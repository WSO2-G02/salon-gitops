# Salon Booking Platform - Architecture Explained

This document provides a complete explanation of the infrastructure and architecture decisions for the salon booking platform.

---

## Table of Contents
1. [Traffic Flow Architecture](#traffic-flow-architecture)
2. [Why Gateway Shows HTTP Only](#why-gateway-shows-http-only)
3. [Do We Need NGINX?](#do-we-need-nginx)
4. [Files Created in istio/ Folder](#files-created-in-istio-folder)
5. [Should Infrastructure Be in Terraform?](#should-infrastructure-be-in-terraform)
6. [How Frontend Connects to Services](#how-frontend-connects-to-services)
7. [ArgoCD Repository Authentication](#argocd-repository-authentication)
8. [Summary of All Changes Made](#summary-of-all-changes-made)

---

## Traffic Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                            │
│                                 │                                                │
│                        ┌────────▼────────┐                                       │
│                        │    Route53      │                                       │
│                        │ aurora-glam.com │                                       │
│                        └────────┬────────┘                                       │
│                                 │                                                │
│                        ┌────────▼────────┐                                       │
│                        │   AWS ALB       │◄─── ACM Certificate                   │
│                        │ (HTTPS :443)    │     (*.aurora-glam.com)               │
│                        │ TLS TERMINATES  │                                       │
│                        │      HERE       │                                       │
│                        └────────┬────────┘                                       │
│                                 │ HTTP :80                                       │
├─────────────────────────────────┼───────────────────────────────────────────────┤
│                         KUBERNETES CLUSTER                                       │
│                                 │                                                │
│                        ┌────────▼────────┐                                       │
│                        │  Istio Ingress  │                                       │
│                        │    Gateway      │                                       │
│                        │    (HTTP :80)   │                                       │
│                        └────────┬────────┘                                       │
│                                 │                                                │
│                        ┌────────▼────────┐                                       │
│                        │  Istio Gateway  │ ◄── gateway.yaml                      │
│                        │   Resource      │     (HTTP only - intentional)         │
│                        └────────┬────────┘                                       │
│                                 │                                                │
│          ┌──────────────────────┼──────────────────────┐                         │
│          │                      │                      │                         │
│   ┌──────▼──────┐       ┌──────▼──────┐       ┌──────▼──────┐                   │
│   │VirtualService│       │VirtualService│       │VirtualService│                 │
│   │  /api/users  │       │/api/services │       │  /frontend   │                 │
│   └──────┬──────┘       └──────┬──────┘       └──────┬──────┘                   │
│          │                      │                      │                         │
│   ┌──────▼──────┐       ┌──────▼──────┐       ┌──────▼──────┐                   │
│   │user-service │       │service-mgmt │       │  frontend   │                   │
│   │    Pod      │       │    Pod      │       │    Pod      │                   │
│   └─────────────┘       └─────────────┘       └─────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Gateway Shows HTTP Only

**Question:** "Why does gateway.yaml only show HTTP when we set up HTTPS?"

**Answer:** This is intentional and correct! Here's why:

### TLS Termination at ALB

The AWS Application Load Balancer (ALB) handles TLS/HTTPS encryption:

```
User Browser ──HTTPS:443──► AWS ALB ──HTTP:80──► Istio Gateway ──► Services
              (encrypted)          (decrypted)    (internal)
```

### Benefits of This Approach

| Benefit | Explanation |
|---------|-------------|
| **Simpler Certificate Management** | AWS ACM automatically renews certificates |
| **Cost Savings** | No need to pay for certificate management in-cluster |
| **Performance** | ALB offloads TLS computation from your cluster |
| **Security** | Internal traffic stays within AWS VPC (already secure) |
| **Consistency** | Same pattern used by most AWS-hosted applications |

### The gateway.yaml Configuration

```yaml
# This is CORRECT - HTTP only because ALB terminates TLS
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
        number: 80          # HTTP only - ALB sends traffic here
        name: http
        protocol: HTTP
      hosts:
        - "aurora-glam.com"
        - "*.aurora-glam.com"
```

### Alternative: TLS at Istio (NOT USED)

If we wanted Istio to handle TLS (not recommended for this setup):
```yaml
# This would require certificate management in Kubernetes
servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: aurora-glam-tls-secret  # Would need cert-manager
```

---

## Do We Need NGINX?

**Question:** "Do we need NGINX?"

**Answer:** **No, NGINX is NOT needed.** Here's why:

### What NGINX Would Do vs What We Already Have

| Function | NGINX | Our Setup |
|----------|-------|-----------|
| **Load Balancing** | ✓ | AWS ALB handles this |
| **SSL/TLS Termination** | ✓ | AWS ALB + ACM handles this |
| **Reverse Proxy** | ✓ | Istio Gateway handles this |
| **Path-based Routing** | ✓ | Istio VirtualServices handle this |
| **Rate Limiting** | ✓ | Can be added to Istio |
| **Request/Response Manipulation** | ✓ | Istio EnvoyFilters can do this |

### Architecture Comparison

**With NGINX (unnecessary complexity):**
```
ALB → NGINX → Istio → Services  (3 hops)
```

**Our Setup (simpler, recommended):**
```
ALB → Istio → Services  (2 hops)
```

### When Would You Need NGINX?

You would only need NGINX if:
1. Not using a cloud load balancer (bare metal)
2. Need specific NGINX modules not available in Istio
3. Team has strong NGINX expertise and prefers it

**Conclusion:** Istio replaces NGINX in this architecture.

---

## Files Created in istio/ Folder

### Current Files

| File | Purpose | Status |
|------|---------|--------|
| `gateway.yaml` | Main Istio Gateway for all traffic | **ACTIVE - Required** |
| `gateway-https.yaml` | Alternative HTTPS config (Istio-managed TLS) | Not used - ALB handles TLS |
| `acme-challenge-vs.yaml` | Let's Encrypt ACME challenges | Not used - ACM handles certs |

### gateway.yaml (The Only One You Need)

```yaml
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
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "aurora-glam.com"
        - "*.aurora-glam.com"
```

### Other Files (Created for Reference)

These were created as alternatives but aren't actively used:

1. **gateway-https.yaml** - Would be used if Istio managed TLS directly
2. **acme-challenge-vs.yaml** - Would route Let's Encrypt verification requests

---

## Should Infrastructure Be in Terraform?

**Question:** "Should these AWS changes be in Terraform?"

**Answer:** **Yes, ideally.** Here's the breakdown:

### What Should Be in Terraform

| Resource | Currently | Should Be | Priority |
|----------|-----------|-----------|----------|
| VPC, Subnets | Terraform | ✓ Already there | - |
| EC2 Instances (Nodes) | Terraform | ✓ Already there | - |
| ECR Repositories | Terraform | ✓ Already there | - |
| **ALB (salon-istio-alb)** | **Manual/CLI** | **Terraform** | High |
| **Target Group** | **Manual/CLI** | **Terraform** | High |
| **ACM Certificate** | **Manual/CLI** | **Terraform** | Medium |
| **Route53 Records** | **Manual/CLI** | **Terraform** | Medium |

### Terraform Code to Add

Add this to `salon-k8s-infra/terraform/`:

**New file: `alb.tf`**
```hcl
# Application Load Balancer for Istio Ingress
resource "aws_lb" "istio_alb" {
  name               = "salon-istio-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name        = "salon-istio-alb"
    Environment = "staging"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.istio_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.aurora_glam.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.istio_ingress.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.istio_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_target_group" "istio_ingress" {
  name        = "istio-ingress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/healthz/ready"
    port                = "15021"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

# Attach worker nodes to target group
resource "aws_lb_target_group_attachment" "workers" {
  for_each = toset(var.worker_node_ids)

  target_group_arn = aws_lb_target_group.istio_ingress.arn
  target_id        = each.value
  port             = 30080  # Istio NodePort
}
```

**New file: `acm.tf`**
```hcl
resource "aws_acm_certificate" "aurora_glam" {
  domain_name               = "aurora-glam.com"
  subject_alternative_names = ["*.aurora-glam.com"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "aurora-glam-certificate"
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.aurora_glam.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.aurora_glam.zone_id
}

resource "aws_acm_certificate_validation" "aurora_glam" {
  certificate_arn         = aws_acm_certificate.aurora_glam.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
```

### Import Existing Resources

Since resources were created manually, import them:
```bash
terraform import aws_lb.istio_alb arn:aws:elasticloadbalancing:us-east-1:024955634588:loadbalancer/app/salon-istio-alb/...
terraform import aws_acm_certificate.aurora_glam arn:aws:acm:us-east-1:024955634588:certificate/0ea09438-151c-41df-87cb-d126b869b73c
```

---

## How Frontend Connects to Services

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         BROWSER                                  │
│                            │                                     │
│            ┌───────────────┴───────────────┐                    │
│            │                               │                    │
│     Page Request                   API Request                  │
│     (HTML/JS/CSS)                  (JSON data)                  │
│            │                               │                    │
│            ▼                               ▼                    │
│   aurora-glam.com/               aurora-glam.com/api/users      │
│                                  aurora-glam.com/api/services   │
│                                  aurora-glam.com/api/appointments│
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │   AWS ALB    │
                    │   (HTTPS)    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │Istio Gateway │
                    └──────┬───────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
   VirtualService    VirtualService    VirtualService
   (path: /)         (/api/users)      (/api/services)
         │                 │                 │
         ▼                 ▼                 ▼
   ┌─────────┐       ┌─────────┐       ┌─────────┐
   │Frontend │       │  User   │       │ Service │
   │  Pod    │       │ Service │       │  Mgmt   │
   └─────────┘       └─────────┘       └─────────┘
```

### Frontend Environment Configuration

The frontend needs to know where to send API requests. In Next.js:

**File: `src/lib/api-client.ts` or similar**
```typescript
const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || '';

// If NEXT_PUBLIC_API_URL is empty, requests go to same domain:
// fetch('/api/users') → https://aurora-glam.com/api/users
```

**For local development:**
```env
# .env.local
NEXT_PUBLIC_API_URL=http://localhost:8000
```

**For production (Kubernetes):**
```yaml
# deployment.yaml
env:
  - name: NEXT_PUBLIC_API_URL
    value: ""  # Empty = same domain
```

### VirtualService Routing

Each service has a VirtualService that routes requests:

```yaml
# staging/user_service/virtualservice.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: user-service-vs
spec:
  hosts:
    - "aurora-glam.com"
  gateways:
    - istio-system/salon-gateway
  http:
    - match:
        - uri:
            prefix: /api/users
      route:
        - destination:
            host: user-service
            port:
              number: 8000
```

### Complete URL Mapping

| Frontend Request | Routed To | Service |
|------------------|-----------|---------|
| `GET /` | frontend:3000 | Next.js app |
| `GET /api/users/me` | user-service:8000 | User Service |
| `POST /api/users/login` | user-service:8000 | User Service |
| `GET /api/services` | service-management:8000 | Service Mgmt |
| `GET /api/staff` | staff-management:8000 | Staff Mgmt |
| `GET /api/appointments` | appointment-service:8000 | Appointments |
| `POST /api/notifications` | notification-service:8000 | Notifications |
| `GET /api/reports` | reports-analytics:8000 | Reports |

---

## ArgoCD Repository Authentication

### Current Issue

ArgoCD shows "Repository not found" because:
1. `salon-gitops` is a **private** GitHub repository
2. ArgoCD doesn't have credentials to access it

### Solution: Add Repository Credentials

**Option 1: Via ArgoCD UI**

1. Go to: https://\<argocd-url\>/settings/repos
2. Click "Connect Repo"
3. Fill in:
   - Repository URL: `https://github.com/WSO2-G02/salon-gitops`
   - Username: Your GitHub username
   - Password: GitHub Personal Access Token (PAT)
4. Click "Connect"

**Option 2: Via kubectl**

```bash
# Create a GitHub PAT with 'repo' scope first

kubectl create secret generic argocd-repo-creds \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/WSO2-G02/salon-gitops \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_PAT

kubectl label secret argocd-repo-creds -n argocd \
  argocd.argoproj.io/secret-type=repository
```

**Option 3: Via declarative YAML**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: salon-gitops-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/WSO2-G02/salon-gitops
  username: <github-username>
  password: <github-pat>
```

### After Adding Credentials

1. Go to ArgoCD UI
2. Click "Refresh" on each application
3. Applications should sync successfully

---

## Summary of All Changes Made

### Infrastructure Changes (AWS)

| Change | Resource | Details |
|--------|----------|---------|
| Created | ALB | `salon-istio-alb` - Application Load Balancer |
| Created | Target Group | `istio-ingress-tg` - Routes to NodePort 30080 |
| Created | ACM Certificate | For `aurora-glam.com` and `*.aurora-glam.com` |
| Updated | Route53 | A record pointing to ALB |
| Deleted | NLB | Old Network Load Balancer (replaced by ALB) |

### Kubernetes Changes

| Change | File | Details |
|--------|------|---------|
| Created | `istio/gateway.yaml` | HTTP gateway (TLS at ALB) |
| Fixed | All VirtualServices | Gateway reference: `istio-system/salon-gateway` |
| Installed | cert-manager | For future certificate management |

### CI/CD Changes

| Change | Repo | Details |
|--------|------|---------|
| Fixed | `salon-booking-frontend-dev` | Removed artifact storage, push to ECR for scanning |
| Added | Both repos | Security workflows (DAST, SBOM, License) |

### Documentation Created

| File | Description |
|------|-------------|
| `docs/INFRASTRUCTURE_CHANGES.md` | Overview of infrastructure changes |
| `docs/LOAD_BALANCER_SETUP.md` | ALB setup details |
| `docs/ARGOCD_REPO_AUTH.md` | How to fix ArgoCD auth |
| `docs/ARCHITECTURE_EXPLAINED.md` | This comprehensive guide |

---

## Quick Reference

### URLs

| Service | URL |
|---------|-----|
| Frontend | https://aurora-glam.com |
| User API | https://aurora-glam.com/api/users |
| Services API | https://aurora-glam.com/api/services |
| Staff API | https://aurora-glam.com/api/staff |
| Appointments API | https://aurora-glam.com/api/appointments |

### kubectl Commands

```bash
# Check Istio gateway
kubectl get gateway -n istio-system

# Check VirtualServices
kubectl get virtualservice -n default

# Check pods
kubectl get pods -n default

# Check Istio ingress
kubectl get svc istio-ingressgateway -n istio-system
```

### AWS CLI Commands

```bash
# Check ALB
aws elbv2 describe-load-balancers --names salon-istio-alb

# Check certificate
aws acm describe-certificate --certificate-arn arn:aws:acm:us-east-1:024955634588:certificate/0ea09438-151c-41df-87cb-d126b869b73c
```

---

## Next Steps

1. [ ] **Fix ArgoCD authentication** - Add repo credentials (see section above)
2. [ ] **Add Terraform code** - Codify ALB/ACM in Terraform
3. [ ] **Test end-to-end** - Once ArgoCD syncs, test https://aurora-glam.com
4. [ ] **Monitor** - Set up CloudWatch alarms for ALB
5. [ ] **Performance testing** - Run load tests once deployed

---

*Document created: $(date)*
*For questions, contact the DevOps team.*
