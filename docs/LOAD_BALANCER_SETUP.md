# Load Balancer & HTTPS Setup Guide

This document describes the AWS Network Load Balancer (NLB) setup for the Salon application and how to configure HTTPS with Let's Encrypt.

## Current Infrastructure

### AWS Network Load Balancer (NLB)

**NLB Details:**
- **Name:** salon-istio-nlb
- **DNS Name:** `salon-istio-nlb-5b4828878eedd9f2.elb.us-east-1.amazonaws.com`
- **Region:** us-east-1
- **Type:** Network Load Balancer (Layer 4)

**Listeners:**
| Port | Protocol | Target Group |
|------|----------|--------------|
| 80   | TCP      | salon-istio-http (NodePort 31252) |
| 443  | TCP      | salon-istio-https (NodePort 32272) |

**Target Groups:**
- `salon-istio-http`: Routes to Istio ingress gateway HTTP (NodePort 31252)
- `salon-istio-https`: Routes to Istio ingress gateway HTTPS (NodePort 32272)

### Route53 DNS Configuration

**Domain:** aurora-glam.com  
**Hosted Zone ID:** Z09063931Q48E2MAYWPT1

**DNS Records:**
| Record | Type | Target |
|--------|------|--------|
| aurora-glam.com | A (Alias) | salon-istio-nlb |
| *.aurora-glam.com | A (Alias) | salon-istio-nlb |
| argocd.aurora-glam.com | A (Alias) | salon-istio-nlb |
| api.aurora-glam.com | A (Alias) | salon-istio-nlb |
| grafana.aurora-glam.com | A (Alias) | salon-istio-nlb |

### Istio Ingress Gateway

**Service:** istio-ingressgateway (istio-system namespace)
- **External IP:** 212.104.231.155 (internal/MetalLB - not publicly routable)
- **NodePorts:**
  - HTTP: 31252
  - HTTPS: 32272
  - Status: 31348

## HTTPS/TLS Setup

### Option 1: Manual Certificate (Current Approach)

For manual certificate management:

1. **Obtain Certificate:**
   - Get SSL certificate from a Certificate Authority (e.g., Let's Encrypt, DigiCert)
   - You'll need: `cert.pem` (certificate), `key.pem` (private key), `chain.pem` (CA chain)

2. **Create Kubernetes Secret:**
   ```bash
   kubectl create secret tls aurora-glam-tls \
     --cert=fullchain.pem \
     --key=privkey.pem \
     -n istio-system
   ```

3. **Apply HTTPS Gateway:**
   ```bash
   kubectl apply -f istio/gateway-https.yaml
   ```

### Option 2: Automated with cert-manager (Requires Additional Setup)

cert-manager is installed but needs an ingress controller (nginx) for HTTP-01 challenges with Istio:

1. **Install NGINX Ingress Controller:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml
   ```

2. **Update ClusterIssuer:**
   ```bash
   kubectl apply -f cert-manager/cluster-issuers.yaml
   ```

3. **Request Certificate:**
   ```bash
   kubectl apply -f cert-manager/certificate.yaml
   ```

### Option 3: AWS Certificate Manager (ACM) with ALB

For production with AWS-managed certificates:

1. **Create ACM Certificate:**
   ```bash
   aws acm request-certificate \
     --domain-name aurora-glam.com \
     --subject-alternative-names "*.aurora-glam.com" \
     --validation-method DNS \
     --region us-east-1
   ```

2. **Validate Certificate:** Add DNS validation records to Route53

3. **Replace NLB with ALB:** 
   - Create Application Load Balancer
   - Attach ACM certificate
   - Configure HTTPS listeners with SSL termination

## Verification Commands

### Check NLB Status
```bash
aws elbv2 describe-load-balancers \
  --load-balancer-arns arn:aws:elasticloadbalancing:us-east-1:024955634588:loadbalancer/net/salon-istio-nlb/5b4828878eedd9f2 \
  --region us-east-1 \
  --query 'LoadBalancers[0].{State:State.Code,DNSName:DNSName}'
```

### Check Target Health
```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:024955634588:targetgroup/salon-istio-http/62fcb842c8d123f1 \
  --region us-east-1 \
  --query 'TargetHealthDescriptions[*].{Id:Target.Id,State:TargetHealth.State}'
```

### Test Domain Access
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://aurora-glam.com
curl -s -o /dev/null -w "%{http_code}\n" http://argocd.aurora-glam.com
```

### Check Certificate (when HTTPS is configured)
```bash
curl -vI https://aurora-glam.com 2>&1 | grep -E "SSL|subject|expire"
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
