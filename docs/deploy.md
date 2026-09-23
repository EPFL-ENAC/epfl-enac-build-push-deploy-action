# deploy.yml reference

The reusable workflow that builds, scans, pushes and deploys an app. The
[README](../README.md) has the quick start; this page has every input, one
recipe per feature with a repository that uses it, and how the jobs fit
together.

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `org` | required | org folder in the Argo repos (`<org>/<repo>/overlays/<env>`) |
| `repo` | required | app folder in the Argo repos, usually the repository name |
| `build_context` | `'["./"]'` | JSON array of directories holding a `Dockerfile`; one image each, up to 9. See [Several images](#several-images) |
| `image_name` | `repo` | image name for the root context only (`.` or `./`) |
| `registries` | | JSON array of registries and the Argo repos each one feeds. See [Several registries](#several-registries) |
| `registry`, `registry_path`, `registry_username` | `ghcr.io`, `""`, `github.actor` | single-registry form, used when `registries` is empty |
| `argo_repository` | `'["EPFL-ENAC/enack8s-app-config"]'` | Argo repos for the single-registry form |
| `build_args` | | extra `KEY=VALUE` build args, one per line, for every image. See [Build args](#build-args) |
| `build_args_script` | | shell run from the repo root in each build job; every stdout line is a build arg. For values that need the checkout (a version file, the commit date) |
| `reuse_unchanged_images` | `false` | re-tag the image already deployed on this branch when its inputs did not change. See [Reusing unchanged images](#reusing-unchanged-images) |
| `rescan_reused_images` | `true` | Trivy-scan a reused image too; set `false` only when [`registry-scan.yml`](registry-scan.md) covers the project |
| `build_key_paths` | | repo paths outside the contexts that must also trigger a rebuild, one per line |
| `skip_vulnerability_scan` | `true` | `false` runs Trivy on every built image; HIGH/CRITICAL findings block the rollout |
| `helm_chart_path` | | chart directory to package and push. See [Publishing a Helm chart](#publishing-a-helm-chart) |
| `helm_chart_render_args` | | one smoke `helm template` per line, the line appended as arguments |
| `helm_chart_name`, `helm_chart_version` | | chart coordinates sent to the Argo repos; `helm_chart_version` is ignored when `helm_chart_path` is set |
| `create_pull_request` | `false` | on a tag, open a PR in the Argo repos instead of committing `prod` on `main` |
| `lfs`, `submodules` | `false` | `git lfs pull` at checkout; `true` or `recursive` for submodules |

Secrets:

| Secret | | |
| --- | --- | --- |
| `token` | required | dispatches to the Argo repos. `CD_TOKEN` is an org secret for EPFL-ENAC repositories; other orgs get it from ENAC-IT with the hosting agreement |
| `private_key` | | SSH key passed as the `SSH_PRIVATE_KEY` build arg. See [Private dependencies](#private-dependencies) |
| `registry_token`, `registry_token_2` | | credentials of the first and second non-ghcr registry |

What a push deploys: `dev`, `test` and `stage` update the overlay of the
same name; a tag `v1.2.3` updates `prod`; any other branch builds and pushes
but touches no overlay.

## Recipes

Each recipe links a repository that uses it: real, current, and reviewed.

### One image

A `Dockerfile` at the repository root. The image is
`ghcr.io/<owner>/<org>/<repo>:<sha>`, for example
`ghcr.io/epfl-enac/epfl-luts/app-test:<sha>`.

```yml
# https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action#readme
name: deploy

'on':
  push:
    branches: [dev, test, stage]
    tags: ['v*.*.*']

jobs:
  deploy:
    permissions:
      contents: read
      packages: write
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3.10.0
    secrets:
      token: ${{ secrets.CD_TOKEN }}
    with:
      org: epfl-luts
      repo: app-test
      image_name: custom-api # optional: ghcr.io/epfl-enac/epfl-luts/custom-api instead of .../app-test
```

`image_name` in use:
[eesd-mmsdb](https://github.com/EPFL-ENAC/eesd-mmsdb/blob/HEAD/.github/workflows/deploy.yml),
[eso-opas](https://github.com/EPFL-ENAC/eso-opas/blob/HEAD/.github/workflows/deploy.yml).

### Several images

One directory per image, each with its `Dockerfile`. The image name is the
last path segment of the context, and the path becomes
`ghcr.io/<owner>/<org>/<repo>/<name>`; `image_name` does not apply.

```yml
    with:
      org: ethz-alice
      repo: arema
      build_context: '["./modules/auth", "./modules/organization", "./modules/projects", "./modules/router"]'
```

gives `ghcr.io/epfl-enac/ethz-alice/arema/auth:<sha>`, `.../organization`,
`.../projects` and `.../router`. In use:
[ALICE-ETHZ-AREMA](https://github.com/EPFL-ENAC/ALICE-ETHZ-AREMA/blob/HEAD/.github/workflows/deploy.yml),
[EML-Water-Portal](https://github.com/EPFL-ENAC/EML-Water-Portal/blob/HEAD/.github/workflows/deploy.yml),
[AddLidar](https://github.com/EPFL-ENAC/AddLidar/blob/HEAD/.github/workflows/deploy.yml).

### Several registries

Each image is built once, pushed to ghcr.io, then copied byte-identical
(same digest) to every other registry, and each registry's Argo repos get
the dispatch.

```yml
    secrets:
      token: ${{ secrets.CD_TOKEN }}
      registry_token: ${{ secrets.CUSTOM_REGISTRY_TOKEN }}
    with:
      org: epfl-luts
      repo: app-test
      build_context: '["./backend", "./frontend"]'
      registries: |
        [
          {"registry": "ghcr.io",
           "argo_repositories": ["EPFL-ENAC/enack8s-app-config"]},
          {"registry": "registry.example.com", "registry_path": "my-project",
           "registry_username": "deploy-bot",
           "argo_repositories": ["EPFL-ENAC/openshift-app-config"]}
        ]
```

| Field | Required | Meaning |
| --- | --- | --- |
| `registry` | yes | hostname |
| `registry_path` | no | path prefix for the image names |
| `registry_username` | no | login user, default `github.actor` |
| `argo_repositories` | no | Argo repos to update for this registry |

ghcr.io logs in with `GITHUB_TOKEN`; the first non-ghcr registry uses
`registry_token`, the second `registry_token_2`. In use (ghcr + quay-its,
enack8s + OpenShift):
[co2-calculator](https://github.com/EPFL-ENAC/co2-calculator/blob/HEAD/.github/workflows/deploy.yml),
[enac-ai-reviewer](https://github.com/EPFL-ENAC/enac-ai-reviewer/blob/HEAD/.github/workflows/deploy.yml).

### Private dependencies

A build that needs a private repository gets an SSH key as the
`SSH_PRIVATE_KEY` build arg. In use:
[lasur-ws](https://github.com/EPFL-ENAC/lasur-ws/blob/HEAD/.github/workflows/deploy.yml).

1. `ssh-keygen -t ed25519 -C "github-actions@github.com"` with no passphrase.
2. Add the public key as a **deploy key** of the private repository.
3. Store the private key, base64 on one line (`base64 -w 0`), as
   `SSH_PRIVATE_KEY` in your repository's Actions secrets, and pass it:

```yml
    secrets:
      token: ${{ secrets.CD_TOKEN }}
      private_key: ${{ secrets.SSH_PRIVATE_KEY }}
```

```dockerfile
RUN apt-get update && apt-get install -y openssh-client git
ARG SSH_PRIVATE_KEY
RUN mkdir -p /root/.ssh && \
    echo "${SSH_PRIVATE_KEY}" | base64 -d > /root/.ssh/id_ed25519 && \
    chmod 600 /root/.ssh/id_ed25519 && \
    echo "StrictHostKeyChecking no" >> /root/.ssh/config
# ... the steps that need the private repository ...
RUN rm -rf /root/.ssh/
```

A build arg persists in the image history: remove the key in the same stage,
or use a multi-stage build so the final image never held it.

### Build args

`build_args` reaches every Dockerfile in the matrix; one that declares no
matching `ARG` ignores it with a Docker warning. The usual one is the deploy
SHA, so a frontend can tag its error-tracker events with the exact release:

```yml
    with:
      build_context: '["./frontend", "./backend"]'
      build_args: |
        GIT_SHA=${{ github.sha }}
```

```dockerfile
ARG GIT_SHA=dev
ENV VITE_APP_VERSION=$GIT_SHA
```

```ts
Sentry.init({ release: `my-app@${import.meta.env.VITE_APP_VERSION}` })
```

For a value that needs the checkout, `build_args_script` runs in the build
job and every stdout line becomes a build arg. Derive it from the commit,
not the clock: the images build in parallel and must agree.

```yml
      build_args_script: sh scripts/app-version.sh
```

In use, with the script shared with the GitLab pipeline:
[co2-calculator](https://github.com/EPFL-ENAC/co2-calculator/blob/HEAD/scripts/app-version.sh).
Never pass credentials as build args: they stay readable in the image config
and layers.

### Reusing unchanged images

Off by default. With `reuse_unchanged_images: true`, every built image
carries the label `enac.build.key`: a sha256 over the git tree of its
context plus every path in `build_key_paths`. On the next push to the same
branch, an image whose key matches the one on `<image>:<branch>` is not
rebuilt: its digest is re-tagged with the new sha in about a second,
rescanned with today's Trivy DB unless `rescan_reused_images: false`, and
distributed as usual. The chart follows the same rule through an
`enac.build.key` annotation in `Chart.yaml`: unchanged, it keeps the version
already published for the branch, so the overlay line does not move. When
nothing changed at all, no dispatch is sent.

```yaml
    with:
      build_context: '["./frontend", "./backend", "./docs"]'
      reuse_unchanged_images: true
      build_key_paths: package.json
```

- A reused image keeps the build args it was built with: a version stamp
  read from a file outside the contexts (a root `package.json`) must be in
  `build_key_paths`, or a bump does not rebuild.
- Tag pipelines always rebuild. The first push after enabling rebuilds
  everything once, because older images carry no label.
- The run summary lists every image and the chart with the decision and
  both keys; the job is named `build <image>` or `reuse <image>`.
- The GitLab [build-push-deploy](https://gitlab.epfl.ch/EPFL-ENAC/build-push-deploy)
  component uses the same formula and label, so both paths recognise each
  other's images.

In use:
[co2-calculator](https://github.com/EPFL-ENAC/co2-calculator/blob/HEAD/.github/workflows/deploy.yml).

### Publishing a Helm chart

```yaml
    with:
      build_context: '["./frontend", "./backend"]'
      helm_chart_name: my-app
      helm_chart_path: ./helm
      helm_chart_render_args: |
        --set backend.existingSecret.name=ci-existing-secret
        --set backend.existingSecret.enabled=false --set backend.secrets.JWT_HMAC_KEY=x
```

The chart is rendered once per line of `helm_chart_render_args` (all must
succeed), packaged as `1.0.<run number>` on a tag, `-rc` on `stage`, `-dev`
elsewhere, and pushed to `oci://ghcr.io/<repository>/helm`. The job runs
beside the image builds; only the manifest update waits for it, and
receives the version as `helm_chart_version`. In use:
[co2-calculator](https://github.com/EPFL-ENAC/co2-calculator/blob/HEAD/helm).

### LFS and submodules

```yml
    with:
      lfs: true
      submodules: recursive
```

No EPFL-ENAC repository uses either today; if yours is the first, add it
here.

## How it works

```
define-matrix ─┬─ build <image> (one job per build context, in parallel) ─┐
               └─ publish-chart (optional) ───────────────────────────────┴─ update-manifest
```

1. **define-matrix** (~5 s): computes the build contexts, the registry
   targets and the Argo repos. With reuse on, it also computes each image's
   build key and reads the key of the image currently tagged with this
   branch on ghcr.
2. **build \<image\>**, one job per context, in parallel: builds with
   BuildKit and pushes `:sha` to ghcr.io with the key as a label, or re-tags
   the existing digest; scans with Trivy; copies the sha tag to every other
   registry with [crane](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md);
   applies the branch or release tags; uploads the image data.
3. **publish-chart** (with `helm_chart_path`): renders, packages and pushes
   the chart, or keeps the published version when the chart is unchanged.
4. **update-manifest**: one dispatch per Argo repo with the digests, tags
   and chart version; the receiver runs
   [`scripts/update-manifest.sh`](update-manifest.md). Skipped when
   everything was reused.

ghcr.io is the source of truth; every other registry holds an exact copy of
the scanned image.

### Layer cache

Layers are cached on ghcr next to the image, under `<image>:buildcache`
(`type=registry, mode=max`), so a dependency install layer (npm, uv, pip) is
reused as long as the lockfile above it is unchanged. Keep per-commit
values (`ARG GIT_SHA`, version stamps) **below** the dependency install in
the Dockerfile: BuildKit folds ENV and ARG into the cache key of every later
RUN, and a value that changes on every commit above `npm ci` reinstalls
everything on every push. BuildKit cache mounts
(`RUN --mount=type=cache,...`) help local builds only; hosted runners start
empty.

Tools (crane, Trivy) are installed version-pinned with hardcoded checksums:
nothing runs from a live apt repo or a third-party action at run time.
