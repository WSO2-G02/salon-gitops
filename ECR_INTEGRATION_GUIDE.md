# ECR Integration with ArgoCD - Setup Guide

This guide explains how ECR (Elastic Container Registry) is automated and integrated with your Kubernetes cluster and ArgoCD.

## Architecture Overview

```
AWS ECR (eu-north-1)
    ↓
EC2 Instances (IAM Role with ECR permissions)
    ↓
Kubernetes Cluster
    ↓
CronJob (refreshes ECR token every 6 hours)
    ↓
Kubernetes Secret (ecr-registry-secret)
    ↓
ArgoCD → Pulls manifests → Deploys with ECR images
```

## Components

### 1. **Terraform IAM Configuration** (`terraform/iam_ecr_policy.tf`)
   - Creates IAM policy with ECR pull permissions
   - Attaches policy to existing EC2 IAM role (`salon-app-ssm-ec2-role`)
   - Allows all nodes to authenticate with ECR

### 2. **ECR Credential Helper CronJob** (`staging/ecr-credential-helper.yaml`)
   - Runs every 6 hours to refresh ECR login token
   - Creates `ecr-registry-secret` in both `staging` and `argocd` namespaces
   - Uses AWS CLI to get fresh ECR credentials

### 3. **Updated Deployments** (all services in `staging/*/deployment.yaml`)
   - Added `imagePullSecrets` to reference `ecr-registry-secret`
   - Ensures pods can pull images from ECR

## Setup Instructions

### Step 1: Apply Terraform Changes

```bash
cd /home/ritzy/wso2\ project/salon-k8s-infra/terraform

# Initialize and apply
terraform init
terraform plan
terraform apply
```

This will:
- Create ECR pull policy
- Attach it to your EC2 instance role

### Step 2: Deploy ECR Credential Helper

```bash
cd /home/ritzy/wso2\ project/salon-gitops

# Create staging namespace if not exists
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -

# Deploy the CronJob manually first
kubectl apply -f staging/ecr-credential-helper.yaml

# Trigger the job manually to create the secret immediately
kubectl create job --from=cronjob/ecr-cred-helper ecr-cred-initial -n kube-system
```

### Step 3: Verify ECR Secret Creation

```bash
# Check if the job succeeded
kubectl get jobs -n kube-system

# Verify secret exists in staging namespace
kubectl get secret ecr-registry-secret -n staging

# Verify secret exists in argocd namespace
kubectl get secret ecr-registry-secret -n argocd
```

### Step 4: Deploy ArgoCD Applications

```bash
# Apply all ArgoCD applications
kubectl apply -f argocd/
```

ArgoCD will now:
1. Pull manifests from your GitHub repo
2. Deploy services with ECR images
3. Use the `ecr-registry-secret` to authenticate

## How It Works

### Token Refresh Mechanism
- ECR tokens expire after 12 hours
- CronJob runs every 6 hours (safe buffer)
- Automatically recreates the secret before expiration
- No manual intervention required

### Multi-Namespace Support
The CronJob creates secrets in:
- **staging**: For application pods
- **argocd**: For ArgoCD to pull images during sync

### IAM Role Benefits
- No hardcoded AWS credentials
- Leverages EC2 instance metadata
- Secure and follows AWS best practices
- Automatic credential rotation by AWS

## Verification

### 1. Check CronJob Schedule
```bash
kubectl get cronjob -n kube-system
```

### 2. View Recent Job Runs
```bash
kubectl get jobs -n kube-system -l job-name=ecr-cred-helper
```

### 3. Check Secret Details
```bash
kubectl get secret ecr-registry-secret -n staging -o yaml
```

### 4. Test Pod Image Pull
```bash
# Check if pods are running successfully
kubectl get pods -n staging
```

### 5. Verify ArgoCD Sync
```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check sync status
kubectl describe application user-service -n argocd
```

## Troubleshooting

### Issue: Pods in ImagePullBackOff state

**Cause**: Secret not created or expired

**Solution**:
```bash
# Manually trigger credential refresh
kubectl create job --from=cronjob/ecr-cred-helper ecr-cred-manual -n kube-system

# Check job logs
kubectl logs -n kube-system -l job-name=ecr-cred-manual
```

### Issue: CronJob fails with authentication error

**Cause**: EC2 IAM role doesn't have ECR permissions

**Solution**:
```bash
# Verify IAM role has policy attached
aws iam list-attached-role-policies --role-name salon-app-ssm-ec2-role

# Verify from within a pod (uses instance metadata)
kubectl run test-aws --image=amazon/aws-cli --rm -it -- aws ecr describe-repositories --region eu-north-1
```

### Issue: ArgoCD can't sync applications

**Cause**: Secret missing in argocd namespace

**Solution**:
```bash
# Verify secret exists
kubectl get secret ecr-registry-secret -n argocd

# If missing, run the job
kubectl create job --from=cronjob/ecr-cred-helper ecr-cred-fix -n kube-system
```

## Manual Secret Creation (Emergency)

If automation fails, manually create the secret:

```bash
# Get ECR token
TOKEN=$(aws ecr get-login-password --region eu-north-1)

# Create secret in staging
kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=024955634588.dkr.ecr.eu-north-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${TOKEN}" \
  --namespace=staging

# Create secret in argocd
kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=024955634588.dkr.ecr.eu-north-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="${TOKEN}" \
  --namespace=argocd
```

## Monitoring

### Set up alerts for CronJob failures

```bash
# Check CronJob status
kubectl get cronjob ecr-cred-helper -n kube-system -o jsonpath='{.status.lastScheduleTime}'

# View failed job logs
kubectl logs -n kube-system -l job-name --selector=job-name=ecr-cred-helper --tail=50
```

## Security Best Practices

✅ **Implemented:**
- IAM role-based authentication (no hardcoded credentials)
- Secrets scoped to specific namespaces
- Automatic token rotation every 6 hours
- ECR image scanning on push enabled

🔒 **Additional Recommendations:**
- Enable AWS CloudTrail for ECR access logging
- Use ECR lifecycle policies to clean old images
- Implement image vulnerability scanning in CI/CD
- Restrict ECR repositories to specific services

## Next Steps

1. **Monitor the first few credential refreshes** to ensure automation works
2. **Set up CloudWatch alarms** for CronJob failures
3. **Test pod deployments** after secret refresh
4. **Document any service-specific ECR configurations**

## Related Files

- Terraform: [terraform/iam_ecr_policy.tf](../salon-k8s-infra/terraform/iam_ecr_policy.tf)
- CronJob: [staging/ecr-credential-helper.yaml](staging/ecr-credential-helper.yaml)
- ArgoCD App: [argocd/ecr_credential_helper.yaml](argocd/ecr_credential_helper.yaml)
- All Deployments: [staging/*/deployment.yaml](staging/)
