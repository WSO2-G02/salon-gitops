# GitOps Workflow Guide: ECR to ArgoCD

## Overview

This guide explains how to complete the **Automation Loop**. You already have the "Pull" part (ArgoCD watching this repo). Now we need the "Push" part:

1.  **Code Change**: You push code to your App Repo (e.g., `appointment-service`).
2.  **CI Trigger**: GitHub Actions builds the Docker image.
3.  **Push to ECR**: The image is pushed to AWS ECR.
4.  **Update GitOps**: The CI pipeline updates the `deployment.yaml` in this `salon-gitops` repo with the new image tag.
5.  **ArgoCD Sync**: ArgoCD detects the change in this repo and deploys the new image.

## Bootstrapping the Cluster

Before the automation loop can work, the cluster must have ArgoCD installed and configured to watch this repository.

1.  **Ensure you have `kubectl` access** to your cluster (e.g., after running `deploy-k8s.sh`).
2.  **Run the Bootstrap Script** from the root of this repository:

    ```bash
    ./bootstrap.sh
    ```

    This script will:
    *   Install ArgoCD.
    *   Apply the Application manifests from `argocd/`.
    *   Output the initial `admin` password.

## Prerequisites

In your **Application Repository** (NOT this `salon-gitops` repo, but the one with source code), go to **Settings > Secrets and variables > Actions** and add:

1.  `AWS_ACCESS_KEY_ID`: Your AWS Access Key.
2.  `AWS_SECRET_ACCESS_KEY`: Your AWS Secret Key.
3.  `GITOPS_PAT`: A Personal Access Token (Classic) with `repo` scope.
    *   This is needed to push changes to the `salon-gitops` repo.
    *   Generate it here: [GitHub Developer Settings](https://github.com/settings/tokens)

## Workflow Template

Create a file named `.github/workflows/deploy.yaml` in your **Application Repository**.

```yaml
name: Build and Update GitOps

on:
  push:
    branches:
      - main  # or 'master'

env:
  AWS_REGION: eu-north-1
  ECR_REPOSITORY: salon-appointment-service  # CHANGE THIS for each service
  GITOPS_REPO: WSO2-G02/salon-gitops        # CHANGE THIS if different
  DEPLOYMENT_FILE: staging/appointment_service/deployment.yaml # CHANGE THIS path

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, and push image to Amazon ECR
        id: build-image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          # Build the docker image
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          
          # Push the image
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          
          echo "image=$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG" >> $GITHUB_OUTPUT

      - name: Update GitOps Repository
        env:
          GITOPS_PAT: ${{ secrets.GITOPS_PAT }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          # Configure Git
          git config --global user.email "github-actions@github.com"
          git config --global user.name "GitHub Actions"
          
          # Clone the specific file we need to update (sparse checkout for speed)
          mkdir gitops-repo
          cd gitops-repo
          git init
          git remote add origin https://oauth2:${GITOPS_PAT}@github.com/${GITOPS_REPO}.git
          git fetch origin main
          git checkout origin/main -- $DEPLOYMENT_FILE
          
          # Update the Docker image tag in the deployment file
          # This command preserves indentation and updates the image line
          # NOTE: If you have multiple containers, ensure this regex is specific enough
          sed -i "s|image: .*$|image: ${{ steps.build-image.outputs.image }}|g" $DEPLOYMENT_FILE
          
          # Verify the change
          cat $DEPLOYMENT_FILE | grep "image:"
          
          # Commit and Push
          git add $DEPLOYMENT_FILE
          git commit -m "Update ${ECR_REPOSITORY} image to ${IMAGE_TAG}"
          git push origin HEAD:main
```

## How to Customize

1.  **ECR_REPOSITORY**: Set this to the name of your ECR repo.
    *   Example: `appointment_service` (matching your current deployment).
2.  **DEPLOYMENT_FILE**: Set this to the path in *this* `salon-gitops` repo.
    *   Example: `staging/appointment_service/deployment.yaml`.

## Why this approach?

*   **Audit Trail**: Every deployment is a Git commit. You can see exactly when and what changed.
*   **Rollbacks**: To rollback, you just revert the commit in this `salon-gitops` repo. ArgoCD handles the rest.
*   **Security**: The cluster pulls images; the CI pipeline pushes triggers. They are decoupled.
