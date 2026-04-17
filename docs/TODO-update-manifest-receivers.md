# TODO: Improve update-manifest workflow readability

## Context

The `epfl-enac-build-push-deploy-action` dispatch payload now includes these
additional fields in `client_payload`:

| Field | Example | Description |
|---|---|---|
| `triggered_by` | `johndoe` | GitHub actor who pushed the original commit |
| `source_repo` | `EPFL-ENAC/my-app` | Full repository name that triggered the deploy |
| `source_sha` | `abc123...` | Full commit SHA |
| `source_ref` | `dev`, `v1.0.0` | Branch or tag name |

These are **in addition to** the existing fields (`repo_name`, `repo_org`,
`branch`, `images`, etc.).

## Target repos

- [ ] `EPFL-ENAC/enack8s-app-config`
- [ ] `EPFL-ENAC/openshift-app-config`

## Tasks

### 1. Add `run-name` to the update-manifest workflow

Add a `run-name` directive so the GitHub Actions UI shows meaningful info
instead of "Repository dispatch triggered by guilbep":

```yaml
name: Update Manifest
on:
  repository_dispatch:
    types: [update-manifest]

run-name: >-
  update-manifest: ${{ github.event.client_payload.repo_org }}/${{ github.event.client_payload.repo_name }}
  (${{ github.event.client_payload.branch }})
  by ${{ github.event.client_payload.triggered_by || 'unknown' }}
```

This will display as:
```
update-manifest: epfl-luts/app-test (dev) by johndoe
```

### 2. Improve the git commit message

Find the step that commits the kustomization.yaml changes and update the
commit message to include source context. For example:

```bash
git commit -m "chore(manifest): update $REPO_ORG/$REPO_NAME ($BRANCH) [by $TRIGGERED_BY]"
```

Where `TRIGGERED_BY` comes from `${{ github.event.client_payload.triggered_by }}`.

### 3. Backward compatibility

These new fields may be absent in dispatches from older versions of the action.
Use fallbacks everywhere:

```yaml
${{ github.event.client_payload.triggered_by || 'unknown' }}
${{ github.event.client_payload.source_repo || '' }}
${{ github.event.client_payload.source_ref || '' }}
```

### 4. Apply to both repos

The same changes should be applied to both `enack8s-app-config` and
`openshift-app-config` workflows.
