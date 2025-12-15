# Deployment Flow Documentation

This document explains the complete CI/CD and deployment flow for the Aurora Glam salon booking platform.

## Overview

The platform uses a **GitOps** approach with:
- **GitHub Actions** for CI/CD pipelines
- **ArgoCD** for Kubernetes deployment
- **Separate staging and production environments**

---

## Architecture Diagram

```mermaid
flowchart TB
    subgraph "Developer Workflow"
        DEV[Developer] -->|Push to main| FE_REPO[Frontend Repo]
        DEV -->|Push to main| BE_REPO[Backend Repo]
    end

    subgraph "CI/CD Pipeline"
        FE_REPO -->|Triggers| FE_CICD[Frontend CI/CD]
        BE_REPO -->|Triggers| BE_CICD[Backend CI/CD]
        
        FE_CICD -->|Build| FE_STAGING_IMG[Staging Image<br/>staging-xxx]
        FE_CICD -->|Build| FE_PROD_IMG[Production Image<br/>xxx]
        
        BE_CICD -->|Build| BE_IMG[Backend Image<br/>xxx]
    end

    subgraph "Container Registry"
        ECR[(AWS ECR)]
        FE_STAGING_IMG --> ECR
        FE_PROD_IMG --> ECR
        BE_IMG --> ECR
    end

    subgraph "GitOps Repository"
        GITOPS[salon-gitops]
        FE_CICD -->|Update staging| GITOPS
        BE_CICD -->|Update staging| GITOPS
        MANUAL[Manual Deploy] -->|Update production| GITOPS
    end

    subgraph "ArgoCD"
        ARGO[ArgoCD Controller]
        GITOPS -->|Watch| ARGO
    end

    subgraph "Kubernetes Cluster"
        ARGO -->|Deploy| STAGING[Staging Namespace]
        ARGO -->|Deploy| PROD[Production Namespace]
    end

    subgraph "User Access"
        STAGING -->|staging.aurora-glam.com| STAGING_USER[QA/Testing]
        PROD -->|aurora-glam.com| PROD_USER[End Users]
    end
```

---

## Frontend CI/CD Flow

### Trigger
- Push to `main` branch
- Pull request to `main`
- Manual workflow dispatch

### Pipeline Stages

```mermaid
flowchart LR
    A[Detect Changes] --> B[Unit Tests]
    B --> C[Build Images]
    C --> D[Security Scans]
    D --> E[Trivy Scan]
    E --> F[Push to ECR]
    F --> G[Update GitOps]
    
    style A fill:#e3f2fd
    style C fill:#fff3e0
    style D fill:#ffebee
    style E fill:#ffebee
    style G fill:#e8f5e9
```

### Build Stage Details

The frontend CI/CD builds **TWO separate Docker images**:

```mermaid
flowchart TB
    subgraph "Build Job"
        CODE[Source Code] --> BUILD_S[Build Staging]
        CODE --> BUILD_P[Build Production]
        
        BUILD_S -->|"STAGING_* secrets"| IMG_S[frontend:staging-abc123-xxx]
        BUILD_P -->|"PROD_* secrets"| IMG_P[frontend:abc123-xxx]
    end
    
    subgraph "Baked-in API URLs"
        IMG_S -->|Contains| STAGING_URLS["staging.aurora-glam.com/api/*"]
        IMG_P -->|Contains| PROD_URLS["aurora-glam.com/api/*"]
    end
```

| Image | Tag Format | API URLs Point To |
|-------|-----------|-------------------|
| Staging | `frontend:staging-{sha}-{timestamp}` | `staging.aurora-glam.com/api/*` |
| Production | `frontend:{sha}-{timestamp}` | `aurora-glam.com/api/*` |

### Why Two Images?

Next.js bakes environment variables at **build time**. A single image with production URLs deployed to staging would cause:
- ❌ CORS errors (staging domain calling production APIs)
- ❌ Data leakage between environments
- ❌ Testing against wrong data

---

## Backend CI/CD Flow

### Pipeline Stages

```mermaid
flowchart LR
    A[Detect Changes] --> B[Unit Tests]
    A --> C[SAST Scan]
    A --> D[Secret Scan]
    A --> E[IaC Scan]
    B --> F[Build Temp]
    C --> F
    D --> F
    E --> F
    F --> G[Trivy Scan]
    G --> H[Promote & Push]
    H --> I[Update GitOps]
    
    style A fill:#e3f2fd
    style F fill:#fff3e0
    style G fill:#ffebee
    style I fill:#e8f5e9
```

### Backend Image Strategy

Backend services build **ONE image** that works in both environments:
- Backend services **ARE** the APIs (they don't call other APIs)
- Environment-specific config comes from Kubernetes secrets
- Same image, different runtime configuration

```mermaid
flowchart TB
    subgraph "Backend Build"
        BE_CODE[Service Code] --> BE_IMG[service:abc123-xxx]
    end
    
    subgraph "Deployment"
        BE_IMG --> STAGING_K8S[Staging K8s]
        BE_IMG --> PROD_K8S[Production K8s]
        
        STAGING_K8S -->|"app-secrets"| STAGING_CONFIG[Staging DB, JWT, etc.]
        PROD_K8S -->|"app-secrets"| PROD_CONFIG[Production DB, JWT, etc.]
    end
```

---

## GitOps Update Flow

### Automatic (CI/CD)

```mermaid
sequenceDiagram
    participant CI as CI/CD Pipeline
    participant GIT as GitOps Repo
    participant ARGO as ArgoCD
    participant K8S as Kubernetes

    CI->>GIT: Update staging/*/deployment.yaml
    GIT->>ARGO: Webhook/Poll (3 min)
    ARGO->>K8S: Apply to staging namespace
    K8S-->>ARGO: Sync complete
```

### Manual Production Deployment

```mermaid
sequenceDiagram
    participant USER as DevOps Engineer
    participant GH as GitHub Actions
    participant GIT as GitOps Repo
    participant ARGO as ArgoCD
    participant K8S as Kubernetes

    USER->>GH: Trigger "Deploy to Production"
    USER->>GH: Select services, confirm "DEPLOY"
    GH->>GH: Read staging tag
    
    alt Frontend Service
        GH->>GH: Strip "staging-" prefix
        Note over GH: staging-abc123 → abc123
    end
    
    GH->>GH: Verify image exists in ECR
    GH->>GIT: Update production/*/deployment.yaml
    GIT->>ARGO: Detect change
    ARGO->>K8S: Apply to production namespace
```

---

## ArgoCD Configuration

### Application Structure

```mermaid
flowchart TB
    subgraph "ArgoCD Applications"
        subgraph "Staging"
            S_FE[frontend]
            S_US[user-service]
            S_AP[appointment-service]
            S_SM[service-management]
            S_ST[staff-management]
            S_NO[notification-service]
            S_RA[reports-analytics]
        end
        
        subgraph "Production"
            P_FE[prod-frontend]
            P_US[prod-user-service]
            P_AP[prod-appointment-service]
            P_SM[prod-service-management]
            P_ST[prod-staff-management]
            P_NO[prod-notification-service]
            P_RA[prod-reports-analytics]
        end
    end
    
    subgraph "GitOps Paths"
        S_PATH[staging/*]
        P_PATH[production/*]
    end
    
    S_FE -.->|watches| S_PATH
    S_US -.->|watches| S_PATH
    P_FE -.->|watches| P_PATH
    P_US -.->|watches| P_PATH
```

### Sync Policy

All ArgoCD applications have:
- **Automated sync**: Enabled
- **Prune**: True (removes deleted resources)
- **Self-heal**: True (reverts manual changes)

---

## Image Tag Flow

### Frontend

```mermaid
flowchart LR
    subgraph "CI/CD Builds"
        BUILD[Build Job]
        BUILD -->|staging URLs| S_TAG["staging-abc123-20251215"]
        BUILD -->|production URLs| P_TAG["abc123-20251215"]
    end
    
    subgraph "ECR Repository"
        ECR[(frontend)]
        S_TAG --> ECR
        P_TAG --> ECR
    end
    
    subgraph "Deployments"
        ECR -->|"staging-abc123-xxx"| STAGING[Staging]
        ECR -->|"abc123-xxx"| PROD[Production]
    end
```

### Backend Services

```mermaid
flowchart LR
    subgraph "CI/CD Builds"
        BUILD[Build Job]
        BUILD --> TAG["abc123-20251215"]
    end
    
    subgraph "ECR Repository"
        ECR[(service_name)]
        TAG --> ECR
    end
    
    subgraph "Deployments"
        ECR -->|"Same image"| STAGING[Staging]
        ECR -->|"Same image"| PROD[Production]
    end
```

---

## Manual Production Deployment

### How to Deploy

1. Go to **GitHub** → `salon-gitops` repository
2. Navigate to **Actions** → **Deploy to Production**
3. Click **Run workflow**

### Workflow Inputs

| Input | Options | Description |
|-------|---------|-------------|
| Services | `all`, `frontend`, `user_service`, etc. | Which services to deploy |
| Image Source | `promote-staging`, `specific-tag` | Use staging tag or custom tag |
| Specific Tag | (optional) | Custom tag if not promoting staging |
| Confirm | `DEPLOY` | Type exactly "DEPLOY" to confirm |

### Frontend Tag Transformation

When promoting frontend from staging to production:

```
Staging tag:    staging-abc12345-20251215123456
                   ↓ (strip "staging-" prefix)
Production tag: abc12345-20251215123456
```

This works because CI/CD builds both images with the same base tag, just different prefixes.

---

## Environment URLs

| Environment | Frontend URL | API Base URL |
|-------------|--------------|--------------|
| Staging | `https://staging.aurora-glam.com` | `https://staging.aurora-glam.com/api/*` |
| Production | `https://aurora-glam.com` | `https://aurora-glam.com/api/*` |

### API Routing

```mermaid
flowchart TB
    subgraph "Istio Gateway"
        GW[Gateway]
    end
    
    subgraph "Staging VirtualService"
        GW -->|staging.aurora-glam.com| S_VS[salon-routes]
        S_VS -->|/api/users/*| S_US[user-service:8001]
        S_VS -->|/api/services/*| S_SM[service-management:8002]
        S_VS -->|/api/appointments/*| S_AP[appointment-service:8003]
        S_VS -->|/api/staff/*| S_ST[staff-management:8004]
        S_VS -->|/api/notifications/*| S_NO[notification-service:8005]
        S_VS -->|/api/reports/*| S_RA[reports-analytics:8006]
        S_VS -->|/*| S_FE[frontend:3000]
    end
    
    subgraph "Production VirtualService"
        GW -->|aurora-glam.com| P_VS[salon-routes]
        P_VS -->|/api/*| P_SERVICES[Backend Services]
        P_VS -->|/*| P_FE[frontend:3000]
    end
```

---

## Troubleshooting

### CORS Errors on Staging

**Symptom**: Staging frontend shows CORS errors when calling APIs

**Cause**: Staging frontend is calling production APIs (wrong image deployed)

**Solution**: Ensure staging deployment uses `frontend:staging-xxx` image with staging API URLs baked in

### ArgoCD Not Syncing

**Check**:
1. ArgoCD application status at `https://argocd.aurora-glam.com`
2. GitOps repository has the latest changes
3. Application sync policy is set to automated

### Image Not Found in ECR

**When deploying to production**:
1. Verify CI/CD pipeline completed successfully
2. Check ECR repository for the expected tag
3. For frontend, ensure both `staging-xxx` and `xxx` tags exist

---

## Repository Structure

```
salon-gitops/
├── argocd/                    # ArgoCD Application manifests
│   ├── frontend.yaml          # Staging frontend app
│   ├── prod-frontend.yaml     # Production frontend app
│   ├── user_service.yaml      # Staging user service
│   ├── prod-user_service.yaml # Production user service
│   └── ...
├── staging/                   # Staging K8s manifests
│   ├── frontend/
│   │   └── deployment.yaml
│   ├── user_service/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── hpa.yaml
│   └── ...
├── production/                # Production K8s manifests
│   ├── frontend/
│   ├── user_service/
│   └── ...
├── istio/                     # Istio configuration
│   └── gateway.yaml
└── .github/workflows/
    └── deploy-production.yml  # Manual production deployment
```

---

## Related Documentation

- [Infrastructure Domain Guide](./INFRASTRUCTURE_DOMAIN_GUIDE.md)
- [Deployment Architecture](./DEPLOYMENT_ARCHITECTURE.md)
