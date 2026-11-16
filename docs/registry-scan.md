# Scheduled registry vulnerability scan

When an image is built, the deploy-time Trivy scan checks it once. To catch CVEs published **after** a release ships, this repo also provides a reusable scheduled scan: `registry-scan.yml`. For each image, it scans the newest release tag plus the mutable `dev`/`stage` tags. It uploads the Trivy results as SARIF to GitHub code scanning. Each CVE becomes a code scanning alert in your repo. When a later scan no longer reports a CVE, GitHub closes its alert.

Each upload has a category `registry-scan/<image>:<slot>`. The slot is `release` for the newest final release tag (`vX.Y.Z`, no pre-release suffix), and `dev` or `stage` for those tags. A new release reuses the `release` category, so it replaces the old release's alerts.

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
  security-events: write
  actions: read

jobs:
  scan:
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/registry-scan.yml@v4.0.0
    with:
      # ghcr image paths without the ghcr.io/ prefix
      images: '["epfl-enac/epfl/my-app/frontend","epfl-enac/epfl/my-app/backend"]'
```

Trivy and crane are installed version-pinned with hardcoded checksums (no live apt repo at run time). Trivy runs outside your checkout, so a `.trivyignore` or `trivy.yaml` in your repository does not change this scan. Only vulnerabilities are reported, not secrets.

Notes:

- Each alert message names this workflow and its commit. It also gives the Trivy version, the DB date, the image digest, and the run.
- The scan opens no issue. After a run, look under **Security > Code scanning** for new alerts.
- If you remove an image from `images` or delete its `dev` or `stage` tag, its category gets no more uploads and its alerts stay open. Delete that configuration on the alert page.
- Private repositories need GitHub Code Security enabled. Without it, the SARIF upload fails.
- Alerts appear under **Security > Code scanning**. Filter them by the category to see one image and slot.
- Older versions of this workflow opened one issue per finding. This version does not close those issues. Close them by hand.
