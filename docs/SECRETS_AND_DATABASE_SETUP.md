# Secrets and Database Configuration Guide

> **Last Updated**: December 15, 2025  
> **Author**: DevOps Team  
> **Applies To**: Staging and Production environments

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [AWS RDS MySQL Configuration](#aws-rds-mysql-configuration)
4. [Kubernetes Secrets](#kubernetes-secrets)
5. [Service Database Configuration](#service-database-configuration)
6. [ECR Image Pull Secrets](#ecr-image-pull-secrets)
7. [How to Update Secrets](#how-to-update-secrets)
8. [Troubleshooting](#troubleshooting)
9. [Security Best Practices](#security-best-practices)

---

## Overview

The Salon Booking System uses a centralized secret management approach where all sensitive configuration values are stored in Kubernetes Secrets. This document describes:

- How secrets are structured and managed
- Database connection configuration
- How to recreate or update secrets
- Security considerations

### Key Secrets

| Secret Name | Namespace | Purpose |
|-------------|-----------|---------|
| `app-secrets` | staging | Application configuration (JWT, DB, SMTP) |
| `app-secrets` | production | Application configuration (JWT, DB, SMTP) |
| `aws-ecr-cred` | staging | ECR image pull credentials |
| `aws-ecr-cred` | production | ECR image pull credentials |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────┐    ┌─────────────────────────────────────┐ │
│  │     ap-south-1 (Mumbai)     │    │        eu-north-1 (Stockholm)       │ │
│  │                             │    │                                     │ │
│  │  ┌───────────────────────┐  │    │  ┌─────────────────────────────┐   │ │
│  │  │   Kubernetes Cluster  │  │    │  │      AWS RDS MySQL          │   │ │
│  │  │                       │  │    │  │                             │   │ │
│  │  │  ┌─────────────────┐  │  │    │  │  Endpoint:                  │   │ │
│  │  │  │ staging ns      │  │──┼────┼──│  database-1.cn8e0eyq896c.  │   │ │
│  │  │  │ - app-secrets   │  │  │    │  │  eu-north-1.rds.amazonaws  │   │ │
│  │  │  │ - aws-ecr-cred  │  │  │    │  │  .com:3306                 │   │ │
│  │  │  └─────────────────┘  │  │    │  │                             │   │ │
│  │  │                       │  │    │  │  Database: salon-db         │   │ │
│  │  │  ┌─────────────────┐  │  │    │  │  Engine: MySQL 8.0.43       │   │ │
│  │  │  │ production ns   │  │──┼────┼──│  Publicly Accessible: Yes   │   │ │
│  │  │  │ - app-secrets   │  │  │    │  │                             │   │ │
│  │  │  │ - aws-ecr-cred  │  │  │    │  └─────────────────────────────┘   │ │
│  │  │  └─────────────────┘  │  │    │                                     │ │
│  │  │                       │  │    └─────────────────────────────────────┘ │
│  │  └───────────────────────┘  │                                            │
│  │                             │    ┌─────────────────────────────────────┐ │
│  │  ┌───────────────────────┐  │    │        us-east-1 (N. Virginia)      │ │
│  │  │        ECR            │◄─┼────┤                                     │ │
│  │  │  (Image Registry)     │  │    │  ECR Repositories:                  │ │
│  │  └───────────────────────┘  │    │  - user_service                     │ │
│  │                             │    │  - appointment_service              │ │
│  └─────────────────────────────┘    │  - notification_service             │ │
│                                      │  - service_management              │ │
│                                      │  - staff_management                │ │
│                                      │  - reports_analytics               │ │
│                                      │  - frontend                        │ │
│                                      └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## AWS RDS MySQL Configuration

### Connection Details

| Property | Value |
|----------|-------|
| **Endpoint** | `database-1.cn8e0eyq896c.eu-north-1.rds.amazonaws.com` |
| **Port** | `3306` |
| **Engine** | MySQL 8.0.43 |
| **Region** | `eu-north-1` (Stockholm) |
| **Publicly Accessible** | Yes |
| **Master Username** | `admin` |

### Database Schema

All microservices share a single database named `salon-db` with the following tables:

```sql
-- salon-db tables
├── users              -- User accounts (used by user_service)
├── appointments       -- Booking appointments (used by appointment_service)
├── services           -- Salon services catalog (used by service_management)
├── staff              -- Staff members (used by staff_management)
├── staff_availability -- Staff schedules (used by staff_management)
└── sessions           -- User sessions (used by user_service)
```

### Important Notes

1. **Single Database Architecture**: All services use `salon-db`. The `user_service` code defaults to `user_db` but is overridden via environment variable.

2. **Cross-Region Access**: The Kubernetes cluster is in `ap-south-1` but connects to RDS in `eu-north-1`. This works because RDS is publicly accessible.

3. **Security Group**: RDS security group allows inbound MySQL (3306) from `0.0.0.0/0`.

---

## Kubernetes Secrets

### app-secrets Structure

The `app-secrets` secret contains all application configuration:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: staging  # or production
type: Opaque
data:
  # JWT Configuration
  JWT_SECRET_KEY: <base64-encoded-jwt-secret>
  
  # Database Configuration
  DB_HOST: <base64-encoded-rds-endpoint>
  DB_USER: <base64-encoded-username>
  DB_PASSWORD: <base64-encoded-password>
  
  # SMTP Configuration (for notification_service)
  SMTP_HOST: <base64-encoded-smtp-host>
  SMTP_PORT: <base64-encoded-smtp-port>
  SMTP_USER: <base64-encoded-smtp-user>
  SMTP_PASSWORD: <base64-encoded-smtp-password>
  FROM_EMAIL: <base64-encoded-sender-email>
```

### Secret Keys Reference

| Key | Description | Example Value |
|-----|-------------|---------------|
| `JWT_SECRET_KEY` | HMAC secret for JWT signing (128 chars hex) | `2094c3965195fc9915e078bb...` |
| `DB_HOST` | RDS MySQL endpoint | `database-1.cn8e0eyq896c.eu-north-1.rds.amazonaws.com` |
| `DB_USER` | Database username | `admin` |
| `DB_PASSWORD` | Database password | `********` |
| `SMTP_HOST` | SMTP server hostname | `smtp.gmail.com` |
| `SMTP_PORT` | SMTP server port | `587` |
| `SMTP_USER` | SMTP authentication username | `noreply@aurora-glam.com` |
| `SMTP_PASSWORD` | SMTP authentication password | `********` |
| `FROM_EMAIL` | Sender email address | `noreply@aurora-glam.com` |

### Creating app-secrets

**For Staging:**
```bash
kubectl create secret generic app-secrets \
  --namespace=staging \
  --from-literal=JWT_SECRET_KEY="<your-jwt-secret>" \
  --from-literal=DB_HOST="database-1.cn8e0eyq896c.eu-north-1.rds.amazonaws.com" \
  --from-literal=DB_USER="admin" \
  --from-literal=DB_PASSWORD="<your-db-password>" \
  --from-literal=SMTP_HOST="smtp.gmail.com" \
  --from-literal=SMTP_PORT="587" \
  --from-literal=SMTP_USER="<your-smtp-user>" \
  --from-literal=SMTP_PASSWORD="<your-smtp-password>" \
  --from-literal=FROM_EMAIL="noreply@aurora-glam.com"
```

**For Production:**
```bash
kubectl create secret generic app-secrets \
  --namespace=production \
  --from-literal=JWT_SECRET_KEY="<your-jwt-secret>" \
  --from-literal=DB_HOST="database-1.cn8e0eyq896c.eu-north-1.rds.amazonaws.com" \
  --from-literal=DB_USER="admin" \
  --from-literal=DB_PASSWORD="<your-db-password>" \
  --from-literal=SMTP_HOST="smtp.gmail.com" \
  --from-literal=SMTP_PORT="587" \
  --from-literal=SMTP_USER="<your-smtp-user>" \
  --from-literal=SMTP_PASSWORD="<your-smtp-password>" \
  --from-literal=FROM_EMAIL="noreply@aurora-glam.com"
```

---

## Service Database Configuration

### Environment Variables by Service

Each service deployment references secrets via environment variables:

| Service | DB_NAME | Port | Notes |
|---------|---------|------|-------|
| user_service | `salon-db` (override) | 8001 | Code defaults to `user_db`, overridden in deployment |
| service_management | `salon-db` (default) | 8002 | - |
| staff_management | `salon-db` (default) | 8003 | - |
| appointment_service | `salon-db` (default) | 8004 | - |
| reports_analytics | `salon-db` (default) | 8005 | - |
| notification_service | `salon-db` (default) | 8006 | - |

### user_service Special Configuration

The `user_service` requires an explicit `DB_NAME` environment variable because its code defaults to `user_db`:

```yaml
# staging/user_service/deployment.yaml
env:
  - name: DB_HOST
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: DB_HOST
  - name: DB_USER
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: DB_USER
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secrets
        key: DB_PASSWORD
  - name: DB_NAME
    value: "salon-db"  # Override default user_db to use shared database
```

---

## ECR Image Pull Secrets

### aws-ecr-cred Secret

The `aws-ecr-cred` secret is a Docker registry credential that allows Kubernetes to pull images from AWS ECR.

**Structure:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-ecr-cred
  namespace: staging  # or production
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-docker-config>
```

**Creating ECR Credentials:**
```bash
# Get ECR login token
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)

# Create the secret
kubectl create secret docker-registry aws-ecr-cred \
  --namespace=staging \
  --docker-server=024955634588.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}"
```

### Automatic Token Refresh

ECR tokens expire after 12 hours. The `ecr-credential-helper` CronJob automatically refreshes these credentials every 6 hours.

See: `staging/ecr-credential-helper.yaml`

---

## How to Update Secrets

### Option 1: Delete and Recreate

```bash
# Delete existing secret
kubectl delete secret app-secrets -n staging

# Create new secret
kubectl create secret generic app-secrets \
  --namespace=staging \
  --from-literal=JWT_SECRET_KEY="..." \
  --from-literal=DB_HOST="..." \
  # ... other values
```

### Option 2: Patch Specific Values

```bash
# Update a single value
kubectl patch secret app-secrets -n staging -p \
  '{"stringData":{"DB_PASSWORD":"new-password"}}'
```

### Option 3: Edit Interactively

```bash
kubectl edit secret app-secrets -n staging
# Note: Values are base64 encoded in the editor
```

### After Updating Secrets

**Restart pods to pick up new secret values:**
```bash
# Restart all deployments in staging
kubectl rollout restart deployment -n staging

# Or restart specific service
kubectl rollout restart deployment/user-service -n staging
```

---

## Troubleshooting

### Common Issues

#### 1. "Unknown database 'user_db'"

**Cause**: user_service is using default DB_NAME instead of salon-db

**Solution**: Ensure `DB_NAME: "salon-db"` is set in the deployment:
```yaml
env:
  - name: DB_NAME
    value: "salon-db"
```

#### 2. "Can't connect to MySQL server"

**Cause**: Network connectivity or security group issue

**Checks**:
```bash
# Test from inside a pod
kubectl exec -it deployment/user-service -n staging -c user-service -- \
  python3 -c "import socket; s=socket.socket(); s.settimeout(5); s.connect(('database-1.cn8e0eyq896c.eu-north-1.rds.amazonaws.com', 3306)); print('OK')"
```

#### 3. "secret 'app-secrets' not found"

**Cause**: Secret doesn't exist in the namespace

**Solution**: Create the secret (see [Creating app-secrets](#creating-app-secrets))

#### 4. "ImagePullBackOff"

**Cause**: ECR credentials expired or missing

**Solution**:
```bash
# Check if secret exists
kubectl get secret aws-ecr-cred -n staging

# Recreate if needed
ECR_TOKEN=$(aws ecr get-login-password --region us-east-1)
kubectl delete secret aws-ecr-cred -n staging --ignore-not-found
kubectl create secret docker-registry aws-ecr-cred \
  --namespace=staging \
  --docker-server=024955634588.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${ECR_TOKEN}"
```

### Verification Commands

```bash
# Check all secrets in namespace
kubectl get secrets -n staging

# View secret keys (not values)
kubectl get secret app-secrets -n staging -o jsonpath='{.data}' | jq 'keys'

# Decode a specific secret value
kubectl get secret app-secrets -n staging -o jsonpath='{.data.DB_HOST}' | base64 -d

# Check pod status
kubectl get pods -n staging

# Check pod events for errors
kubectl describe pod <pod-name> -n staging

# Check application logs
kubectl logs deployment/user-service -n staging -c user-service
```

---

## Security Best Practices

### DO ✅

1. **Use Kubernetes Secrets** for all sensitive values
2. **Rotate secrets regularly** (especially JWT keys)
3. **Use separate secrets** for staging and production
4. **Limit secret access** via RBAC policies
5. **Monitor secret access** in audit logs
6. **Use strong passwords** (min 16 characters, mixed case, numbers, symbols)

### DON'T ❌

1. **Never commit secrets to Git** (use templates with placeholders)
2. **Never share secrets in plain text** (Slack, email, etc.)
3. **Never use production secrets** in staging
4. **Never hardcode secrets** in application code
5. **Never log secret values** in application logs

### Secret Rotation Schedule

| Secret | Rotation Frequency | Notes |
|--------|-------------------|-------|
| JWT_SECRET_KEY | Every 90 days | Requires user re-authentication |
| DB_PASSWORD | Every 90 days | Update RDS and Kubernetes secret together |
| SMTP_PASSWORD | Per provider policy | Check email provider requirements |
| ECR Token | Every 12 hours | Automated via CronJob |

---

## API Routing Configuration

All API traffic is routed through Istio VirtualService via the `salon-gateway`.

### Public URL Mapping

| External Path | Backend Service | Internal Path |
|---------------|-----------------|---------------|
| `/api/users/*` | user-service | `/api/v1/*` |
| `/api/appointments/*` | appointment-service | `/api/v1/*` |
| `/api/services/*` | service-management | `/api/v1/*` |
| `/api/staff/*` | staff-management | `/api/v1/*` |
| `/api/notifications/*` | notification-service | `/api/v1/notifications/*` |
| `/api/reports/*` | reports-analytics | `/api/v1/analytics/*` |
| `/*` | frontend | `/*` (catch-all, must be last) |

### Health Check Endpoints

```bash
# User Service
curl https://aurora-glam.com/api/users/health

# Appointment Service
curl https://aurora-glam.com/api/appointments/health

# Service Management
curl https://aurora-glam.com/api/services/health

# Staff Management
curl https://aurora-glam.com/api/staff/health

# Notification Service
curl https://aurora-glam.com/api/notifications/health

# Reports & Analytics
curl https://aurora-glam.com/api/reports/health
```

### VirtualService Configuration

The routing is consolidated in `salon-routes.yaml` files:
- Staging: `staging/salon-routes.yaml`
- Production: `production/salon-routes.yaml`

**Important Notes:**
- Route order matters - more specific routes must come before generic ones
- The frontend catch-all (`/`) must be the LAST route
- All services use the `istio-system/salon-gateway` gateway

---

## Related Documentation

- [ECR Credential Helper](../staging/ecr-credential-helper.yaml)
- [Staging Secrets Template](../staging/secrets/app-secrets.example.yaml)
- [Production Secrets Template](../production/secrets/app-secrets.example.yaml)
- [Terraform RDS Reference](../../salon-k8s-infra/terraform/variables.tf)
- [Staging VirtualService Routes](../staging/salon-routes.yaml)
- [Production VirtualService Routes](../production/salon-routes.yaml)

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-15 | Initial documentation created | DevOps |
| 2025-12-15 | Added app-secrets with RDS credentials | DevOps |
| 2025-12-15 | Added DB_NAME override for user_service | DevOps |
| 2025-12-15 | Created secrets template files | DevOps |
| 2025-12-15 | Consolidated VirtualService routing | DevOps |
| 2025-12-15 | Fixed API path rewrites for all services | DevOps |
