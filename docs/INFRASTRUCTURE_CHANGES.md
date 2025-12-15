# Infrastructure Changes - December 14, 2025

This document outlines all infrastructure changes made to the Salon Booking application.

## Summary of Changes

| Component | Change | Status |
|-----------|--------|--------|
| AWS ALB | Created Application Load Balancer with HTTPS | ✅ Active |
| AWS ACM | SSL certificate for aurora-glam.com | ✅ Issued |
| AWS NLB | Deleted (replaced by ALB) | ✅ Removed |
| Route53 | DNS records point to ALB | ✅ Updated |
| cert-manager | Installed in cluster | ✅ Installed |
| VirtualServices | Fixed gateway references | ✅ Fixed |
| Frontend CI/CD | Fixed artifact upload issue | ✅ Fixed |

---

## 1. AWS Application Load Balancer (ALB)

### Created Resources

**ALB:**
- Name: `salon-istio-alb`
- ARN: `arn:aws:elasticloadbalancing:us-east-1:024955634588:loadbalancer/app/salon-istio-alb/d185e4c99a979fea`
- DNS: `salon-istio-alb-688560610.us-east-1.elb.amazonaws.com`
- Type: Application Load Balancer (Layer 7)
- Scheme: Internet-facing

**Listeners:**
| Port | Protocol | Action |
|------|----------|--------|
| 80 | HTTP | Redirect to HTTPS (301) |
| 443 | HTTPS | Forward to target group |

**Target Group:**
- Name: `salon-istio-alb-tg`
- ARN: `arn:aws:elasticloadbalancing:us-east-1:024955634588:targetgroup/salon-istio-alb-tg/e9721c80e97d7bdc`
- Port: 31252 (Istio ingress NodePort)
- Health Check: `/healthz/ready` on port 31348

### Why ALB instead of NLB?

- **TLS Termination:** ALB handles HTTPS at the edge, Istio receives HTTP
- **AWS ACM Integration:** Free, auto-renewing certificates
- **No cluster TLS config needed:** Simplifies Istio Gateway configuration
- **Layer 7 features:** Path-based routing, sticky sessions if needed

---

## 2. AWS Certificate Manager (ACM)

**Certificate:**
- ARN: `arn:aws:acm:us-east-1:024955634588:certificate/0ea09438-151c-41df-87cb-d126b869b73c`
- Domains: `aurora-glam.com`, `*.aurora-glam.com`
- Status: Issued
- Expires: January 12, 2027 (auto-renewed by AWS)
- Validation: DNS (CNAME record in Route53)

**SSL Policy:** `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.3)

---

## 3. Route53 DNS Changes

**Hosted Zone:** Z09063931Q48E2MAYWPT1 (aurora-glam.com)

**Updated Records (all point to ALB):**
| Record | Type | Target |
|--------|------|--------|
| aurora-glam.com | A (Alias) | salon-istio-alb |
| *.aurora-glam.com | A (Alias) | salon-istio-alb |
| argocd.aurora-glam.com | A (Alias) | salon-istio-alb |
| api.aurora-glam.com | A (Alias) | salon-istio-alb |
| grafana.aurora-glam.com | A (Alias) | salon-istio-alb |

**Added for ACM validation:**
| Record | Type | Purpose |
|--------|------|---------|
| _19451237fc9144627971d57d46029012.aurora-glam.com | CNAME | ACM validation |

---

## 4. Security Group Changes

**Security Group:** sg-0e0839ef96f77505b (salon-app-ec2-sg)

**Added Rule:**
- Type: Custom TCP
- Port Range: 30000-32767
- Source: 0.0.0.0/0
- Purpose: Allow NodePort traffic from ALB/NLB

---

## 5. Kubernetes Changes

### cert-manager Installation

cert-manager v1.14.4 installed for future automated certificate management:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
```

**Note:** Currently not actively used since ALB handles TLS. Can be used for internal mTLS if needed.

### VirtualService Gateway Reference Fix

All VirtualServices in `staging/` were updated to correctly reference the gateway:

**Before:**
```yaml
gateways:
- salon-gateway
```

**After:**
```yaml
gateways:
- istio-system/salon-gateway
```

**Files Updated:**
- staging/frontend/virtualservice.yaml
- staging/user_service/virtualservice.yaml
- staging/appointment_service/virtualservice.yaml
- staging/notification_service/virtualservice.yaml
- staging/reports_analytics/virtualservice.yaml
- staging/service_management/virtualservice.yaml
- staging/staff_management/virtualservice.yaml

---

## 6. Frontend CI/CD Fix

**Issue:** Trivy scan failing with "Artifact not found for name: image-frontend"

**Root Cause:** `continue-on-error: true` on artifact upload step was hiding failures

**Fix in `salon-booking-frontend-dev/.github/workflows/ci-cd.yml`:**

**Before:**
```yaml
- name: Upload image artifact
  uses: actions/upload-artifact@v4
  continue-on-error: true
  with:
    name: image-frontend
    path: image-frontend.tar.gz
    retention-days: 1
```

**After:**
```yaml
- name: Save image artifact
  run: |
    docker save ${{ steps.meta.outputs.full_image }} | gzip > image-frontend.tar.gz
    ls -la image-frontend.tar.gz
    
- name: Upload image artifact
  uses: actions/upload-artifact@v4
  with:
    name: image-frontend
    path: image-frontend.tar.gz
    retention-days: 1
    if-no-files-found: error
```

---

## 7. Deleted Resources

### AWS Network Load Balancer (NLB)

**Deleted:**
- Name: `salon-istio-nlb`
- ARN: `arn:aws:elasticloadbalancing:us-east-1:024955634588:loadbalancer/net/salon-istio-nlb/5b4828878eedd9f2`
- Reason: Replaced by ALB for HTTPS support

**Associated Target Groups (can be deleted):**
- `salon-istio-http` (port 31252)
- `salon-istio-https` (port 32272)

---

## 8. Architecture Overview

```
                    Internet
                        │
                        ▼
              ┌─────────────────────┐
              │      Route53        │
              │  aurora-glam.com    │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │    AWS ALB          │ ← HTTPS terminates here
              │  (salon-istio-alb)  │ ← ACM certificate
              │   Port 443 HTTPS    │
              │   Port 80 → 301     │
              └─────────┬───────────┘
                        │ HTTP (internal)
                        ▼
              ┌─────────────────────┐
              │ EC2 Worker Nodes    │
              │  NodePort: 31252    │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │  Istio Ingress GW   │ ← HTTP only (port 80)
              │  (istio-system)     │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │   VirtualServices   │ ← Route by path/host
              └─────────┬───────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   ┌─────────┐    ┌──────────┐    ┌──────────┐
   │Frontend │    │   API    │    │  ArgoCD  │
   │   /     │    │/api/*    │    │ argocd.  │
   └─────────┘    └──────────┘    └──────────┘
```

---

## 9. Current Service Routing

| URL Path | Service | Namespace |
|----------|---------|-----------|
| `/` | frontend | staging |
| `/user-service/*` | user-service | staging |
| `/appointment/*` | appointment-service | staging |
| `/notification/*` | notification-service | staging |
| `/staff-management/*` | staff-management | staging |
| `/service-management/*` | service-management | staging |
| `/reports-analytics/*` | reports-analytics | staging |
| `argocd.aurora-glam.com` | argocd-server | argocd |

---

## 10. Verification Commands

### Test HTTPS
```bash
curl -sI https://aurora-glam.com | head -5
curl -sI https://argocd.aurora-glam.com | head -5
```

### Check ALB Health
```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:024955634588:targetgroup/salon-istio-alb-tg/e9721c80e97d7bdc \
  --region us-east-1
```

### Check Certificate
```bash
curl -vI https://aurora-glam.com 2>&1 | grep -E "SSL|subject|issuer|expire"
```

### Check ArgoCD Applications
```bash
kubectl get applications -n argocd
```

---

## 11. Pending Actions

### ArgoCD Repository Credentials (REQUIRED)

ArgoCD cannot sync because the GitOps repo is private. Add credentials:

1. **Login to ArgoCD:**
   - URL: https://argocd.aurora-glam.com
   - Username: `admin`
   - Password: `MYUYWpmIyJRgtZaG`

2. **Add Repository Credentials:**
   - Go to Settings → Repositories → Connect Repo
   - Repository URL: `https://github.com/WSO2-G02/salon-gitops`
   - Username: Your GitHub username
   - Password: GitHub Personal Access Token (with `repo` scope)

Or via CLI:
```bash
kubectl create secret generic argocd-repo-creds \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/WSO2-G02/salon-gitops \
  --from-literal=username=<GITHUB_USERNAME> \
  --from-literal=password=<GITHUB_PAT>

kubectl label secret argocd-repo-creds -n argocd argocd.argoproj.io/secret-type=repository
```

---

## 12. Files Changed in This Session

### salon-gitops/
- `staging/*/virtualservice.yaml` - Fixed gateway references (7 files)
- `docs/LOAD_BALANCER_SETUP.md` - Updated with ALB information
- `docs/ARGOCD_REPO_AUTH.md` - Created
- `docs/INFRASTRUCTURE_CHANGES.md` - Created (this file)
- `cert-manager/` - Created directory with cluster issuer configs
- `istio/gateway-https.yaml` - Created (not applied, for reference)

### salon-booking-frontend-dev/
- `.github/workflows/ci-cd.yml` - Fixed artifact upload issue

---

## 13. Rollback Instructions

If issues occur, here's how to rollback:

### Revert to NLB (if needed)
```bash
# Create NLB again
aws elbv2 create-load-balancer \
  --name salon-istio-nlb \
  --type network \
  --subnets subnet-0523626e5aa0971af subnet-02945ed405c1a1477 \
  --region us-east-1

# Update Route53 to point to NLB
# (use NLB DNS name instead of ALB)
```

### Revert VirtualServices
```bash
# Change gateway reference back
sed -i 's|istio-system/salon-gateway|salon-gateway|g' staging/*/virtualservice.yaml
```
