# EPFL ENAC-IT Continuous Deployment

This action implements ENAC-IT's Continuous Deployment for your app on a given environment (dev, test, stage or prod). It can be used in EPFL-ENAC repositories, as well as any other repositories owned by other organizations.

- if you push on the *dev* branch, it will update the images on the overlay dev in your enack8s-app-config
- if you push on the *test* branch, same but overlay *test*
- if you push on the *stage* branch, same but overlay *stage*
- if you push a tag (create a release: v1.0.0 for instance, it will update the overlay prod

To use it in your repository, create a workflow file named `.github/workflows/deploy.yml` with the following content:


## for repository with one image

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
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v2.1.0
    secrets:
      token: ${{ secrets.CD_TOKEN }}
    with:
      org: epfl-luts # your org
      repo: app-test # your app name, usual convention is name of your repository
```
## for repository with multi images

You need to pass an additional inputs: 'build_context' which is a list of directories with a Dockerfile in it.
The images pushed to the registry will follow org/repo convention: 
  - ghcr.io/epfl-enac/ethz-alice/arema/backend:{sha256}
  - ghcr.io/epfl-enac/ethz-alice/arema/admin:{sha256}
  - ghcr.io/epfl-enac/ethz-alice/arema/frontend:{sha256}


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
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v2.1.0
    secrets:
      token: ${{ secrets.CD_TOKEN }}
    with:
      org: ethz-alice # your org
      repo: arema # your app name, usual convention is name of your repository
      build_context: '["./backend", "./admin", "./frontend"]'
```
## Inputs
  - `org`:
    The organization name given by ENAC-IT - (mandatory)
  - `repo`:
    The repository name given by ENAC-IT - (mandatory)
  - `token`:
    The secret associated with the deployment_id - (mandatory)
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
              "image": "ghcr.io/epfl-enac/${{ENAC_IT4R_CD_ORG}}/${{ENAC_IT4R_CD_REPO}}/backend",
              "id": 1
            },
            {
              "Dockerfile": "./admin/Dockerfile",
              "context": "./admin",
              "image": "ghcr.io/epfl-enac/${{ENAC_IT4R_CD_ORG}}/${{ENAC_IT4R_CD_REPO}}/admin",
              "id": 2
            },
            {
              "Dockerfile": "./frontend/Dockerfile",
              "context": "./frontend",
              "image": "ghcr.io/epfl-enac/${{ENAC_IT4R_CD_ORG}}/${{ENAC_IT4R_CD_REPO}}/frontend",
              "id": 3
            }
        ]
    ```
    - in the default case (no context provided: will be ["."]), the matrix will be:
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
  - `create_pull_request`:
    - Create a pull request in the enack8s-app-config repository - (optional)
    - Default is false, if you create a tag, it will automatically push to main without creating a PR, and deploy within the prod overlay in 5mn or so. 
## Create one secrets in your repository

Under your repository settings in /settings/secrets/actions



### How it works
GitHub Action reusable workflow to automate the build and continuous deployment (CD) process for your application. The workflow will trigger on every push to the `main` or `dev` branch or whatever you defined and whenever a tag is created. Upon execution, it will perform the following:

1. Build the package as part of the CI process.
2. Trigger a webhook to initiate the CD process.

For CD, the webhook will call a GitHub Action in the `enack8s-app-config` repository. This action will update the manifests in the `enack8s-app-config` repository. There's no need to define a separate GitHub Action in the `enack8s-app-config` repository itself; the webhook-driven approach ensures all operations originate from your repository.

- Using the update_manifest Hook
The update_manifest GitHub Actions workflow is designed to update Kubernetes manifests in a repository based on specific events. This guide will explain how to use the update_manifest hook and the different options that can be passed in the client_payload.

- Triggering the Hook
The update_manifest hook is triggered by a repository_dispatch event. To trigger this event, you can use the GitHub API to send a POST request to the repository's dispatch endpoint.

- Example API Request
Here is an example of how to trigger the update_manifest hook using curl:

```
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: Bearer ${{ secrets.CD_TOKEN }}" \
          ${{ secrets.CD_URI }} \
  -d '{
    "event_type": "update-manifest",
    "client_payload": {
      "repo_name": "${{ secrets.CD_REPO }}",
      "repo_org": "${{ secrets.CD_ORG }}",
      "branch": "prod",
      "create_pull_request": true,
      "images": [
        {
          "name": "ghcr.io/epfl-enac/alice-ethz-***/***-api",
          "digest": "sha256:608087b53ee814372a55e45c73317410355d6ec5ec1273e8be918143264261f1",
          "ref_name": "dev"
        },
        {
          "name": "ghcr.io/epfl-enac/alice-ethz-***/***-admin",
          "digest": "sha256:0bc241c70114e076d53dc371f298873da7dec25ca51101591c81fee98aa68493",
          "ref_name": "dev",
        }]
    }
  }'
```

- client_payload Options

The client_payload object contains several options that control how the manifest is updated:

  - repo_org: The organization or user that owns the repository.
  - repo_name: The name of the repository.
  - branch: The branch where the manifest is located. Typically, this will be prod for production deployments.
  - create_pull_request: A boolean value (true or false) that determines whether a pull request should be created for the changes.
  - images: An array of object that need to be updated in the manifest. following this schema {
          "name": "ghcr.io/epfl-enac/alice-ethz-***/***-api",
          "digest": "sha256:608087b53ee814372a55e45c73317410355d6ec5ec1273e8be918143264261f1",
          "ref_name": "v1.0.0" # The new tag or reference name to be used in the manifest (only for prod branch).
        }

- Workflow Behavior
  1) Checkout Repository: The workflow checks out the repository to the latest commit.
  2) Install Dependencies: Installs necessary dependencies such as git, wget, curl, jq, and yq.
  3) Modify Manifest:
    - Navigates to the specified repository and branch.
    - Updates the digest for the specified images in the kustomization.yaml file.
    - If the branch is prod, it also updates the newTag field with the ref_name.
  4) Commit and Push Changes:
    - Commits the changes with a message indicating the update.
    - If create_pull_request is true, it creates a new branch and pushes the changes.
    - If create_pull_request is false, it pushes the changes directly to the main branch.

 - Example Usage
To update the manifest for the prod branch with a new image digest and tag, and create a pull request for the changes:
```
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://api.github.com/repos/YOUR_ORG/YOUR_REPO/dispatches \
  -d '{
    "event_type": "update-manifest",
    "client_payload": {
      "repo_org": "YOUR_ORG",
      "repo_name": "YOUR_REPO",
      "branch": "prod",
      "create_pull_request": true,
      "image": [
        {
          "name": "ghcr.io/epfl-enac/alice-ethz-***/***-api",
          "digest": "sha256:608087b53ee814372a55e45c73317410355d6ec5ec1273e8be918143264261f1",
          "ref_name": "v1.0.0"
        },
        {
          "name": "ghcr.io/epfl-enac/alice-ethz-***/***-admin",
          "digest": "sha256:0bc241c70114e076d53dc371f298873da7dec25ca51101591c81fee98aa68493",
          "ref_name": "dev",
        }]
    }
  }'
```

To update the manifest for a non-production branch without creating a pull request:

```
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://api.github.com/repos/YOUR_ORG/YOUR_REPO/dispatches \
  -d '{
    "event_type": "update-manifest",
    "client_payload": {
      "repo_org": "YOUR_ORG",
      "repo_name": "YOUR_REPO",
      "branch": "dev",
      ....
    }
  }'
```

- Note: Replace YOUR_GITHUB_TOKEN, YOUR_ORG, YOUR_REPO, and YOUR_DIGEST with the appropriate values for your repository.
- Note: The update-manifest hook is designed to work with repositories that use kustomize to manage Kubernetes manifests. If your repository uses a different method for managing manifests, you may need to modify the workflow to suit your needs.
- If you have any questions or need assistance with the update-manifest hook, please contact the EPFL-ENAC DevOps team.
- If your branches or repository does not follow the standard pattern, you may need to modify the workflow to suit your needs.
- How to update the manifest for a non-production branch without creating a pull request:
  ```sh
  yq eval '(.images[] | select(.name == "ghcr.io/epfl-enac/resslab-astra-82001-frontend").newTag) = "1.2.666"' -i epfl-resslab/resslab-astra-82001-frontend/overlays/prod/kustomization.yaml
  ```



- Add `CD_TOKEN`

This value is provided by ENAC-IT while discussing the hosting agreement.
