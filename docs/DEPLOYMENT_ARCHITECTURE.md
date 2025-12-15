# Aurora Glam - Deployment Architecture Guide

> **For Team Members**: This document explains how our CI/CD pipeline, staging, and production environments work together.

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [How Deployment Works](#how-deployment-works)
4. [Deploying to Production](#deploying-to-production)
5. [ArgoCD Configuration](#argocd-configuration)
6. [Staging vs Production](#staging-vs-production)
7. [Security: Restricting Staging Access](#security-restricting-staging-access)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### The Big Picture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         DEPLOYMENT FLOW OVERVIEW                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

  FRONTEND REPO                              BACKEND REPO
  (salon-booking-frontend-dev)               (salon-booking-backend-dev)
           │                                          │
           │ push to main                             │ push to main
           ▼                                          ▼
  ┌─────────────────┐                       ┌─────────────────┐
  │  CI/CD Pipeline │                       │  CI/CD Pipeline │
  │  (ci-cd.yml)    │                       │(ci-cd-pipeline) │
  └────────┬────────┘                       └────────┬────────┘
           │                                          │
           │ Updates staging/frontend/               │ Updates staging/{service}/
           ▼                                          ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │                     GITOPS REPO (salon-gitops)                       │
  │  ┌─────────────────────────┐    ┌─────────────────────────┐         │
  │  │   staging/              │    │   production/           │         │
  │  │   ├── frontend/         │    │   ├── frontend/         │         │
  │  │   ├── user_service/     │    │   ├── user_service/     │         │
  │  │   ├── appointment_svc/  │    │   ├── appointment_svc/  │         │
  │  │   └── ...               │    │   └── ...               │         │
  │  │                         │    │                         │         │
  │  │  ◄── CI/CD AUTO-UPDATES │    │  ◄── MANUAL PROMOTION   │         │
  │  └─────────────────────────┘    └─────────────────────────┘         │
  │                                                                      │
  │  .github/workflows/deploy-production.yml  ← UNIFIED DEPLOY WORKFLOW │
  └─────────────────────────────────────────────────────────────────────┘
                              │
                    ArgoCD watches both folders
                              │
           ┌──────────────────┴──────────────────┐
           ▼                                      ▼
  ┌─────────────────┐                    ┌─────────────────┐
  │  STAGING        │                    │  PRODUCTION     │
  │  Namespace      │                    │  Namespace      │
  │                 │                    │                 │
  │  staging.       │                    │  aurora-glam.   │
  │  aurora-glam.com│                    │  com            │
  └─────────────────┘                    └─────────────────┘
```

---

## How Deployment Works

### Automatic Flow (Push to Staging)

```
Developer pushes code to main branch
              │
              ▼
┌─────────────────────────────────────────┐
│         GitHub Actions CI/CD            │
│  ┌─────┐  ┌─────┐  ┌─────┐  ┌───────┐  │
│  │Build│─►│Test │─►│Scan │─►│Push to│  │
│  │     │  │     │  │     │  │  ECR  │  │
│  └─────┘  └─────┘  └─────┘  └───────┘  │
│                                  │      │
│                                  ▼      │
│           ┌─────────────────────────┐   │
│           │ Update GitOps Repo      │   │
│           │ staging/{service}/      │   │
│           │ deployment.yaml         │   │
│           └─────────────────────────┘   │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│           ArgoCD Auto-Sync              │
│                                         │
│  Detects change in staging/ folder      │
│  Deploys to staging namespace           │
└─────────────────────────────────────────┘
              │
              ▼
        staging.aurora-glam.com
        (Ready for testing!)
```

### Manual Flow (Deploy to Production)

```
Team member triggers "Deploy to Production" workflow
              │
              ▼
┌─────────────────────────────────────────┐
│     Deploy to Production Workflow       │
│     (salon-gitops/.github/workflows/)   │
│                                         │
│  1. Select services: "all" or specific  │
│  2. Choose: promote staging OR tag      │
│  3. Type "DEPLOY" to confirm            │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│           Workflow Actions              │
│                                         │
│  1. Validates image exists in ECR       │
│  2. Gets tag from staging (or input)    │
│  3. Updates production/{service}/       │
│     deployment.yaml                     │
│  4. Commits to salon-gitops             │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│           ArgoCD Auto-Sync              │
│                                         │
│  Detects change in production/ folder   │
│  Deploys to production namespace        │
└─────────────────────────────────────────┘
              │
              ▼
          aurora-glam.com
          (Live for users!)
```

---

## Deploying to Production

### Step-by-Step Guide

#### 1. Go to the Deploy Workflow

Navigate to: **https://github.com/WSO2-G02/salon-gitops/actions/workflows/deploy-production.yml**

Or: GitHub → salon-gitops repo → Actions → "Deploy to Production"

#### 2. Click "Run workflow"

#### 3. Fill in the Options

| Field | Options | Description |
|-------|---------|-------------|
| **Services** | `all` | Deploy ALL services (frontend + 6 backend) |
| | `frontend` | Deploy only frontend |
| | `user_service,frontend` | Deploy specific services (comma-separated) |
| **Image source** | `promote-staging` | Use the same image currently in staging |
| | `specific-tag` | Use a specific image tag |
| **Specific tag** | (optional) | Only if you chose "specific-tag" above |
| **Confirm** | `DEPLOY` | Type exactly "DEPLOY" to confirm |

#### 4. Click "Run workflow" (green button)

#### 5. Monitor the Deployment

- Watch the workflow progress
- Check ArgoCD: https://argocd.aurora-glam.com
- Verify site: https://aurora-glam.com

### Example Scenarios

**Deploy everything that's in staging to production:**
```
Services: all
Image source: promote-staging
Confirm: DEPLOY
```

**Deploy only the frontend:**
```
Services: frontend
Image source: promote-staging
Confirm: DEPLOY
```

**Deploy frontend and user_service:**
```
Services: frontend,user_service
Image source: promote-staging
Confirm: DEPLOY
```

**Deploy a specific version:**
```
Services: frontend
Image source: specific-tag
Specific tag: abc12345-20251215120000
Confirm: DEPLOY
```

---

## Why This Architecture?

### Industry Best Practice: GitOps with Staged Promotion

```
┌─────────────────────────────────────────────────────────────────┐
│                    WHY STAGING → PRODUCTION?                     │
└─────────────────────────────────────────────────────────────────┘

                    TRADITIONAL (Risky)
                    ─────────────────────
                    Code → Build → Deploy directly to production
                    
                    Problem: Bugs go straight to users!

                    
                    OUR APPROACH (Safe)
                    ─────────────────────
                    Code → Build → Staging → Test → Production
                    
                    Benefits:
                    ✓ Catch bugs before users see them
                    ✓ QA team can test new features
                    ✓ Rollback is easy (deploy previous tag)
                    ✓ Production is always stable
```

### Why One Unified Deploy Workflow?

| Approach | Workflows | Pros | Cons |
|----------|-----------|------|------|
| Per-service workflows | 7 workflows | Fine control | Hard to manage, must deploy each separately |
| **Unified workflow** ⭐ | 1 workflow | Easy to use, deploy all or specific | Slightly less flexible |
| Git branch promotion | 0 workflows | Pure GitOps | Requires git knowledge |

**We chose unified** because:
- ✅ One place to deploy everything
- ✅ Can still deploy individual services
- ✅ Easy for any team member to use
- ✅ Clear audit trail in GitHub Actions

We have **4 main repositories**:

| Repository | Purpose |
|------------|---------|
| `salon-booking-frontend-dev` | Frontend source code (Next.js) |
| `salon-booking-backend-dev` | Backend microservices source code (FastAPI) |
| `salon-gitops` | Kubernetes manifests (what ArgoCD watches) |
| `salon-k8s-infra` | Terraform infrastructure code |

### GitOps Repository Structure (`salon-gitops`)

```
salon-gitops/
├── argocd/                     # ArgoCD Application definitions
│   ├── frontend.yaml           # Staging frontend app
│   ├── prod-frontend.yaml      # Production frontend app
│   ├── user_service.yaml       # Staging user service
│   ├── prod-user_service.yaml  # Production user service
│   └── ...
├── staging/                    # Staging environment manifests
│   ├── frontend/
│   │   └── deployment.yaml     # ← CI/CD updates this file
│   ├── user_service/
│   ├── appointment_service/
│   └── ...
├── production/                 # Production environment manifests
│   ├── frontend/
│   │   └── deployment.yaml     # ← Manual promotion updates this
│   ├── user_service/
│   └── ...
├── istio/
│   └── gateway.yaml            # Istio Gateway configuration
└── docs/
    └── DEPLOYMENT_ARCHITECTURE.md  # This file
```

---

## How Deployment Works

### The Flow (Simplified)

```
Developer pushes code
        │
        ▼
GitHub Actions runs CI/CD
        │
        ▼
Docker image built & pushed to ECR
        │
        ▼
CI/CD updates staging/frontend/deployment.yaml in salon-gitops
        │
        ▼
ArgoCD detects change in salon-gitops repo
        │
        ▼
ArgoCD deploys new image to STAGING namespace
        │
        ▼
Team tests at staging.aurora-glam.com
        │
        ▼
If approved → Manual "Deploy to Production" workflow
        │
        ▼
Workflow updates production/frontend/deployment.yaml
        │
        ▼
ArgoCD deploys to PRODUCTION namespace
        │
        ▼
Live at aurora-glam.com
```

---

## ArgoCD Configuration

### What is ArgoCD?

ArgoCD is a **GitOps continuous delivery tool**. It:
1. Watches the `salon-gitops` repository
2. Compares what's in the repo vs what's in the cluster
3. Automatically syncs any differences

### Current ArgoCD Applications

| Application Name | Watches Path | Deploys To |
|-----------------|--------------|------------|
| `frontend` | `staging/frontend/` | staging namespace |
| `prod-frontend` | `production/frontend/` | production namespace |
| `user-service` | `staging/user_service/` | staging namespace |
| `prod-user-service` | `production/user_service/` | production namespace |
| ... | ... | ... |

### ArgoCD Application Example

**Staging Frontend** (`argocd/frontend.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: frontend
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/WSO2-G02/salon-gitops
    path: staging/frontend          # ← Watches this folder
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: staging              # ← Deploys to staging
  syncPolicy:
    automated:                      # ← Auto-sync enabled
      prune: true
      selfHeal: true
```

**Production Frontend** (`argocd/prod-frontend.yaml`):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-frontend
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/WSO2-G02/salon-gitops
    path: production/frontend       # ← Watches this folder
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: production           # ← Deploys to production
  syncPolicy:
    automated:                      # ← Auto-sync enabled
      prune: true
      selfHeal: true
```

### Key Point: ArgoCD Does NOT Decide What to Deploy

ArgoCD only syncs what's in the GitOps repo. The **CI/CD pipeline decides** which folder to update:
- CI/CD → Updates `staging/` folder → ArgoCD syncs to staging namespace
- Manual workflow → Updates `production/` folder → ArgoCD syncs to production namespace

---

## Staging vs Production

### Comparison Table

| Aspect | Staging | Production |
|--------|---------|------------|
| **URL** | staging.aurora-glam.com | aurora-glam.com |
| **K8s Namespace** | `staging` | `production` |
| **Deployment Trigger** | Automatic (on git push) | Manual (GitHub Actions workflow) |
| **Purpose** | Testing, QA | Live users |
| **Who can access** | Team only (recommended) | Everyone |
| **Break OK?** | Yes, for testing | No! |

### Why Two Environments?

```
┌─────────────────────────────────────────────────────────────────┐
│  STAGING (staging.aurora-glam.com)                              │
│  ─────────────────────────────────────────────────────────────  │
│  • New features are deployed here first                         │
│  • QA team tests new features                                   │
│  • Bugs can be found before affecting real users                │
│  • Safe to break - only internal team uses it                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ After testing, manually promote
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  PRODUCTION (aurora-glam.com)                                   │
│  ─────────────────────────────────────────────────────────────  │
│  • Real customers use this                                      │
│  • Only tested, approved code goes here                         │
│  • Must be stable and reliable                                  │
│  • Requires manual approval to deploy                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step: Code to Production

### Step 1: Developer Pushes Code

```bash
# Developer makes changes
git add .
git commit -m "feat: add new booking feature"
git push origin main
```

### Step 2: CI/CD Pipeline Runs Automatically

GitHub Actions (`.github/workflows/ci-cd.yml`) runs:

1. **Build**: Creates Docker image
2. **Test**: Runs Jest unit tests
3. **Security Scan**: Trivy scans for vulnerabilities
4. **Push to ECR**: Uploads image with tag like `abc12345-20251215120000`
5. **Update GitOps**: Changes `staging/frontend/deployment.yaml`:

```yaml
# Before
image: 024955634588.dkr.ecr.us-east-1.amazonaws.com/frontend:old-tag

# After (CI/CD updates this)
image: 024955634588.dkr.ecr.us-east-1.amazonaws.com/frontend:abc12345-20251215120000
```

### Step 3: ArgoCD Syncs to Staging

- ArgoCD detects the change in `staging/frontend/deployment.yaml`
- Within ~3 minutes, ArgoCD deploys the new image to `staging` namespace
- New version is now live at **staging.aurora-glam.com**

### Step 4: Team Tests on Staging

- QA team visits staging.aurora-glam.com
- Tests the new feature
- Reports any bugs
- Approves for production (or requests fixes)

### Step 5: Manual Deploy to Production

Once approved, a team member triggers the production deployment:

1. Go to **GitHub → Actions → "Deploy to Production"**
2. Click **"Run workflow"**
3. Choose: Promote from staging OR enter specific image tag
4. Type **"DEPLOY"** to confirm
5. Click **"Run workflow"**

### Step 6: Production Workflow Updates GitOps

The workflow updates `production/frontend/deployment.yaml`:

```yaml
# Before
image: 024955634588.dkr.ecr.us-east-1.amazonaws.com/frontend:previous-tag

# After
image: 024955634588.dkr.ecr.us-east-1.amazonaws.com/frontend:abc12345-20251215120000
```

### Step 7: ArgoCD Syncs to Production

- ArgoCD detects the change in `production/frontend/deployment.yaml`
- ArgoCD deploys the new image to `production` namespace
- New version is now live at **aurora-glam.com**

---

## How to Deploy to Production

### Prerequisites
- GitHub access to `salon-booking-frontend-dev` repository
- Feature has been tested on staging

### Steps

1. **Go to GitHub Actions**
   ```
   https://github.com/WSO2-G02/salon-booking-frontend-dev/actions
   ```

2. **Select "Deploy to Production" workflow**
   
3. **Click "Run workflow"**

4. **Fill in the form:**
   - **Image tag**: Leave empty to promote current staging version
     - OR enter specific tag like `abc12345-20251215120000`
   - **Confirm deployment**: Type `DEPLOY` (must be exact)

5. **Click green "Run workflow" button**

6. **Monitor the workflow:**
   - Validates the image exists in ECR
   - Updates production deployment manifest
   - Commits to salon-gitops repository

7. **Verify deployment:**
   - Check ArgoCD: https://argocd.aurora-glam.com
   - Check production site: https://aurora-glam.com

### Rollback

To rollback, run the same workflow with the **previous image tag**.

---

## Security: Restricting Staging Access

### Current State
Currently, staging.aurora-glam.com is publicly accessible (same as production).

### How to Restrict Access (Options)

#### Option 1: IP Whitelisting (Recommended)
Add to Istio VirtualService:
```yaml
# Only allow company office IP
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: staging-ip-whitelist
  namespace: staging
spec:
  rules:
  - from:
    - source:
        ipBlocks: ["YOUR.OFFICE.IP.ADDRESS/32"]
```

#### Option 2: Basic Authentication
Add Nginx ingress with basic auth or use Istio's JWT authentication.

#### Option 3: VPN Only
- Put staging behind a VPN
- Team must connect to VPN to access staging

#### Option 4: OAuth/SSO
- Integrate with company SSO (Google Workspace, Okta, etc.)
- Only authenticated company employees can access

### Recommendation
For simplicity, **IP whitelisting** is the easiest to implement. Talk to your team lead about which approach fits best.

---

## Infrastructure Components

### How Each Component Fits

| Component | What It Does | Managed By |
|-----------|--------------|------------|
| **Terraform** | Creates AWS resources (VPC, EC2, ECR, IAM) | `salon-k8s-infra` repo |
| **Kubespray** | Installs Kubernetes on EC2 instances | One-time setup |
| **Istio** | Service mesh, handles routing between services | GitOps + manual |
| **Istio Gateway** | Entry point for all HTTP traffic | `istio/gateway.yaml` |
| **VirtualService** | Routes traffic based on domain to correct namespace | `staging/salon-routes.yaml`, `production/salon-routes.yaml` |
| **ArgoCD** | Watches GitOps repo, syncs to cluster | Installed in cluster |
| **ECR** | Stores Docker images | Terraform created |
| **Route53** | DNS records pointing to ALB | AWS Console |
| **ALB** | Load balancer in front of cluster | Terraform/AWS |

### Traffic Flow

```
User visits aurora-glam.com
          │
          ▼
    Route53 DNS
    (aurora-glam.com → ALB IP)
          │
          ▼
    AWS ALB (Load Balancer)
          │
          ▼
    Istio Ingress Gateway
    (Accepts: aurora-glam.com, staging.aurora-glam.com, argocd.aurora-glam.com)
          │
          ├── Host: aurora-glam.com ──────────► VirtualService (production)
          │                                              │
          │                                              ▼
          │                                     Production Namespace
          │                                     (frontend, APIs)
          │
          ├── Host: staging.aurora-glam.com ──► VirtualService (staging)
          │                                              │
          │                                              ▼
          │                                     Staging Namespace
          │                                     (frontend, APIs)
          │
          └── Host: argocd.aurora-glam.com ───► ArgoCD Namespace
                                                         │
                                                         ▼
                                                ArgoCD Web UI
```

---

## Troubleshooting

### Common Issues

#### "My changes aren't showing up on staging"

1. Check if CI/CD pipeline passed:
   ```
   https://github.com/WSO2-G02/salon-booking-frontend-dev/actions
   ```

2. Check if GitOps was updated:
   ```bash
   cd salon-gitops
   git pull
   git log -1 staging/frontend/deployment.yaml
   ```

3. Check ArgoCD sync status:
   ```
   https://argocd.aurora-glam.com
   ```

4. Check pod status:
   ```bash
   kubectl get pods -n staging
   kubectl describe pod <pod-name> -n staging
   ```

#### "ArgoCD shows OutOfSync"

```bash
# Force sync
kubectl -n argocd patch application frontend --type merge -p '{"operation":{"sync":{"prune":true}}}'

# Or use ArgoCD UI: Click "Sync" button
```

#### "Production deployment failed"

1. Check the GitHub Actions log
2. Verify the image exists in ECR:
   ```bash
   aws ecr describe-images --repository-name frontend --image-ids imageTag=<tag>
   ```

3. Check ArgoCD for sync errors

#### "Can't access staging/production website"

1. Check DNS:
   ```bash
   nslookup aurora-glam.com
   nslookup staging.aurora-glam.com
   ```

2. Check Istio Gateway:
   ```bash
   kubectl get gateway -n istio-system
   kubectl describe gateway salon-gateway -n istio-system
   ```

3. Check VirtualService:
   ```bash
   kubectl get virtualservice -A
   ```

---

## Quick Reference

### URLs

| Service | URL |
|---------|-----|
| Production | https://aurora-glam.com |
| Staging | http://staging.aurora-glam.com |
| ArgoCD | http://argocd.aurora-glam.com |
| Grafana | http://grafana.aurora-glam.com |

### Useful Commands

```bash
# Check all pods
kubectl get pods -n staging
kubectl get pods -n production

# Check ArgoCD apps
kubectl get applications -n argocd

# View pod logs
kubectl logs -f deployment/frontend -n staging

# Check which image is deployed
kubectl get deployment frontend -n staging -o jsonpath='{.spec.template.spec.containers[0].image}'

# Force ArgoCD refresh
argocd app refresh frontend
```

### Workflow Triggers

| Action | What Happens |
|--------|--------------|
| Push to `main` branch | CI/CD runs → Deploys to STAGING |
| Manual "Deploy to Production" | Updates production manifest → Deploys to PRODUCTION |

---

## Questions?

Contact the DevOps team or check:
- ArgoCD UI: http://argocd.aurora-glam.com
- GitHub Actions: https://github.com/WSO2-G02/salon-booking-frontend-dev/actions
- This documentation: `salon-gitops/docs/DEPLOYMENT_ARCHITECTURE.md`
