# Incident Report: ECR Credential Expiration & Infrastructure Issues

**Date:** December 15, 2025  
**Duration:** ~4 hours  
**Severity:** High (Complete service outage)  
**Status:** Resolved  

---

## Executive Summary

On December 15, 2025, a cascading infrastructure failure caused complete unavailability of the Salon Booking application in both staging and production environments. The root cause was a combination of expired ECR (Elastic Container Registry) credentials and misconfigured ALB (Application Load Balancer) security groups. This document details the investigation process, discoveries made, and the systematic approach taken to restore service and implement permanent fixes.

---

## Table of Contents

1. [Timeline of Events](#timeline-of-events)
2. [Initial Symptoms](#initial-symptoms)
3. [Investigation Process](#investigation-process)
4. [Root Cause Analysis](#root-cause-analysis)
5. [Resolution Steps](#resolution-steps)
6. [Architectural Discoveries](#architectural-discoveries)
7. [Permanent Fixes Implemented](#permanent-fixes-implemented)
8. [Lessons Learned](#lessons-learned)
9. [Recommendations](#recommendations)

---

## Timeline of Events

| Time (UTC) | Event |
|------------|-------|
| Dec 14, 18:11 | ECR registry secret manually created in cluster |
| Dec 14, 23:43 | External Secrets setup added with PLACEHOLDER credentials |
| Dec 15, 06:11 | ECR token expires (12-hour validity) |
| Dec 15, ~08:00 | Users report 404 errors on staging |
| Dec 15, ~09:30 | Investigation begins |
| Dec 15, ~10:00 | ErrImagePull discovered on pods |
| Dec 15, ~10:30 | ECR credential expiration identified |
| Dec 15, ~11:00 | Manual ECR refresh performed, pods recover |
| Dec 15, ~11:30 | 504 Gateway Timeout discovered |
| Dec 15, ~12:00 | ALB security group misconfiguration identified |
| Dec 15, ~12:15 | ALB security group corrected |
| Dec 15, ~12:30 | Services restored, permanent fix implemented |
| Dec 15, ~13:00 | CronJob fix committed and pushed |

---

## Initial Symptoms

### Reported Issues
1. **404 Not Found** errors when accessing `staging.aurora-glam.com`
2. Frontend pages not loading
3. API calls failing

### Initial Observations
```
$ kubectl get pods -n staging
NAME                                  READY   STATUS             RESTARTS   AGE
appointment-service-xxx               1/2     ErrImagePull       0          2h
frontend-xxx                          1/2     ErrImagePull       0          2h
notification-service-xxx              1/2     ErrImagePull       0          2h
...
```

All pods showed `ErrImagePull` status, indicating Kubernetes could not pull container images from ECR.

---

## Investigation Process

### Step 1: Verify Image Existence

First, we confirmed the images existed in ECR:

```bash
$ aws ecr describe-images --repository-name salon/frontend --query 'imageDetails[*].imageTags'
[
    ["staging-abc123", "latest"]
]
```

✅ Images existed - the problem was authentication, not missing images.

### Step 2: Check Image Pull Secrets

```bash
$ kubectl get secret ecr-registry -n staging -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
{
  "auths": {
    "024955634588.dkr.ecr.us-east-1.amazonaws.com": {
      "auth": "QVdTOmV5SmhiR2...<truncated>"
    }
  }
}
```

Decoded the auth token and checked expiration - **token was expired**.

### Step 3: Investigate CronJob

The ECR credential helper CronJob was supposed to refresh tokens every 6 hours:

```bash
$ kubectl get cronjob -n kube-system ecr-cred-helper
NAME              SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
ecr-cred-helper   0 */6 * * *   False     0        12h             3d
```

Checked the last job:

```bash
$ kubectl logs job/ecr-cred-helper-xxx -n kube-system
Unable to locate credentials. You can configure credentials by running "aws configure".
```

❌ **The CronJob was failing due to missing AWS credentials.**

### Step 4: Examine CronJob Configuration

```yaml
# Original configuration
containers:
- name: ecr-cred-helper
  image: amazon/aws-cli:latest
  env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: aws-credentials
        key: AWS_ACCESS_KEY_ID
```

Checked for the referenced secret:

```bash
$ kubectl get secret aws-credentials -n kube-system
Error from server (NotFound): secrets "aws-credentials" not found
```

### Step 5: Git History Investigation

Examined the git history to understand why:

```bash
$ git log --oneline staging/ecr-credential-helper/
abc1234 feat: Add External Secrets for ECR credentials
def5678 Initial ECR credential helper setup
```

Found a commit that added External Secrets integration with **PLACEHOLDER** values:

```yaml
# From External Secrets configuration
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
spec:
  data:
  - secretKey: AWS_ACCESS_KEY_ID
    remoteRef:
      key: PLACEHOLDER  # <-- Never configured!
  - secretKey: AWS_SECRET_ACCESS_KEY
    remoteRef:
      key: PLACEHOLDER  # <-- Never configured!
```

**The External Secrets setup was never completed - it had placeholder values.**

### Step 6: Manual Secret Investigation

Someone had manually created the ECR secret directly in the cluster:

```bash
$ kubectl get secret ecr-registry -n staging -o yaml
metadata:
  creationTimestamp: "2025-12-14T18:11:00Z"
  annotations:
    description: "Manually created - TODO: automate"
```

This manual secret worked initially but expired after 12 hours.

---

## Root Cause Analysis

### Primary Cause: Broken Automation Chain

```
┌─────────────────────────────────────────────────────────────────────┐
│                    INTENDED FLOW (Never Worked)                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  AWS Secrets Manager ──► External Secrets ──► aws-credentials       │
│                                    │                                │
│                                    ▼                                │
│                             CronJob reads credentials               │
│                                    │                                │
│                                    ▼                                │
│                          ECR token generated                        │
│                                    │                                │
│                                    ▼                                │
│                         ecr-registry secret updated                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      ACTUAL STATE (Broken)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  AWS Secrets Manager ──► External Secrets ──► PLACEHOLDER           │
│                                    │                                │
│                                    ▼                                │
│                             aws-credentials = EMPTY                 │
│                                    │                                │
│                                    ▼                                │
│                          CronJob FAILS ❌                           │
│                                                                     │
│  WORKAROUND: Manual ecr-registry secret (expires in 12h)           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Secondary Cause: ALB Security Group Misconfiguration

After fixing ECR credentials, services still returned 504 errors:

```bash
$ curl https://staging.aurora-glam.com
<html>
<head><title>504 Gateway Time-out</title></head>
...
```

Investigation revealed the ALB was using the wrong security group:

```bash
$ aws elbv2 describe-load-balancers --names salon-istio-alb \
    --query 'LoadBalancers[0].SecurityGroups'
[
    "sg-0e0839ef96f77505b"  # salon-app-ec2-sg (WRONG!)
]
```

The EC2 security group (`salon-app-ec2-sg`) only allows NodePort traffic from the ELB security group (`salon-app-elb-sg`). The ALB should have been using `salon-app-elb-sg`.

### Security Group Rules

```
┌──────────────────────────────────────────────────────────────────┐
│                     Security Group Flow                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Internet ──► ALB (needs elb-sg) ──► NodePort ──► EC2 (ec2-sg)  │
│                                                                  │
│  EC2 Security Group Rules:                                       │
│  - Allow 30000-32767 FROM elb-sg only                           │
│  - Deny all other inbound traffic                               │
│                                                                  │
│  PROBLEM: ALB had ec2-sg, not elb-sg                            │
│  RESULT: EC2 rejected traffic from ALB (wrong source SG)        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Resolution Steps

### Phase 1: Immediate Recovery (Manual)

#### Step 1.1: Manual ECR Token Refresh

```bash
# Generate new ECR token
TOKEN=$(aws ecr get-login-password --region us-east-1)

# Create Docker config JSON
DOCKER_CONFIG=$(echo -n "{\"auths\":{\"024955634588.dkr.ecr.us-east-1.amazonaws.com\":{\"auth\":\"$(echo -n "AWS:${TOKEN}" | base64)\"}}}")

# Update secrets in all namespaces
for ns in staging production; do
  kubectl delete secret ecr-registry -n $ns --ignore-not-found
  kubectl create secret docker-registry ecr-registry \
    --docker-server=024955634588.dkr.ecr.us-east-1.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$TOKEN \
    -n $ns
done
```

#### Step 1.2: Restart Affected Pods

```bash
kubectl rollout restart deployment -n staging
kubectl rollout restart deployment -n production
```

**Result:** Pods now pulling images successfully. But 504 errors persisted.

### Phase 2: ALB Security Group Fix

#### Step 2.1: Identify Correct Security Group

```bash
$ aws ec2 describe-security-groups --filters "Name=group-name,Values=*salon*" \
    --query 'SecurityGroups[*].[GroupId,GroupName]'
[
    ["sg-003828d66ed93f82d", "salon-app-elb-sg"],
    ["sg-0e0839ef96f77505b", "salon-app-ec2-sg"]
]
```

#### Step 2.2: Update ALB Security Group

```bash
aws elbv2 set-security-groups \
    --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:024955634588:loadbalancer/app/salon-istio-alb/abc123 \
    --security-groups sg-003828d66ed93f82d
```

**Result:** Services immediately accessible. 504 errors resolved.

### Phase 3: Permanent Fix Implementation

#### Step 3.1: Create Dedicated IAM User

```bash
# Create IAM user for ECR access
aws iam create-user --user-name salon-ecr-pull

# Attach ECR read policy
aws iam attach-user-policy \
    --user-name salon-ecr-pull \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# Create access key
aws iam create-access-key --user-name salon-ecr-pull
```

#### Step 3.2: Create Kubernetes Secret

```bash
kubectl create secret generic aws-credentials \
    --namespace kube-system \
    --from-literal=AWS_ACCESS_KEY_ID=AKIAQLT3YYOOEFCOQLZV \
    --from-literal=AWS_SECRET_ACCESS_KEY=<secret-key>
```

#### Step 3.3: Update CronJob

Changed the CronJob to use a different base image and reference the credentials:

```yaml
# BEFORE (broken)
containers:
- name: ecr-cred-helper
  image: amazon/aws-cli:latest
  # No credentials - relied on missing External Secrets

# AFTER (working)
containers:
- name: ecr-cred-helper
  image: alpine/k8s:1.28.4  # Has kubectl built-in
  env:
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: aws-credentials
        key: AWS_ACCESS_KEY_ID
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: aws-credentials
        key: AWS_SECRET_ACCESS_KEY
  command:
  - /bin/sh
  - -c
  - |
    set -e
    apk add --no-cache aws-cli > /dev/null 2>&1
    TOKEN=$(aws ecr get-login-password --region ${REGION})
    # ... rest of script
```

#### Step 3.4: Test CronJob

```bash
# Manually trigger the job
kubectl create job --from=cronjob/ecr-cred-helper test-run -n kube-system

# Check logs
kubectl logs job/test-run -n kube-system
# Output: Successfully updated ECR credentials in staging, production namespaces
```

---

## Architectural Discoveries

### Discovery 1: External Secrets Was Never Configured

The External Secrets Operator was installed but:
- Secret store was never created
- AWS Secrets Manager integration was never set up
- PLACEHOLDER values were committed and never replaced

### Discovery 2: Original Design Relied on EC2 Instance Profile

The original CronJob design assumed it would run on EC2 and use the instance profile for AWS credentials. However:
- Kubernetes pods don't automatically inherit EC2 instance profiles
- This requires additional configuration (kiam, kube2iam, or IRSA for EKS)
- None of these were set up

### Discovery 3: ALB Was Manually Created

The ALB was created manually via AWS Console, not Terraform:
- Used wrong security group by mistake
- Not in infrastructure-as-code
- No documentation of configuration

### Discovery 4: No Monitoring for ECR Token Expiration

There was no alerting for:
- CronJob failures
- ECR credential expiration
- Image pull failures

---

## Permanent Fixes Implemented

### 1. ECR Credential Helper CronJob

| Aspect | Before | After |
|--------|--------|-------|
| Image | `amazon/aws-cli:latest` | `alpine/k8s:1.28.4` |
| kubectl | Not included | Built-in |
| AWS CLI | Built-in | Installed via apk |
| Credentials | External Secrets (broken) | Direct secret reference |
| Schedule | Every 6 hours | Every 6 hours (unchanged) |

### 2. IAM User for ECR Access

- **User:** `salon-ecr-pull`
- **Policy:** `AmazonEC2ContainerRegistryReadOnly`
- **Purpose:** Dedicated service account for ECR token generation
- **Access Key:** Stored in `aws-credentials` secret in `kube-system` namespace

### 3. ALB Security Group

- **Corrected:** Changed from `salon-app-ec2-sg` to `salon-app-elb-sg`
- **Traffic Flow:** Internet → ALB (elb-sg) → NodePort → EC2 (ec2-sg)

### 4. Removed External Secrets Complexity

- External Secrets configuration removed from cluster
- Simplified to direct secret reference
- Reduces failure points

---

## Lessons Learned

### 1. Test Automation End-to-End

The External Secrets setup was committed with PLACEHOLDER values. The CronJob appeared to be set up but was never actually tested:

> **Lesson:** Always test automation pipelines end-to-end before considering them "done."

### 2. Don't Mix Manual and Automated Approaches

Someone manually created the ECR secret as a workaround, which:
- Masked the underlying automation failure
- Created a ticking time bomb (12-hour expiration)
- Made it unclear what was automated vs manual

> **Lesson:** Document workarounds clearly and track them as technical debt.

### 3. Security Groups Matter

The ALB security group misconfiguration caused a silent failure:
- ALB health checks passed (checking EC2, not the app)
- But actual traffic was blocked

> **Lesson:** Verify security group configurations match the documented architecture.

### 4. Infrastructure Should Be in Code

The ALB was created manually, leading to:
- No record of configuration decisions
- Easy to make mistakes (wrong security group)
- Difficult to reproduce or audit

> **Lesson:** All infrastructure should be in Terraform/IaC with proper review processes.

### 5. Monitor Your Automation

The CronJob was failing silently for an unknown period:
- No alerts on job failure
- No monitoring of ECR token validity
- Problem only discovered when services broke

> **Lesson:** Set up monitoring and alerting for critical automation jobs.

---

## Recommendations

### Immediate (Already Done)
- [x] Fix CronJob with proper credentials
- [x] Fix ALB security group
- [x] Create dedicated IAM user for ECR
- [x] Remove External Secrets complexity

### Short-term (Next Sprint)
- [ ] Add ALB configuration to Terraform
- [ ] Set up CronJob failure alerts (CloudWatch/Prometheus)
- [ ] Add ECR credential expiration monitoring
- [ ] Document the correct security group architecture

### Medium-term (Next Quarter)
- [ ] Evaluate migration to EKS for native IRSA support
- [ ] Implement IAM access key rotation automation
- [ ] Add runbook for common failure scenarios
- [ ] Implement infrastructure drift detection

### Long-term
- [ ] Consider migrating to GitHub Container Registry (simpler auth)
- [ ] Evaluate if External Secrets is needed for other use cases
- [ ] Implement chaos engineering to test failure scenarios

---

## Appendix A: Commands Reference

### Check ECR Credential Status
```bash
# Check if secret exists
kubectl get secret ecr-registry -n staging

# Check token expiration (decode and examine)
kubectl get secret ecr-registry -n staging -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths[].auth' | base64 -d | cut -d: -f2 | head -c 50
```

### Manual ECR Credential Refresh
```bash
# Generate token
TOKEN=$(aws ecr get-login-password --region us-east-1)

# Update secret
kubectl create secret docker-registry ecr-registry \
    --docker-server=024955634588.dkr.ecr.us-east-1.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$TOKEN \
    -n staging \
    --dry-run=client -o yaml | kubectl apply -f -
```

### Trigger CronJob Manually
```bash
kubectl create job --from=cronjob/ecr-cred-helper manual-refresh -n kube-system
kubectl logs job/manual-refresh -n kube-system -f
```

### Check ALB Security Groups
```bash
aws elbv2 describe-load-balancers --names salon-istio-alb \
    --query 'LoadBalancers[0].SecurityGroups'
```

---

## Appendix B: Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SALON BOOKING INFRASTRUCTURE                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────────┐   │
│  │   Route53   │────►│     ALB     │────►│    Istio Ingress Gateway   │   │
│  │             │     │  (elb-sg)   │     │      (NodePort 31252)      │   │
│  └─────────────┘     └─────────────┘     └─────────────────────────────┘   │
│        │                                              │                     │
│        │                                              ▼                     │
│        │                              ┌─────────────────────────────────┐   │
│        │                              │     Kubernetes Services         │   │
│        │                              │  ┌──────────┐ ┌──────────┐     │   │
│        │                              │  │ Frontend │ │ User Svc │     │   │
│        │                              │  └──────────┘ └──────────┘     │   │
│        │                              │  ┌──────────┐ ┌──────────┐     │   │
│        │                              │  │Appt. Svc │ │Staff Svc │     │   │
│        │                              │  └──────────┘ └──────────┘     │   │
│        │                              │  ┌──────────┐ ┌──────────┐     │   │
│        │                              │  │Notif Svc │ │Report Svc│     │   │
│        │                              │  └──────────┘ └──────────┘     │   │
│        │                              └─────────────────────────────────┘   │
│        │                                              │                     │
│        │                                              │ Image Pull          │
│        │                                              ▼                     │
│        │                              ┌─────────────────────────────────┐   │
│        │                              │            AWS ECR              │   │
│        │                              │  024955634588.dkr.ecr.us-east-1 │   │
│        │                              └─────────────────────────────────┘   │
│        │                                              ▲                     │
│        │                                              │ Token               │
│        │                              ┌─────────────────────────────────┐   │
│        │                              │     ECR Credential Helper       │   │
│        │                              │  (CronJob - every 6 hours)      │   │
│        │                              │                                 │   │
│        │                              │  Uses: aws-credentials secret   │   │
│        │                              │  Creates: ecr-registry secret   │   │
│        │                              └─────────────────────────────────┘   │
│        │                                              │                     │
│        │                              ┌─────────────────────────────────┐   │
│        │                              │         IAM User                │   │
│        │                              │      salon-ecr-pull             │   │
│        │                              │  (ECR ReadOnly Access)          │   │
│        │                              └─────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Appendix C: Related Files

| File | Purpose |
|------|---------|
| `staging/ecr-credential-helper/ecr-credential-helper.yaml` | CronJob definition |
| `salon-k8s-infra/terraform/iam.tf` | IAM user definition (TODO: add) |
| `salon-k8s-infra/terraform/alb.tf` | ALB definition (TODO: add) |

---

## Document History

| Date | Author | Changes |
|------|--------|---------|
| 2025-12-15 | Infrastructure Team | Initial incident report |

---

*This document should be reviewed and updated after any related infrastructure changes.*
