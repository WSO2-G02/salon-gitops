# Load Balancer & HTTPS Setup Guide

This document describes the AWS Application Load Balancer (ALB) setup for the Salon application with HTTPS using AWS Certificate Manager (ACM).

## Current Infrastructure (Production)

### AWS Application Load Balancer (ALB) - ACTIVE ✅

**ALB Details:**
- **Name:** salon-istio-alb
- **DNS Name:** `salon-istio-alb-688560610.us-east-1.elb.amazonaws.com`
- **Region:** us-east-1
- **Type:** Application Load Balancer (Layer 7)

**Listeners:**
| Port | Protocol | Action |
|------|----------|--------|
| 80   | HTTP     | Redirect to HTTPS (301) |
| 443  | HTTPS    | Forward to target group |

**Target Group:**
- `salon-istio-alb-tg`: Routes to Istio ingress gateway HTTP (NodePort 31252)
- Health Check: `/healthz/ready` on port 31348

**SSL/TLS:**
- Certificate: AWS ACM managed (`arn:aws:acm:us-east-1:024955634588:certificate/0ea09438-151c-41df-87cb-d126b869b73c`)
- Domains: `aurora-glam.com`, `*.aurora-glam.com`
- SSL Policy: `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.3)
- Certificate expires: January 12, 2027 (auto-renewed by AWS)

### Legacy NLB (Can be deleted)

**NLB Details:**
- **Name:** salon-istio-nlb
- **DNS Name:** `salon-istio-nlb-5b4828878eedd9f2.elb.us-east-1.amazonaws.com`
- **Type:** Network Load Balancer (Layer 4)
- **Status:** Replaced by ALB for HTTPS support

### Route53 DNS Configuration

**Domain:** aurora-glam.com  
**Hosted Zone ID:** Z09063931Q48E2MAYWPT1

**DNS Records (Pointing to ALB):**
| Record | Type | Target |
|--------|------|--------|
| aurora-glam.com | A (Alias) | salon-istio-alb |
| *.aurora-glam.com | A (Alias) | salon-istio-alb |
| argocd.aurora-glam.com | A (Alias) | salon-istio-alb |
| api.aurora-glam.com | A (Alias) | salon-istio-alb |
| grafana.aurora-glam.com | A (Alias) | salon-istio-alb |

### Istio Ingress Gateway

**Service:** istio-ingressgateway (istio-system namespace)
- **External IP:** 212.104.231.155 (internal/MetalLB - not publicly routable)
- **NodePorts:**
  - HTTP: 31252 (used by ALB)
  - HTTPS: 32272 (not used - TLS terminates at ALB)
  - Status: 31348 (health check)

## Architecture

```
Internet → ALB (HTTPS:443) → NodePort:31252 → Istio Gateway → VirtualServices → Services
                ↓
         TLS Termination
         (AWS ACM Certificate)
```

**Key Points:**
1. ALB handles TLS termination (HTTPS)
2. Traffic inside cluster is HTTP (port 80)
3. Istio Gateway only needs HTTP configuration
4. No TLS certificates needed in Kubernetes

## HTTPS Verification

Test HTTPS is working:
```bash
curl -sI https://argocd.aurora-glam.com | head -5
```

Expected output:
```
HTTP/2 200 
date: ...
content-type: text/html; charset=utf-8
```

Check SSL certificate:
```bash
curl -vI https://aurora-glam.com 2>&1 | grep -E "SSL|subject|issuer|expire"
```

## Verification Commands

### Check ALB Status
```bash
aws elbv2 describe-load-balancers \
  --names salon-istio-alb \
  --region us-east-1 \
  --query 'LoadBalancers[0].{State:State.Code,DNSName:DNSName}'
```

### Check Target Health
```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:024955634588:targetgroup/salon-istio-alb-tg/e9721c80e97d7bdc \
  --region us-east-1 \
  --query 'TargetHealthDescriptions[*].{Id:Target.Id,State:TargetHealth.State}'
```

### Check ACM Certificate
```bash
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:024955634588:certificate/0ea09438-151c-41df-87cb-d126b869b73c \
  --region us-east-1 \
  --query 'Certificate.{Status:Status,DomainName:DomainName,NotAfter:NotAfter}'
```

## Troubleshooting

### Targets Unhealthy

If NLB targets show unhealthy:

1. **Check Security Groups:** Ensure NodePort range (30000-32767) allows traffic from 0.0.0.0/0
   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id sg-0e0839ef96f77505b \
     --protocol tcp \
     --port 30000-32767 \
     --cidr 0.0.0.0/0 \
     --region us-east-1
   ```

2. **Verify Istio Gateway Pod:**
   ```bash
   kubectl get pods -n istio-system -l istio=ingressgateway
   ```

3. **Check NodePort Connectivity:**
   ```bash
   curl -v http://<worker-public-ip>:31252
   ```

### DNS Not Resolving

1. **Check Route53 Records:**
   ```bash
   aws route53 list-resource-record-sets --hosted-zone-id Z09063931Q48E2MAYWPT1
   ```

2. **Verify DNS Propagation:**
   ```bash
   dig aurora-glam.com +short
   nslookup aurora-glam.com
   ```

### cert-manager Issues

1. **Check Certificate Status:**
   ```bash
   kubectl get certificate -n istio-system
   kubectl describe certificate aurora-glam-tls -n istio-system
   ```

2. **Check Challenges:**
   ```bash
   kubectl get challenge -n istio-system
   kubectl describe challenge <challenge-name> -n istio-system
   ```

## Security Considerations

- **Security Group:** sg-0e0839ef96f77505b allows:
  - SSH (22) from 0.0.0.0/0
  - HTTP (80) from 0.0.0.0/0
  - Kubernetes API (6443) from 0.0.0.0/0
  - NodePorts (30000-32767) from 0.0.0.0/0

- **Recommendations:**
  - Restrict SSH access to specific IP ranges
  - Consider using AWS WAF with ALB for additional security
  - Enable VPC Flow Logs for network monitoring
