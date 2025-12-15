# Salon Booking System - GitOps Repository

This repository contains the Kubernetes manifests and configuration for the Salon Booking System microservices deployment using ArgoCD.

## 📁 Repository Structure

```
salon-gitops/
├── argocd/                           # ArgoCD Application definitions
│   ├── appointment_service.yaml
│   ├── ecr_credential_helper.yaml
│   ├── frontend.yaml
│   ├── notification_service.yaml
│   ├── reports_analytics.yaml
│   ├── service_management.yaml
│   ├── staff_management.yaml
│   ├── user_service.yaml
│   └── prod-*.yaml                   # Production variants
│
├── staging/                          # Staging environment manifests
│   ├── appointment_service/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── frontend/
│   ├── notification_service/
│   ├── reports_analytics/
│   ├── service_management/
│   ├── staff_management/
│   ├── user_service/
│   ├── secrets/
│   │   └── app-secrets.example.yaml  # Template (DO NOT commit real secrets)
│   └── ecr-credential-helper.yaml
│
├── production/                       # Production environment manifests
│   └── (same structure as staging)
│
├── istio/                           # Istio Gateway configuration
│   └── gateway.yaml
│
└── docs/                            # Documentation
    └── SECRETS_AND_DATABASE_SETUP.md
```

## 🚀 Quick Start

### Prerequisites

1. Kubernetes cluster (v1.28+)
2. ArgoCD installed
3. Istio service mesh
4. AWS CLI configured
5. kubectl configured

### Initial Setup

1. **Create namespaces:**
   ```bash
   kubectl create namespace staging
   kubectl create namespace production
   kubectl label namespace staging istio-injection=enabled
   kubectl label namespace production istio-injection=enabled
   ```

2. **Create application secrets:**
   ```bash
   # See docs/SECRETS_AND_DATABASE_SETUP.md for full details
   kubectl create secret generic app-secrets \
     --namespace=staging \
     --from-literal=JWT_SECRET_KEY="<your-jwt-secret>" \
     --from-literal=DB_HOST="database-1.cn8e0eyq896c.eu-north-1.rds.amazonaws.com" \
     --from-literal=DB_USER="admin" \
     --from-literal=DB_PASSWORD="<your-password>" \
     --from-literal=SMTP_HOST="smtp.gmail.com" \
     --from-literal=SMTP_PORT="587" \
     --from-literal=SMTP_USER="<smtp-user>" \
     --from-literal=SMTP_PASSWORD="<smtp-password>" \
     --from-literal=FROM_EMAIL="noreply@aurora-glam.com"
   ```

3. **Create ECR pull secrets:**
   ```bash
   ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)
   kubectl create secret docker-registry aws-ecr-cred \
     --namespace=staging \
     --docker-server=024955634588.dkr.ecr.us-east-1.amazonaws.com \
     --docker-username=AWS \
     --docker-password="${ECR_TOKEN}"
   ```

4. **Apply ArgoCD applications:**
   ```bash
   kubectl apply -f argocd/
   ```

## 🏗️ Architecture

### Microservices

| Service | Port | Description |
|---------|------|-------------|
| user_service | 8001 | User authentication and management |
| service_management | 8002 | Salon services catalog |
| staff_management | 8003 | Staff and availability management |
| appointment_service | 8004 | Booking appointments |
| reports_analytics | 8005 | Business reports and analytics |
| notification_service | 8006 | Email/SMS notifications |
| frontend | 3000 | Next.js web application |

### Infrastructure

| Component | Region | Purpose |
|-----------|--------|---------|
| Kubernetes | ap-south-1 | Application workloads |
| AWS ECR | us-east-1 | Container image registry |
| AWS RDS MySQL | eu-north-1 | Database (salon-db) |
| AWS ALB | ap-south-1 | Load balancer with HTTPS |

### Network Flow

```
Internet → ALB (HTTPS) → Istio Gateway → Services
                              ↓
                         VirtualService
                              ↓
                    ┌─────────┴─────────┐
                    ↓                   ↓
                Frontend          Backend APIs
                (Next.js)         (FastAPI)
```

## 📚 Documentation

- **[Secrets and Database Setup](docs/SECRETS_AND_DATABASE_SETUP.md)** - Complete guide for secrets management, RDS configuration, and troubleshooting
- **[Secrets Template (Staging)](staging/secrets/app-secrets.example.yaml)** - Template for staging secrets
- **[Secrets Template (Production)](production/secrets/app-secrets.example.yaml)** - Template for production secrets

## 🔄 CI/CD Flow

```
Code Push → GitHub Actions CI/CD → Build & Push to ECR → Update GitOps Repo → ArgoCD Sync → Deploy to K8s
```

1. **Backend repo** (`salon-booking-backend-dev`): Builds all microservices
2. **Frontend repo** (`salon-booking-frontend-dev`): Builds Next.js app
3. **GitOps repo** (this repo): Updated automatically with new image tags
4. **ArgoCD**: Watches this repo and syncs to Kubernetes

## ⚠️ Important Notes

### Secrets Management

- **NEVER commit real secrets to this repository**
- Use `kubectl create secret` to create secrets directly in the cluster
- Template files in `*/secrets/` are examples only (contain placeholders)

### Database Configuration

- All services use `salon-db` database in RDS
- `user_service` requires explicit `DB_NAME=salon-db` (see deployment)
- RDS endpoint: `database-1.cn8e0eyq896c.eu-north-1.rds.amazonaws.com:3306`

### Image Tags

- Image tags are automatically updated by CI/CD pipelines
- Format: `<short-sha>-<timestamp>` (e.g., `d77fdfa8-20251214185501`)
- Do not manually edit image tags unless necessary

## 🛠️ Common Operations

### Check Pod Status
```bash
kubectl get pods -n staging
kubectl get pods -n production
```

### View Logs
```bash
kubectl logs deployment/user-service -n staging -c user-service
```

### Restart Services
```bash
kubectl rollout restart deployment -n staging
```

### Force ArgoCD Sync
```bash
argocd app sync user-service --force
```

## 📋 Checklist for New Deployments

- [ ] Namespaces created with Istio injection
- [ ] `app-secrets` created in target namespace
- [ ] `aws-ecr-cred` created in target namespace
- [ ] ArgoCD applications applied
- [ ] RDS security group allows cluster IP
- [ ] Istio Gateway configured
- [ ] DNS pointing to ALB

## 🔗 Related Repositories

- [salon-booking-backend-dev](https://github.com/WSO2-G02/salon-booking-backend-dev) - Backend microservices
- [salon-booking-frontend-dev](https://github.com/WSO2-G02/salon-booking-frontend-dev) - Frontend application
- [salon-k8s-infra](https://github.com/WSO2-G02/salon-k8s-infra) - Terraform infrastructure

## 📞 Support

For issues or questions:
1. Check [Secrets and Database Setup](docs/SECRETS_AND_DATABASE_SETUP.md) documentation
2. Review pod events: `kubectl describe pod <pod-name> -n staging`
3. Check ArgoCD sync status in the ArgoCD UI
