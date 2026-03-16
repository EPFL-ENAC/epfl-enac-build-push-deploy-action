# Workflow Architecture — v3

## Problem Statement

In v2, the `build-and-push` job was a single monolithic step. If a project needed to push the same image to two registries (e.g., ghcr.io and an on-prem registry) and update two different ArgoCD manifest repos, the entire workflow had to be duplicated — meaning **the same image was built twice**.

### Goals

1. **Build once, push many** — each Docker image is built exactly once regardless of how many registries are targeted.
2. **Multi-registry support** — push to N registries from a single workflow invocation.
3. **Per-registry manifest updates** — each registry can be associated with its own ArgoCD manifest repositories.
4. **Build caching** — cache Docker layers (including package manager installs) across runs.
5. **Backward compatibility** — existing callers using v2 inputs continue to work without changes.

---

## Job Pipeline

```
define-matrix → build → push → update-manifest
```

### 1. `define-matrix`

Computes three matrices from inputs:

| Matrix | Dimensions | Purpose |
|---|---|---|
| `build_matrix` | build contexts | One entry per Dockerfile/context to build |
| `push_matrix` | build contexts × registries | Cross-product: push each image to each registry |
| `manifest_matrix` | argo repos × registries | One entry per (argo_repository, registry) pair |

**Fallback logic:** When `registries` input is empty, the job constructs a single-element registries array from the legacy `registry`, `registry_path`, `registry_username`, and `argo_repository` inputs.

### 2. `build`

- Matrix: `build_matrix` (one job per build context)
- Builds each Docker image locally (`load: true`, no push)
- Runs Trivy vulnerability scan (unless `skip_vulnerability_scan` is true)
- Writes all layers to GitHub Actions cache (`cache-to: type=gha,mode=max`)
- **No registry login needed** — images are never pushed here

### 3. `push`

- Matrix: `push_matrix` (one job per build context × registry)
- Logs into the target registry
- Rebuilds from GHA cache (`cache-from: type=gha`) — near-instant since all layers are cached
- Pushes to the target registry
- Saves image metadata (name, digest, ref_name, registry) as a GitHub Actions artifact

### 4. `update-manifest`

- Matrix: `manifest_matrix` (one job per argo repository)
- Downloads all image data artifacts from the push step
- Filters images by the registry associated with this argo repository
- Dispatches a `repository_dispatch` event to the argo manifest repo

---

## Data Flow

```
                    ┌─────────────┐
                    │define-matrix│
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │ build_matrix│push_matrix │manifest_matrix
              ▼            ▼            ▼
        ┌───────┐    ┌──────────┐  ┌─────────────────┐
        │ build │    │          │  │                 │
        │ctx: . │    │          │  │                 │
        │ctx: A │    │          │  │                 │
        │ctx: B │    │          │  │                 │
        └───┬───┘    │          │  │                 │
            │        │          │  │                 │
     GHA cache       │          │  │                 │
     (layers)        │          │  │                 │
            │        ▼          │  │                 │
            │   ┌──────────┐   │  │                 │
            └──►│   push   │   │  │                 │
                │ctx:. →R1 │   │  │                 │
                │ctx:. →R2 │   │  │                 │
                │ctx:A →R1 │   │  │                 │
                │ctx:A →R2 │   │  │                 │
                └────┬─────┘   │  │                 │
                     │         │  │                 │
              artifacts        │  │                 │
            (image metadata)   │  │                 │
                     │         │  ▼                 │
                     │    ┌────┴──────────────┐     │
                     └───►│ update-manifest   │     │
                          │ argo-repo-1 (R1)  │     │
                          │ argo-repo-2 (R2)  │     │
                          └───────────────────┘     │
```

### Image metadata artifact format

Each push job produces a JSON file:

```json
{
  "name": "ghcr.io/epfl-enac/org/repo/backend",
  "digest": "sha256:abc123...",
  "ref_name": "dev",
  "registry": "ghcr.io",
  "push_id": "r1_c1"
}
```

The `update-manifest` job downloads all artifacts and filters by `registry` to get only the images relevant to its argo repository.

---

## Caching Strategy

### Docker Layer Cache (GHA)

```yaml
cache-from: type=gha,scope=build-${{ matrix.name }}
cache-to: type=gha,mode=max,scope=build-${{ matrix.name }}
```

- `mode=max` caches **all** layers, including intermediate build stages
- This means package installs (`npm ci`, `pip install`, `uv sync`) are cached as Docker layers
- The `build` job writes to cache; `push` jobs read from cache
- Scoped per image name to avoid cache collisions between different images

### Dockerfile-Level Cache Mounts (Optional)

For even faster package installs, users can add BuildKit cache mounts in their Dockerfiles:

```dockerfile
# npm
RUN --mount=type=cache,target=/root/.npm npm ci

# uv
RUN --mount=type=cache,target=/root/.cache/uv uv sync

# pip
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
```

These cache mounts are preserved within the GHA cache layers (`mode=max`).

---

## Registry Credentials

| Registry type | Secret used | Condition |
|---|---|---|
| `ghcr.io` | `GITHUB_TOKEN` (automatic) | `matrix.registry == 'ghcr.io'` |
| 1st non-ghcr | `registry_token` | `matrix.non_ghcr_index == 1` |
| 2nd non-ghcr | `registry_token_2` | `matrix.non_ghcr_index == 2` |

The `non_ghcr_index` is computed in `define-matrix` by `jq`, assigning a 1-based sequential index to non-ghcr registries in order.

---

## Backward Compatibility

All v2 inputs are preserved and work as before:

| v2 Input | Behavior in v3 |
|---|---|
| `registry` | Used when `registries` is empty |
| `registry_path` | Used when `registries` is empty |
| `registry_username` | Used when `registries` is empty |
| `argo_repository` | Used when `registries` is empty (becomes `argo_repositories` in the constructed registries array) |
| `registry_token` | Still used for the first non-ghcr registry |

When `registries` is empty, `define-matrix` constructs:

```json
[{
  "registry": "<inputs.registry>",
  "registry_path": "<inputs.registry_path>",
  "registry_username": "<inputs.registry_username>",
  "argo_repositories": <inputs.argo_repository>
}]
```

This means **no changes are needed** for existing callers.

---

## Usage Examples

### Single registry (backward compatible)

```yaml
jobs:
  deploy:
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3
    secrets:
      token: ${{ secrets.CD_TOKEN }}
    with:
      org: epfl-luts
      repo: app-test
```

### Multi-registry

```yaml
jobs:
  deploy:
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3
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

This builds `backend` and `frontend` **once**, pushes both to ghcr.io and registry.example.com (4 push jobs), and triggers manifest updates on both `enack8s-app-config` (with ghcr.io images) and `openshift-app-config` (with registry.example.com images).

---

## Limits

- Maximum 9 build contexts (unchanged from v2)
- Maximum 2 non-ghcr registries (limited by secrets: `registry_token` and `registry_token_2`)
- ghcr.io count is unlimited (uses `GITHUB_TOKEN`)
