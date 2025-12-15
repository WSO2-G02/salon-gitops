# 🚀 Staging → Production Deployment Workflow

## Industry Standard: GitOps with Environment Promotion

This document explains the **industry-standard approach** for deploying applications through staging to production environments.

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    INDUSTRY STANDARD DEPLOYMENT PIPELINE                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐                  │
│   │   DEVELOP    │ ───► │   STAGING    │ ───► │  PRODUCTION  │                  │
│   │              │      │              │      │              │                  │
│   │  Developer   │      │  QA Testing  │      │  Live Users  │                  │
│   │  Testing     │      │  UAT Testing │      │  Real Traffic│                  │
│   │  Feature Dev │      │  Integration │      │  Monitored   │                  │
│   └──────────────┘      └──────────────┘      └──────────────┘                  │
│         │                      │                     │                          │
│         │ Auto Deploy          │ Manual Approval     │                          │
│         │ on PR Merge          │ Required            │                          │
│         ▼                      ▼                     ▼                          │
│   ┌─────────────────────────────────────────────────────────────────┐           │
│   │                      GitOps Repository                          │           │
│   │   staging/              production/                             │           │
│   │   ├── frontend/         ├── frontend/                           │           │
│   │   ├── user-service/     ├── user-service/                       │           │
│   │   └── ...               └── ...                                 │           │
│   └─────────────────────────────────────────────────────────────────┘           │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🌐 Domain Configuration

| Environment | Domain | Purpose |
|-------------|--------|---------|
| **Staging** | `staging.aurora-glam.com` | Testing & QA |
| **Production** | `aurora-glam.com` | Live website |
| **ArgoCD** | `argocd.aurora-glam.com` | GitOps dashboard |

---

## 🔄 Deployment Flow

### Step 1: Developer Pushes Code
```bash
# Developer works on feature branch
git checkout -b feature/new-booking-ui
# ... make changes ...
git commit -m "feat: add new booking UI"
git push origin feature/new-booking-ui
# Create PR → Merge to main
```

### Step 2: CI/CD Automatically Deploys to STAGING
```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions CI/CD Pipeline (Automatic)                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Run Tests (Unit, Integration)                                │
│  2. Security Scans (npm audit, Trivy, Gitleaks)                  │
│  3. Build Docker Image                                           │
│  4. Push to ECR (024955634588.dkr.ecr.us-east-1.amazonaws.com)   │
│  5. Update GitOps: staging/frontend/deployment.yaml              │
│  6. ArgoCD auto-syncs to staging namespace                       │
│                                                                  │
│  Result: https://staging.aurora-glam.com shows new version       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Step 3: QA Tests in Staging
- Test all features at `https://staging.aurora-glam.com`
- Verify API integrations
- Check mobile responsiveness
- Run automated E2E tests (optional)

### Step 4: Manual Promotion to Production
```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions - Manual Production Deployment                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Go to: GitHub → Actions → "Deploy to Production" → Run          │
│                                                                  │
│  Or use GitHub CLI:                                              │
│  gh workflow run deploy-production.yml                           │
│                                                                  │
│  This triggers:                                                  │
│  1. Copy staging image tag to production/frontend/deployment.yaml│
│  2. ArgoCD syncs production namespace                            │
│  3. https://aurora-glam.com shows new version                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🏗️ Infrastructure Components

### 1. AWS / Terraform
| Component | Purpose | File |
|-----------|---------|------|
| ECR | Docker image registry | `terraform/ecr.tf` |
| Route53 | DNS management | Manual or `terraform/route53.tf` |
| ACM | SSL certificates | Manual or `terraform/acm.tf` |
| IAM | Access permissions | `terraform/iam.tf` |

### 2. Kubernetes / Kubespray
| Component | Purpose |
|-----------|---------|
| Namespaces | `staging`, `production`, `istio-system`, `argocd` |
| Deployments | App containers |
| Services | Internal networking |
| ConfigMaps/Secrets | Configuration |

### 3. Istio Service Mesh
| Component | Purpose | File |
|-----------|---------|------|
| Gateway | External traffic entry point | `istio/gateway.yaml` |
| VirtualService (staging) | Routes `staging.aurora-glam.com` | `staging/salon-routes.yaml` |
| VirtualService (prod) | Routes `aurora-glam.com` | `production/salon-routes.yaml` |

### 4. ArgoCD GitOps
| Application | Watches | Deploys To |
|-------------|---------|------------|
| frontend | `staging/frontend/` | staging namespace |
| prod-frontend | `production/frontend/` | production namespace |

---

## 📁 Repository Structure

```
salon-gitops/
├── argocd/                          # ArgoCD Application definitions
│   ├── frontend.yaml                # Staging frontend app
│   ├── prod-frontend.yaml           # Production frontend app
│   └── ...
│
├── staging/                         # STAGING environment
│   ├── frontend/
│   │   ├── deployment.yaml          # Updated by CI/CD automatically
│   │   └── service.yaml
│   ├── user-service/
│   ├── salon-routes.yaml            # Routes staging.aurora-glam.com
│   └── ...
│
├── production/                      # PRODUCTION environment
│   ├── frontend/
│   │   ├── deployment.yaml          # Updated by manual promotion
│   │   └── service.yaml
│   ├── user-service/
│   ├── salon-routes.yaml            # Routes aurora-glam.com
│   └── ...
│
├── istio/
│   └── gateway.yaml                 # Handles both domains
│
└── docs/
    └── STAGING_PRODUCTION_WORKFLOW.md
```

---

## 🔧 Setup Instructions

### Step 1: Configure DNS (Route53)

Add these records in AWS Route53:

| Record Type | Name | Value |
|-------------|------|-------|
| A (Alias) | aurora-glam.com | ALB DNS name |
| A (Alias) | staging.aurora-glam.com | ALB DNS name |
| A (Alias) | argocd.aurora-glam.com | ALB DNS name |

### Step 2: Update Istio Gateway

The gateway must accept both domains:

```yaml
# istio/gateway.yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: salon-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: aurora-glam-tls
    hosts:
    - "aurora-glam.com"
    - "staging.aurora-glam.com"
    - "argocd.aurora-glam.com"
```

### Step 3: Configure VirtualServices

**Staging** (`staging/salon-routes.yaml`):
```yaml
spec:
  hosts:
  - "staging.aurora-glam.com"  # Only staging domain
  gateways:
  - istio-system/salon-gateway
```

**Production** (`production/salon-routes.yaml`):
```yaml
spec:
  hosts:
  - "aurora-glam.com"  # Only production domain
  gateways:
  - istio-system/salon-gateway
```

### Step 4: Add Production Deployment Workflow

Create `.github/workflows/deploy-production.yml` in frontend repo.

---

## 🎯 Quick Commands

### Check Current Deployments
```bash
# Staging
kubectl get pods -n staging
kubectl get deployment frontend -n staging -o jsonpath='{.spec.template.spec.containers[0].image}'

# Production
kubectl get pods -n production
kubectl get deployment frontend -n production -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Manual Promotion (Emergency)
```bash
# Get staging image tag
STAGING_TAG=$(kubectl get deployment frontend -n staging -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)

# Update production
kubectl set image deployment/frontend frontend=024955634588.dkr.ecr.us-east-1.amazonaws.com/frontend:$STAGING_TAG -n production
```

### Rollback Production
```bash
# Rollback to previous version
kubectl rollout undo deployment/frontend -n production

# Or rollback to specific revision
kubectl rollout undo deployment/frontend -n production --to-revision=2
```

---

## 🔐 Security Best Practices

1. **Separate Secrets**: Staging and production have different database credentials
2. **Access Control**: Only senior devs can trigger production deployments
3. **Audit Logs**: All deployments logged in GitHub Actions
4. **Rollback Ready**: Keep last 5 image versions in ECR

---

## 📋 Checklist for New Team Members

- [ ] Get access to GitHub repository
- [ ] Get access to ArgoCD dashboard (argocd.aurora-glam.com)
- [ ] Understand the staging → production flow
- [ ] Know how to check deployment status
- [ ] Know how to rollback if needed
- [ ] Read the API documentation

---

## 🆘 Troubleshooting

### Staging not updating?
1. Check GitHub Actions completed successfully
2. Check ArgoCD sync status: `kubectl get application frontend -n argocd`
3. Force sync: `kubectl annotate application frontend -n argocd argocd.argoproj.io/refresh=hard --overwrite`

### Production not updating after promotion?
1. Verify the workflow ran: GitHub → Actions → "Deploy to Production"
2. Check ArgoCD: `kubectl get application prod-frontend -n argocd`
3. Check pod status: `kubectl get pods -n production`

### Wrong version deployed?
1. Check GitOps repo for correct image tag
2. Rollback if needed: `kubectl rollout undo deployment/frontend -n production`

---

## 📞 Contact

- **DevOps Lead**: [Your Name]
- **Slack Channel**: #aurora-glam-devops
- **Emergency**: Check ArgoCD dashboard first, then contact DevOps

