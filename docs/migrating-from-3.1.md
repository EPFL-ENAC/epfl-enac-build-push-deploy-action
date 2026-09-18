# Migrating a caller from v3.1.0 to v3.8.0

Four minor releases on 17 and 18 September 2026 (3.2.0 to 3.8.0). Each step below is optional except the first, and each says what it changes on your side. Measured on co2-calculator (three build contexts, two registries): a dev deploy went from a 152s median push-to-manifest to 76 to 92s on a code commit and 35s on a commit that touches no image, with fewer Argo syncs.

## Step 1: bump the ref, nothing else

```yaml
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3.8.0
```

No input is required. What changes on the bump alone:

| What | Before | After | Check on your side |
| --- | --- | --- | --- |
| Layer cache | GitHub Actions cache API (`type=gha`) | `<image>:buildcache` tag on ghcr (`type=registry,mode=max`) | Nothing. The old cache entries expire on their own; one extra tag per image on ghcr. The first run is a cold cache. |
| Push jobs | one job per image × registry | copies and tags run at the end of each build job, after the Trivy scan | Branch protection or dashboards that name `deploy / push (...)` jobs: those jobs no longer exist. Build jobs are named `build <image>`. |
| update-manifest | one job per Argo repo | one job, dispatches to each repo in turn | Nothing. Payload unchanged. |
| Provenance attestation | on | off | Nothing. Removes the `unknown/unknown` manifest from the pushed index. |
| Trivy | `.deb` install, image pulled back from ghcr | tarball install, scans the archive the build wrote | Nothing. Same DB, same severities, same gate. |
| Actions | Node 20 majors | checkout v7, buildx v4, login v4, build-push v7, metadata v6, artifacts v7/v8 | Nothing. Silences the Node 20 deprecation warnings. |
| Buildx builder | removed in post-cleanup | left on the discarded runner (`cleanup: false`) | Nothing. |

Rollback is the same line back to `@v3.1.0`. The `:buildcache` tags and the labels described below are harmless leftovers.

## Step 2: check your Dockerfile for a per-commit value above the dependency install

This was the single largest win on co2-calculator and needs no action input. BuildKit folds `ARG` and `ENV` values into the cache key of every later `RUN`. A value that changes on every commit, declared above `npm ci` or `uv sync`, reinstalls every package on every push:

```dockerfile
# before: npm ci reinstalled 545 packages on every commit (46 to 62s)
ARG GIT_SHA=dev
ENV GIT_SHA=${GIT_SHA}
COPY package-lock.json ./
RUN npm ci

# after: the deps layer is cached across commits (20 to 26s)
COPY package-lock.json ./
RUN npm ci
ARG GIT_SHA=dev
ENV GIT_SHA=${GIT_SHA}
```

Move any such `ARG`/`ENV` below the last dependency install. The value still reaches the build the same way.

## Step 3 (optional): let the action publish your Helm chart

If you run your own chart job in front of `deploy` because `update-manifest` needs the chart version, it costs about 14s of critical path per run while the chart is only consumed at the end. Replace it:

```yaml
    with:
      helm_chart_name: my-app
      helm_chart_path: ./helm
      # only if your chart needs values to render at all; one `helm template` per line
      helm_chart_render_args: |
        --set backend.existingSecret.name=ci-existing-secret
```

Then delete your chart job, its `needs:` entry on `deploy`, and the `helm_chart_version:` input. The version scheme is the one most callers already use, `1.0.<run_number>` for tags, `-rc` on stage, `-dev` elsewhere, so the sequence continues where yours stopped. The chart is pushed to `oci://ghcr.io/<your repo, lowercased>/helm`.

## Step 4 (optional): compute build args inside the build job

If you run a job in front of `deploy` only to compute a build arg that needs the checkout, such as a version read from `package.json`, move the script into `build_args_script`. Its stdout lines are `KEY=VALUE` build args; diagnostics go to stderr.

```yaml
    with:
      build_args: |
        GIT_SHA=${{ github.sha }}
      build_args_script: |
        VERSION=$(node -p "require('./package.json').version")
        echo "APP_VERSION=$VERSION-$(TZ=UTC git show -s --format=%cd --date=format-local:%Y-%m-%d-%H%M HEAD)"
```

The script runs once per image, in parallel. Derive stamps from the commit (`git show`), not from the clock, or two images of one deploy can carry different minutes. Saves about 10s per run.

## Step 5 (optional): reuse unchanged images and the chart

Off by default. With it on, an image whose build context did not change since the last push on the branch is re-tagged with the new sha instead of rebuilt, the chart keeps its published version when `helm/` did not change, and a push that changes neither skips the Argo dispatch entirely.

```yaml
    with:
      reuse_unchanged_images: true
      build_key_paths: package.json      # paths outside the contexts that must rebuild everything
      rescan_reused_images: false        # only if a scheduled registry scan covers you
```

Before turning it on, decide three things:

1. **Version stamps.** A reused image keeps the build args it was built with. A pod then reports the version of the commit that last changed its component, which is the code it runs, not the current commit. If a stamp is read from a file outside the build contexts (a root `package.json`), list it in `build_key_paths` so a bump rebuilds everything.
2. **Scanning.** By default a reused image is pulled and rescanned with the current DB, so the gate is the same as for a rebuild (6 to 13s per reused image). Set `rescan_reused_images: false` only if `registry-scan.yml` or an equivalent scans your deployed tags on a schedule.
3. **Overlays.** Your manifest repo must reference images by digest (the `update_manifest` workflows in enack8s-app-config and openshift-app-config do). A re-tag keeps the digest, so nothing moves in the overlay for a reused image.

The first push after enabling rebuilds every image and publishes one chart once, to write the `enac.build.key` label and annotation. From then on each run's summary page shows a table per image and for the chart: decision, reason, build key and previous key. Build jobs are named `reuse <image>` when reused.

## Verifying before you merge

Push a branch named `ci-test/<anything>` with the new `uses:` ref. The whole workflow runs, images are pushed under their sha tag, and the Argo dispatch is skipped because the branch is not `dev`, `develop`, `test`, `stage` or a tag. Read the run summary and the job names, then merge.

## What co2-calculator's caller looks like after all five steps

```yaml
jobs:
  deploy:
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3.8.0
    secrets:
      token: ${{ secrets.CD_TOKEN }}
      registry_token: ${{ secrets.QUAY_TOKEN }}
    with:
      ORG: epfl
      REPO: co2-calculator
      build_context: '[ "./frontend", "./backend", "./docs" ]'
      registries: |
        [ { "registry": "ghcr.io", "argo_repositories": ["EPFL-ENAC/enack8s-app-config"] },
          { "registry": "quay-its.epfl.ch", "registry_path": "svc1751", "registry_username": "svc1751+ghaction",
            "argo_repositories": ["EPFL-ENAC/openshift-app-config"] } ]
      helm_chart_name: co2-calculator
      helm_chart_path: ./helm
      helm_chart_render_args: |
        --set backend.existingSecret.name=ci-existing-secret
      build_args: |
        GIT_SHA=${{ github.sha }}
      build_args_script: |
        echo "APP_VERSION=$(node -p "require('./package.json').version")-dev-$(TZ=UTC git show -s --format=%cd --date=format-local:%Y-%m-%d-%H%M HEAD)"
      reuse_unchanged_images: true
      rescan_reused_images: false
      build_key_paths: package.json
```

Two jobs (`app-version`, `publish-chart`) and one workflow file (`publish_chart.yaml`) were deleted from the caller in the process. The full measurements are in [co2-calculator issue 2859](https://github.com/EPFL-ENAC/co2-calculator/issues/2859).
