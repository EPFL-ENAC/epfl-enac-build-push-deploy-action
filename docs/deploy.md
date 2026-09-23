# deploy.yml reference

The reusable workflow that builds, scans, pushes and deploys an app. Quick
start and the documentation map are in the [README](../README.md).

## Architecture

```
define-matrix ─┬─ build <image> (one job per build context, in parallel) ─┐
               └─ publish-chart (optional) ───────────────────────────────┴─ update-manifest
```

1. **define-matrix** (about 5s): computes the build contexts, the registry targets and the manifest repos. For each image it also computes a build key (sha256 over the git tree of the context plus `build_key_paths`) and reads the key of the image currently tagged with this branch on ghcr. Same key → that image is marked for reuse.
2. **build \<image\>**, one job per context, all in parallel:
   - **changed inputs**: builds once with BuildKit, pushes `:sha` to ghcr.io with the build key as the `enac.build.key` label, caches every layer on ghcr under `:buildcache` (`type=registry, mode=max`), scans the built archive with Trivy (HIGH/CRITICAL block the rollout);
   - **unchanged inputs** (opt-in, `reuse_unchanged_images`): re-tags the digest already deployed on this branch with the new sha, about 1s, and rescans it with today's DB unless `rescan_reused_images: false`;
   - then, either way: copies the sha tag to every other registry with [crane](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md) (byte-identical, **same digest**), applies the branch or release tags, and uploads the image data for the manifest step.
3. **publish-chart** (only with `helm_chart_path`): renders, packages and pushes the Helm chart beside the builds; only update-manifest waits for it. With reuse on, an unchanged chart directory keeps the version already published for the branch.
4. **update-manifest**: one job, dispatches the image digests, tags and chart version to every Argo repo. Skipped when every image was reused and the chart is unchanged: the overlays already hold exactly that, and a dispatch would only make Argo sync a no-op and run its hooks.

ghcr.io is the source of truth; every other registry holds an exact copy of the scanned image. With reuse on, a docs-only commit in a repo with three contexts rebuilds one image and re-tags two.

### Docker Build Caching

Layers are cached on ghcr next to the image, under `<image>:buildcache` (`cache-to: type=registry,mode=max`). `mode=max` keeps intermediate stages too, so a dependency install layer (npm, uv, pip) is reused as long as the lockfile above it is unchanged. Keep per-commit values (`ARG GIT_SHA`, version stamps) **below** the dependency install in the Dockerfile: BuildKit folds ENV and ARG into the cache key of every later RUN, and a value that changes on every commit above `npm ci` reinstalls everything on every push.

BuildKit cache mounts (`RUN --mount=type=cache,target=/root/.npm npm ci`) still help local builds, but hosted runners start empty every job, so in CI only the layer cache counts.

## For repository with one image

You need to have a Dockerfile at the root of your repository, that's it,
The image pushed to the registry will follow org/repo convention: ghcr.io/epfl-enac/epfl-luts/app-test:{sha256}

```yml
# https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action#readme
name: deploy

'on':
  push:
    branches:
      - dev
      - test
      - stage
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
      org: epfl-luts # your org
      repo: app-test # your app name, usual convention is name of your repository
```

Optional: override the image name when the build context is the repository root ("./" or "."). This is useful for complex repos where the default name (repo) does not match the desired image name.

```yml
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
      image_name: custom-api # will produce ghcr.io/<owner-lowercased>/epfl-luts/custom-api for root context
```

To add LFS and/or submodule support, add the corresponding inputs:

```yml
    with:
      org: epfl-luts
      repo: app-test
      lfs: true
      submodules: true
```

## For repository with multi images

Pass an additional input: `build_context` which is a list of directories with a Dockerfile in each.
- The image names are derived automatically from the last path segment of each context.
  - Example: "./modules/auth" -> image name "auth"
  - Example: "./auth" -> image name "auth"
- The full image path becomes: ghcr.io/<owner-lowercased>/<org>/<repo>/<name>
- Note: `image_name` only applies to the root context ("./" or "."); it does not change names for subdirectory contexts.

Example:

```yml
# https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action#readme
name: deploy

'on':
  push:
    branches:
      - dev
      - test
      - stage
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
      org: ethz-alice # your org
      repo: arema # your app name, usual convention is name of your repository
      build_context: '["./modules/auth", "./modules/organization", "./modules/projects", "./modules/router"]'
```

The images pushed to the registry will be:
  - ghcr.io/epfl-enac/ethz-alice/arema/auth:{sha256}
  - ghcr.io/epfl-enac/ethz-alice/arema/organization:{sha256}
  - ghcr.io/epfl-enac/ethz-alice/arema/projects:{sha256}
  - ghcr.io/epfl-enac/ethz-alice/arema/router:{sha256}

## Multi-registry deployment

To push the same images to multiple registries (e.g., ghcr.io AND a custom registry) and update different manifest repos for each:

```yml
jobs:
  deploy:
    permissions:
      contents: read
      packages: write
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3.10.0
    secrets:
      token: ${{ secrets.CD_TOKEN }}
      registry_token: ${{ secrets.CUSTOM_REGISTRY_TOKEN }}
    with:
      org: epfl-luts
      repo: app-test
      build_context: '["./backend", "./frontend"]'
      registries: |
        [
          {
            "registry": "ghcr.io",
            "argo_repositories": ["EPFL-ENAC/enack8s-app-config"]
          },
          {
            "registry": "registry.example.com",
            "registry_path": "my-project",
            "registry_username": "deploy-bot",
            "argo_repositories": ["EPFL-ENAC/openshift-app-config"]
          }
        ]
```

This builds each image **once**, then pushes to both ghcr.io and registry.example.com, and updates separate ArgoCD manifest repos for each registry.

### Registry entry format

Each entry in the `registries` JSON array supports:

| Field | Required | Description |
|---|---|---|
| `registry` | yes | Registry hostname (e.g., `ghcr.io`, `docker.io`) |
| `registry_path` | no | Path prefix for image names (e.g., `my-project`) |
| `registry_username` | no | Username for login (defaults to `github.actor`) |
| `argo_repositories` | no | JSON array of ArgoCD manifest repos to update |

### Registry credentials

- `ghcr.io` registries use `GITHUB_TOKEN` automatically
- The 1st non-ghcr registry uses the `registry_token` secret
- The 2nd non-ghcr registry uses the `registry_token_2` secret

## For a repository that depends on a private repository

If your repository depends on some dependency in a private repository, you will need to provide Github action with a SSH key pair, that will be used in the Docker build. The public key should be added to the repository's deploy keys, and the private key should be added to the repository's secrets.

1. Make a key pair with NO password

```
ssh-keygen -t ed25519 -C "github-actions@github.com"
```

2. Register this key pair with your personal account **Settings > SSH and GPG keys**

3. Usage example:

```yml
jobs:
  deploy:
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3.10.0
    secrets:
      token: ${{ secrets.CD_TOKEN }}
      private_key: ${{ secrets.SSH_PRIVATE_KEY }}
    with:
      # Optional inputs can be passed here
      org: epfl-lasur
      repo: ws
      build_context: '["./"]'
```

where SSH_PRIVATE_KEY is defined in the private repo's **Settings > Secrets and variables > Actions** and public key was added to private repo's **Settings > Deploy keys**

Note: the SSH private key value MUST be on a single line, then use `base64 -w 0` to encode it. Further usage in the Dockerfile will decode it using `base64 -d`

Dockerfile example:

```dockerfile
# Install openssh-client
RUN apt-get update && apt-get install -y openssh-client git

# Add build argument for SSH key
ARG SSH_PRIVATE_KEY

# Set up SSH
RUN mkdir -p /root/.ssh && \
    echo "${SSH_PRIVATE_KEY}" | base64 -d > /root/.ssh/id_ed25519 && \
    chmod 600 /root/.ssh/id_ed25519 && \
    # Accept host keys automatically
    echo "StrictHostKeyChecking no" >> /root/.ssh/config

# Perform actions requiring private repo access
# ...

# Important: Remove the SSH key when no longer needed
RUN rm -rf /root/.ssh/
```

## Passing custom Docker build args (`build_args`)

Use the `build_args` input to pass extra `--build-arg KEY=VALUE` pairs into every image built by the matrix. Each line is one `KEY=VALUE`. The value is appended to the built-in `SSH_PRIVATE_KEY` arg, so both work together.

A typical use case is baking the **git SHA** of the deploy into the image so frontends can report their release to error trackers (Sentry, GlitchTip), and backends can expose a `/version` endpoint.

```yml
jobs:
  deploy:
    permissions:
      contents: read
      packages: write
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3.10.0
    secrets:
      token: ${{ secrets.CD_TOKEN }}
    with:
      org: epfl
      repo: co2-calculator
      build_context: '[ "./frontend", "./backend", "./docs" ]'
      build_args: |
        GIT_SHA=${{ github.sha }}
```

The same `GIT_SHA` is forwarded to **every** Dockerfile in `build_context`. Dockerfiles that don't declare a matching `ARG` simply ignore it — Docker emits a harmless warning and the build proceeds.

### Example: GlitchTip / Sentry release tagging (co2-calculator)

In the **frontend** Dockerfile, accept the arg and expose it as a build-time env var so Vite/webpack inlines it into the bundle:

```dockerfile
# frontend/Dockerfile
FROM node:22-alpine AS build
ARG GIT_SHA=dev
ENV VITE_APP_VERSION=$GIT_SHA
WORKDIR /app
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build
# ...
```

In the frontend code, initialise the Sentry/GlitchTip SDK with the SHA as the release identifier:

```ts
// frontend/src/sentry.ts
import * as Sentry from '@sentry/vue'

Sentry.init({
  dsn: import.meta.env.VITE_GLITCHTIP_DSN,
  release: `co2-calculator@${import.meta.env.VITE_APP_VERSION}`, // name@sha: several projects can share one GlitchTip
  environment: import.meta.env.MODE,
})
```

Now every error event in GlitchTip is tagged with the exact deploy SHA — clicking through from an event to source takes you to the commit that produced the broken bundle.

The **backend** and **docs** Dockerfiles in the same matrix don't need to consume `GIT_SHA`: passing an unused build-arg is a no-op (Docker prints `WARN: ... was not consumed`). If you do want them to expose a version endpoint, just add `ARG GIT_SHA` and use it.

> Source-map upload to GlitchTip is a separate, project-local job (it requires the un-minified source maps which are not part of the runtime image). Keep using the same `${{ github.sha }}` as the release tag in that job and the events will line up.

### Other use cases

- `APP_VERSION=${{ github.ref_name }}` — bake a tag like `v1.2.3` into a backend response header.
- `BUILD_DATE=${{ github.event.head_commit.timestamp }}` — for OCI labels (`repository.updated_at` is the repo's last push on any branch, not this build).

Never pass credentials as build args: they persist in the image config and layer history, readable by anyone who can pull the image. Private package registries need BuildKit `--mount=type=secret`, which this workflow does not expose yet.

## Skipping unchanged images

Off by default. With `reuse_unchanged_images: true`, every built image carries a label `enac.build.key`: a sha256 over the git tree of its build context plus every path in `build_key_paths`. On the next push to the same branch, `define-matrix` compares that key with the one on `<image>:<branch tag>`. Unchanged inputs mean the build job skips checkout, build and Trivy on the archive, re-tags the existing digest with the new sha (about 1s), rescans that image with today's DB (unless `rescan_reused_images: false`, for projects that run the scheduled `registry-scan.yml`), and distributes it as usual. A docs-only commit then no longer rebuilds the frontend and backend.

The chart follows the same rule: its directory's tree hash travels as an `enac.build.key` annotation in Chart.yaml, and an unchanged chart keeps the version already published for the branch instead of taking a new `1.0.<run>` number, so the overlay's `helmCharts` line does not move. When nothing at all changed, update-manifest does not dispatch. Each run's summary page lists every image and the chart with its decision and both keys, and the job is named `build <image>` or `reuse <image>` accordingly. Tag builds always rebuild. A reused image keeps the build args it was built with: a version stamp baked in at build time is the one of the commit that last changed that context, which is the code the pod runs. If that stamp is read from a file outside the contexts (a root `package.json`), list it in `build_key_paths` so a bump rebuilds every image. The first push after enabling rebuilds everything once, because older images have no label.

```yaml
    with:
      build_context: '[ "./frontend", "./backend", "./docs" ]'
      reuse_unchanged_images: true
      build_key_paths: package.json
```

## Publishing a Helm chart

Set `helm_chart_path` and the workflow packages and pushes the chart itself, in a job that runs in parallel with the image builds instead of gating them:

```yaml
    with:
      build_context: '[ "./frontend", "./backend" ]'
      helm_chart_name: my-app
      helm_chart_path: ./helm
      # optional: values needed for the chart to render at all
      helm_chart_render_args: |
        --set backend.existingSecret.name=ci-existing-secret
        --set backend.existingSecret.enabled=false --set backend.secrets.JWT_HMAC_KEY=x
```

Each line of `helm_chart_render_args` is one render; all must succeed before the chart is pushed. The version (`1.0.<run_number>` with a `-dev`/`-rc` suffix by branch) is forwarded to the manifest repos as `helm_chart_version`.

## Inputs
  - `org`:
    The organization name given by ENAC-IT - (mandatory)
  - `repo`:
    The repository name given by ENAC-IT - (mandatory)
  - `lfs`:
    - Enable Git LFS support - (optional)
    - Default is false
  - `submodules`:
    - Enable Git submodules checkout - (optional)
    - Default is false. Can be set to true or 'recursive'
  - `build_args`:
    - Additional Docker build-args, one `KEY=VALUE` per line - (optional)
    - Default is empty
    - Appended to the built-in `SSH_PRIVATE_KEY` arg
    - Forwarded to every image in the build matrix; unconsumed args produce a harmless Docker warning
    - See [Passing custom Docker build args](#passing-custom-docker-build-args-build_args)
  - `token`:
    The secret associated with the deployment_id - (mandatory)
  - `registries`:
    - JSON array of registry configurations for multi-registry push - (optional)
    - If empty, falls back to the single `registry`/`registry_path`/`registry_username` inputs
    - See [Multi-registry deployment](#multi-registry-deployment) for format
  - `build_args_script`:
    - Shell script run in each build job after checkout, from the repository root - (optional)
    - Every stdout line is a `KEY=VALUE` build arg appended to `build_args`; write diagnostics to stderr
    - For values that need the checkout, such as a version read from `package.json` or the commit date. Runs once per image in parallel, so derive from the commit rather than the clock if the images must agree
  - `reuse_unchanged_images`:
    - Opt in to skip the build when an image's inputs are unchanged since the last image pushed for this branch - (optional, default false)
    - See [Skipping unchanged images](#skipping-unchanged-images)
  - `rescan_reused_images`:
    - Run the Trivy scan on reused images too, so the gate is the same as for a rebuild - (optional, default true)
    - Set false only when a scheduled registry scan covers the project
  - `build_key_paths`:
    - Repo paths outside the build contexts that also trigger a rebuild when they change, one per line - (optional)
  - `build_context`:
    - The context of the build - (optional)
    - Currently we support max 9 contexts/ or build image per repository
    - The context is the path to the directory containing the Dockerfile. For example:
      ["./backend", "./admin", "./frontend"], default is ["."]
    - This will result in the following matrix automatically, where `epfl-enac` would be replaced by the repository owner name (in lowercase):
    ```json
    [
      {
        "Dockerfile": "./backend/Dockerfile",
        "context": "./backend",
        "name": "backend",
        "image": "ghcr.io/epfl-enac/${{ENAC_IT4R_CD_ORG}}/${{ENAC_IT4R_CD_REPO}}/backend",
        "id": 1
      },
      {
        "Dockerfile": "./admin/Dockerfile",
        "context": "./admin",
        "name": "admin",
        "image": "ghcr.io/epfl-enac/${{ENAC_IT4R_CD_ORG}}/${{ENAC_IT4R_CD_REPO}}/admin",
        "id": 2
      },
      {
        "Dockerfile": "./frontend/Dockerfile",
        "context": "./frontend",
        "name": "frontend",
        "image": "ghcr.io/epfl-enac/${{ENAC_IT4R_CD_ORG}}/${{ENAC_IT4R_CD_REPO}}/frontend",
        "id": 3
      }
    ]
    ```
    - in the default case (no context provided: will be ["."] or ["./"]), the matrix will be:
    ```json
    [
      {
        "Dockerfile": "./Dockerfile",
        "context": ".",
        "name": "${{ENAC_IT4R_CD_REPO}}",
        "image": "ghcr.io/epfl-enac/${{ENAC_IT4R_CD_ORG}}/${{ENAC_IT4R_CD_REPO}}",
        "id": 1
      }
    ]
    ```
    - Note: "." and "./" are treated the same.
  - `image_name`:
    - Override the image name when the build context is "./" or "." only - (optional)
    - Default is empty (""), which means use the `repo` value (`CD_REPO`)
    - When set, the image built from the root context will be named:
      `ghcr.io/<owner-lowercased>/<org>/<image_name>`
    - Has no effect on subdirectory contexts (e.g., "./modules/auth")
  - `create_pull_request`:
    - Create a pull request in the enack8s-app-config repository - (optional)
    - Default is false, if you create a tag, it will automatically push to main without creating a PR, and deploy within the prod overlay in 5mn or so.
  - `skip_vulnerability_scan`:
    - Skip the Trivy vulnerability scan - (optional)
    - Default is false
  - `helm_chart_path`:
    - Directory of a Helm chart to package and push - (optional)
    - Pushed to `oci://ghcr.io/<repository-lowercased>/helm` as `1.0.<run_number>` (tag), `1.0.<run_number>-rc` (stage) or `1.0.<run_number>-dev` (any other branch)
    - The job runs alongside the image builds; only `update-manifest` waits for it, and receives the version as `helm_chart_version`
    - See [Publishing a Helm chart](#publishing-a-helm-chart)
  - `helm_chart_render_args`:
    - Smoke-test renders before packaging: one `helm template` per non-empty line, each line appended as extra arguments - (optional)
    - Empty runs a single plain `helm template`
  - `helm_chart_name` / `helm_chart_version`:
    - Chart coordinates written into the manifest payload - (optional)
    - `helm_chart_version` is ignored when `helm_chart_path` is set

## Secrets
  - `token`: PAT for dispatching to argo manifest repos - (mandatory)
  - `private_key`: SSH private key for building from private repos - (optional)
  - `registry_token`: Token for 1st non-ghcr registry - (optional)
  - `registry_token_2`: Token for 2nd non-ghcr registry - (optional)

`CD_TOKEN` is provided by ENAC-IT while discussing the hosting agreement.
Add secrets under your repository's Settings → Secrets and variables → Actions.
