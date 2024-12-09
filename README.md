# EPFL ENAC-IT Continuous Deployment

This action implements ENAC-IT's Continuous Deployment for your app on a given environment (dev, test, stage or prod).

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
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v2.0.0
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
    uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v2.0.0
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

- Add `CD_TOKEN`

This value is provided by ENAC-IT while discussing the hosting agreement.
