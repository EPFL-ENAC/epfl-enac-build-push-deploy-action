# update-manifest: how the overlays get updated

`deploy.yml` ends by telling each Argo repo which digests and chart version
to deploy. This page is the contract between the sender (this action, or
the GitLab component) and the receivers (`update_manifest.yaml` in
[enack8s-app-config](https://github.com/EPFL-ENAC/enack8s-app-config) and
[openshift-app-config](https://github.com/EPFL-ENAC/openshift-app-config)).

## The payload

A `repository_dispatch` of type `update-manifest` to the Argo repo:

```json
{
  "event_type": "update-manifest",
  "client_payload": {
    "repo_org": "epfl-luts",
    "repo_name": "app-test",
    "branch": "dev",
    "images": [
      {"name": "ghcr.io/epfl-enac/epfl-luts/app-test/frontend",
       "digest": "sha256:608087b5…", "ref_name": "dev"}
    ],
    "helm_chart_name": "app-test",
    "helm_chart_version": "1.0.1234-dev",
    "create_pull_request": false,
    "triggered_by": "jdoe", "source_repo": "EPFL-ENAC/app-test", "source_sha": "abc123…"
  }
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `repo_org`, `repo_name`, `branch` | yes | the overlay: `<repo_org>/<repo_name>/overlays/<branch>/kustomization.yaml` |
| `images[]` | no | each entry sets `digest` and `newTag` (= `ref_name`) of the `images` entry with that `name` |
| `digest`, `ref_name` (top level) | no | legacy form: updates the first image of the overlay |
| `helm_chart_name`, `helm_chart_version` | no | sets that chart's `version` under `helmCharts` |
| `create_pull_request` | no | on `prod`, `false` commits straight to `main`; anything else opens a PR |
| `triggered_by`, `source_*` | no | shown in the run name and the commit message |

## What the receiver does

Both Argo repos, and the GitLab
[build-push-deploy](https://gitlab.epfl.ch/EPFL-ENAC/build-push-deploy)
component, run the same [`scripts/update-manifest.sh`](../scripts/update-manifest.sh),
pinned by commit SHA. It:

1. reads the overlay at `main` through the GitHub API;
2. sets `digest` and `newTag` of each matching image, skipping names the
   overlay does not list, and **fails** if none matches;
3. sets the chart version, if the overlay lists that chart;
4. stops if nothing changed; otherwise commits on `main` (retrying if
   `main` moved), or on `prod` with `create_pull_request`, commits on a new
   branch and opens a PR.

`make test` runs the script against a fake GitHub API.

## Compatibility

The payload has not changed since v3.0: every field above is accepted, the
legacy top-level `digest` still works, and `create_pull_request` keeps its
default (a PR on `prod`). What changed in v3.9.0 is on the receiver side
only: a payload whose images match nothing in the overlay fails the run
instead of committing nothing, and prod PRs are authored by the Actions
bot rather than a git identity. No app needs to change anything to keep
deploying.

## Sending one by hand

```sh
curl -X POST -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $CD_TOKEN" \
  https://api.github.com/repos/EPFL-ENAC/enack8s-app-config/dispatches \
  -d '{"event_type": "update-manifest", "client_payload": {
        "repo_org": "epfl-luts", "repo_name": "app-test", "branch": "prod",
        "create_pull_request": true,
        "images": [{"name": "ghcr.io/epfl-enac/epfl-luts/app-test", "digest": "sha256:…", "ref_name": "v1.0.0"}]}}'
```

The receivers assume kustomize overlays laid out as in the Argo repos'
READMEs. Questions: the ENAC-IT DevOps team.
