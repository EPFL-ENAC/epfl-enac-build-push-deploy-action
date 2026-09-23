# EPFL ENAC-IT Continuous Deployment

Reusable GitHub Actions workflows that take an app from a push to a running
pod on ENAC's clusters: build the images, scan them, push them to the
registries, publish the Helm chart, and point the Argo CD overlay at the new
digests. Works for EPFL-ENAC repositories and for other organizations'.

## The three workflows

| Workflow | Use it when | Docs |
| --- | --- | --- |
| **`deploy.yml`** | every push to `dev`, `test`, `stage` or a `v*` tag should deploy that environment | [reference](docs/deploy.md) |
| **`registry-scan.yml`** | you want a weekly Trivy scan of the images already deployed, with an issue per finding | [setup](docs/registry-scan.md) |
| **`mirror-to-gitlab.yml`** | a branch deploys from gitlab.epfl.ch and GitHub must push it there after every merge | [setup](docs/mirror-to-gitlab.md) |

## Quick start

A `Dockerfile` at the root of your repository, and this file as
`.github/workflows/deploy.yml`:

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
      org: epfl-luts # your org
      repo: app-test # your app name, usually the repository name
```

A push to `dev` builds `ghcr.io/epfl-enac/epfl-luts/app-test:<sha>`, scans
it, and updates `epfl-luts/app-test/overlays/dev` in enack8s-app-config;
`test` and `stage` do the same for their overlay; a tag `v1.2.3` updates
`prod`. `CD_TOKEN` comes from ENAC-IT with the hosting agreement (already an
org secret for EPFL-ENAC repositories).

Several images, other registries, private dependencies, build args, image
reuse, a Helm chart: [docs/deploy.md](docs/deploy.md).

## Documentation map

| Read this | When |
| --- | --- |
| [deploy.yml reference](docs/deploy.md) | inputs, secrets, multi-image, multi-registry, build args, reuse, chart |
| [update-manifest](docs/update-manifest.md) | what the Argo repos receive, what the receiver does, compatibility guarantees |
| [Mirroring a branch to GitLab](docs/mirror-to-gitlab.md) | setting up `mirror-to-gitlab.yml`: deploy key, protected branch, host key |
| [Scheduled registry scan](docs/registry-scan.md) | setting up `registry-scan.yml` |
| [Deploying from GitLab](https://github.com/EPFL-ENAC/enack8s-app-config/blob/main/docs/gitlab-ci.md) | how the GitHub and GitLab deploy paths fit together: runners, credentials, trust rules |
| [Migrate a deploy to GitLab](https://gitlab.epfl.ch/EPFL-ENAC/build-push-deploy/-/blob/main/docs/migrate-from-github.md) | moving one branch of your app to gitlab.epfl.ch: before/after, what changes, the steps |
| [build-push-deploy component](https://gitlab.epfl.ch/EPFL-ENAC/build-push-deploy) | the GitLab CI port of `deploy.yml` and [what it still lacks](https://gitlab.epfl.ch/EPFL-ENAC/build-push-deploy/-/work_items/1) |
| [enack8s-app-config README](https://github.com/EPFL-ENAC/enack8s-app-config#readme) | onboarding an app on the cluster: overlays, secrets, namespaces |
| [Architecture](docs/architecture.md) | how the jobs fit together and why |

## Versions and compatibility

Pin a tag (`@v3.10.0`); see [CHANGELOG.md](CHANGELOG.md). Minor versions
add inputs and never change what an existing call does. The manifest
payload is stable since v3.0, and the Argo repos accept every past form of
it: see [Compatibility](docs/update-manifest.md#compatibility). Upgrading
from 3.1.0 or earlier: [docs/migrating-from-3.1.md](docs/migrating-from-3.1.md).
