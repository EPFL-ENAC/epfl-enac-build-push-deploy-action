# Mirroring a branch to GitLab

GitLab CE cannot pull from GitHub, and a push nobody remembers is a silent
non-deploy. `mirror-to-gitlab.yml` pushes the branch after every change:

```yaml
name: mirror-to-gitlab
"on":
  push:
    branches: [dev]
permissions:
  contents: read
jobs:
  mirror:
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/mirror-to-gitlab.yml@v3.10.0
    with:
      gitlab_repo: EPFL-ENAC/my-app
    secrets:
      deploy_key: ${{ secrets.GITLAB_DEPLOY_KEY }}
```

Setup, once per app:

1. `ssh-keygen -t ed25519 -N '' -f gitlab-mirror` on your machine.
2. GitLab project → Settings → Repository → Deploy keys: add `gitlab-mirror.pub` with **Grant write permissions**.
3. Same page, Protected branches: allow that deploy key to push to the branch you mirror. A deploy key is scoped to that project and, through this, to that branch.
4. GitHub repo → Settings → Secrets → Actions: `GITLAB_DEPLOY_KEY` = the private key. Delete the local file.

The workflow pins gitlab.epfl.ch's SSH host key (fingerprint
`SHA256:/OhwCKIqMSKkZP0RgiQ5f0qS64EsnYL++6Y+Gbmx7tU`); compare it with
<https://gitlab.epfl.ch/help/instance_configuration> before accepting a
change to it. When GitHub Actions is down, push by hand:
`git push git@gitlab-ssh.epfl.ch:EPFL-ENAC/my-app.git origin/dev:dev`.
