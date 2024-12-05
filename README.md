# EPFL ENAC-IT Continuous Deployment

This action implements ENAC-IT's Continuous Deployment for your app on a given environment (dev, test, stage or prod).

To use it in your repository, create a workflow file named `.github/workflows/deploy.yml` with the following content:

```yml
# https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action#readme
name: deploy

'on':
  push:
    branches:
      - develop
      - dev
      - main
      - test
      - stage
    tags: ['v*.*.*']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: EPFL-ENAC/epfl-enac-build-push-deploy-action@v1.0.0
        with:
          ENAC_IT4R_CD_ORG: "org name given by ENAC-IT: e.g. : epfl-enac or epfl-lasur"
          ENAC_IT4R_CD_REPO: "app name given by ENAC-IT: e.g. : my-app"
          ENAC_IT4R_CD_TOKEN: ${{ secrets.ENAC_IT4R_CD_TOKEN }}
          ENAC_IT4R_CD_BUILD_CONTEXT: ["./frontend", "./backend"]
```
## Inputs
  - `ENAC_IT4R_CD_ORG`:
    The organization name given by ENAC-IT - (mandatory)
  - `ENAC_IT4R_CD_REPO`:
    The repository name given by ENAC-IT - (mandatory)
  - `ENAC_IT4R_CD_TOKEN`:
    The secret associated with the deployment_id - (mandatory)
  - `ENAC_IT4R_CD_BUILD_CONTEXT`:
    - The context of the build - (optional)
    - Currently we support max 9 contexts/ or build image per repository
    - The context is the path to the directory containing the Dockerfile. For example: 
      ["./backend", "./admin", "./frontend"], default is ["."]
    - This will result in the following matrix automatically:
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
   
## Create one secrets in your repository

Under your repository settings in /settings/secrets/actions

- Add `ENAC_IT4R_CD_TOKEN`

This value is provided by ENAC-IT while discussing the hosting agreement.

## Example usage with custom timeout and interval

```
uses: EPFL-ENAC/epfl-enac-build-push-deploy-action@v1.0.0
with:
  ENAC_IT4R_CD_ORG: "epfl-enac"
  ENAC_IT4R_CD_REPO: "my-app"
  ENAC_IT4R_CD_TOKEN: ${{ secrets.ENAC_IT4R_CD_TOKEN }}
  ENAC_IT4R_CD_BUILD_CONTEXT: ["./frontend", "./backend"]
```
