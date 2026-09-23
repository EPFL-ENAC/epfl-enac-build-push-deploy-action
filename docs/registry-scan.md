# Scheduled registry vulnerability scan

The deploy-time Trivy scan only checks an image when it is built. To catch CVEs published **after** a release ships, this repo also provides a reusable scheduled scan: `registry-scan.yml`. For each image it scans the newest release tag (`v*`) plus the mutable `dev`/`stage` tags, and files one GitHub issue in your repo per vulnerable tag+digest (deduplicated by title, so re-runs don't spam).

Create `.github/workflows/registry-scan.yml` in your repository:

```yaml
name: registry-scan
on:
  schedule:
    - cron: "0 3 * * 0" # Every Sunday at 3:00 AM
  workflow_dispatch:

permissions:
  contents: read
  packages: read
  issues: write

jobs:
  scan:
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/registry-scan.yml@v3.10.0
    with:
      # ghcr image paths without the ghcr.io/ prefix
      images: '["epfl-enac/epfl/my-app/frontend","epfl-enac/epfl/my-app/backend"]'
```

Trivy and crane are installed version-pinned with hardcoded checksums (no live apt repo or third-party action at run time).
