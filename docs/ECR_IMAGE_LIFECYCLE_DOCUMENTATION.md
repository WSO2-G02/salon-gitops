# ECR Image Lifecycle & CI/CD Pipeline Documentation

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CI/CD PIPELINE FLOW                                │
└─────────────────────────────────────────────────────────────────────────────────┘

  Developer Push                Build & Test              Push to ECR              Update GitOps
  ─────────────                 ───────────               ───────────              ─────────────
       │                             │                         │                         │
       ▼                             ▼                         ▼                         ▼
  ┌─────────┐    trigger    ┌─────────────────┐    push   ┌─────────────┐    update  ┌─────────────┐
  │ GitHub  │──────────────▶│ GitHub Actions  │─────────▶│    ECR      │───────────▶│   GitOps    │
  │  Repo   │               │   CI/CD         │           │ Repository  │            │    Repo     │
  └─────────┘               └─────────────────┘           └─────────────┘            └─────────────┘
                                    │                           │                          │
                                    │ lint, test, scan          │ store images             │ sync
                                    ▼                           ▼                          ▼
                            ┌─────────────────┐         ┌─────────────────┐        ┌─────────────────┐
                            │ Trivy Security  │         │ Lifecycle Policy│        │     ArgoCD      │
                            │     Scan        │         │  (Auto-cleanup) │        │  (Auto-deploy)  │
                            └─────────────────┘         └─────────────────┘        └─────────────────┘
                                                                                           │
                                                                                           ▼
                                                                                   ┌─────────────────┐
                                                                                   │   Kubernetes    │
                                                                                   │     Cluster     │
                                                                                   └─────────────────┘
```

---

## 🔄 Image Upload/Download Flow

### Upload Flow (Push to ECR)

```
1. Developer commits code
          │
          ▼
2. GitHub Actions triggered
          │
          ▼
3. Build Stage:
   ├── Install dependencies
   ├── Run linting (ESLint/Black)
   ├── Run tests
   └── Build Docker image
          │
          ▼
4. Security Scan:
   ├── Trivy vulnerability scan
   └── Fail build if HIGH/CRITICAL vulns
          │
          ▼
5. Push to ECR:
   ├── Authenticate to AWS ECR
   ├── Tag image: {service}:{git-sha-short}-{timestamp}
   └── Push image to ECR repository
          │
          ▼
6. Update GitOps:
   ├── Clone GitOps repository
   ├── Update deployment.yaml with new image tag
   └── Commit and push to GitOps repo
```

### Download Flow (Pull from ECR)

```
1. ArgoCD detects GitOps change
          │
          ▼
2. ArgoCD syncs to Kubernetes
          │
          ▼
3. Kubernetes pulls image:
   ├── ECR Credential Helper CronJob refreshes tokens
   ├── ImagePullSecrets used for authentication
   └── Kubelet pulls image from ECR
          │
          ▼
4. Pod starts with new image
```

---

## 🏷️ Image Tagging Strategy

### Current Implementation
```
Format: {commit-sha-short}-{YYYYMMDDHHMMSS}
Example: d2ba07eb-20251215013040
```

### Tag Components:
| Component | Description | Example |
|-----------|-------------|---------|
| `commit-sha-short` | First 8 chars of git commit SHA | `d2ba07eb` |
| `timestamp` | Build timestamp (UTC) | `20251215013040` |

### Benefits:
- ✅ Unique per build
- ✅ Traceable to git commit
- ✅ Chronologically sortable
- ✅ Immutable deployments

---

## 🗑️ ECR Lifecycle Policy (Auto-Cleanup)

### Current Configuration (Terraform)

```hcl
resource "aws_ecr_lifecycle_policy" "cleanup_policy" {
  for_each = toset(var.services)
  repository = aws_ecr_repository.repos[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire temporary scan images after 1 day"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["scan"]
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only last 10 production images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
```

### What This Does:

| Rule | Priority | Description | When Applied |
|------|----------|-------------|--------------|
| **Scan Cleanup** | 1 | Delete images tagged with `scan*` after 1 day | For temporary vulnerability scan images |
| **Image Retention** | 2 | Keep only the most recent 10 images | Applied to all images after Rule 1 |

### Storage Impact:
```
Scenario: 5 builds/day × 7 days = 35 images
With policy: Max 10 images per repository
Storage saved: ~71% reduction
```

---

## 🛡️ Security Features

### Image Scanning
- **Trivy** scans during CI build
- **ECR Basic Scanning** on push (`scan_on_push = true`)
- Builds fail on HIGH/CRITICAL vulnerabilities

### Encryption
- All images encrypted at rest with AES-256
- Uses AWS-managed keys (no additional cost)

### Access Control
- OIDC-based authentication (no long-lived credentials)
- IAM roles with least privilege
- ECR policies restrict access to specific principals

---

## 📈 Industry Best Practices & Improvements

### Current State vs. Best Practices

| Aspect | Current | Best Practice | Recommendation |
|--------|---------|---------------|----------------|
| **Tagging** | `{sha}-{timestamp}` | Semantic versioning | Add `latest`, `staging`, `prod` tags |
| **Retention** | Keep 10 images | Environment-based | Different policies per environment |
| **Scanning** | Basic scanning | Advanced scanning | Enable Inspector Enhanced Scanning |
| **Multi-arch** | Single arch | Multi-arch | Build arm64 + amd64 images |
| **Signing** | Not implemented | Image signing | Add Sigstore/Cosign signing |
| **SBOM** | Not implemented | SBOM generation | Add Syft for SBOM generation |

---

## 🚀 Recommended Improvements

### 1. Enhanced Tagging Strategy

```yaml
# Recommended multi-tag approach
tags:
  - ${SHA_SHORT}                    # Commit reference
  - ${BRANCH}-${SHA_SHORT}          # Branch + commit
  - ${BRANCH}-latest                # Latest for branch
  - v${VERSION}                     # Semantic version (for releases)
  - staging                         # Environment tag
  - prod                            # Production tag
```

**Implementation:**
```yaml
# In GitHub Actions
- name: Push to ECR with multiple tags
  run: |
    IMAGE_BASE=${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.${{ secrets.AWS_REGION }}.amazonaws.com/${{ env.SERVICE_NAME }}
    
    # Tag with commit SHA
    docker tag $IMAGE_BASE:build $IMAGE_BASE:${{ env.SHA_SHORT }}
    
    # Tag with branch-latest
    docker tag $IMAGE_BASE:build $IMAGE_BASE:${{ github.ref_name }}-latest
    
    # Push all tags
    docker push $IMAGE_BASE --all-tags
```

### 2. Environment-Specific Lifecycle Policies

```hcl
# Improved Terraform lifecycle policy
resource "aws_ecr_lifecycle_policy" "enhanced_policy" {
  for_each = toset(var.services)
  repository = aws_ecr_repository.repos[each.key].name

  policy = jsonencode({
    rules = [
      # Rule 1: Remove untagged images after 1 day
      {
        rulePriority = 1
        description  = "Remove untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      
      # Rule 2: Keep last 3 production images indefinitely
      {
        rulePriority = 2
        description  = "Keep production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 3
        }
        action = { type = "expire" }
      },
      
      # Rule 3: Keep last 5 staging images
      {
        rulePriority = 3
        description  = "Keep staging images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["staging-", "main-"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = { type = "expire" }
      },
      
      # Rule 4: Remove feature branch images after 7 days
      {
        rulePriority = 4
        description  = "Expire feature branch images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["feature-", "fix-", "dev-"]
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = 7
        }
        action = { type = "expire" }
      },
      
      # Rule 5: Keep max 20 images total as safety net
      {
        rulePriority = 10
        description  = "Maximum image retention"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}
```

### 3. Image Signing with Cosign

```yaml
# Add to GitHub Actions workflow
- name: Install Cosign
  uses: sigstore/cosign-installer@v3

- name: Sign the container image
  env:
    COSIGN_EXPERIMENTAL: "true"
  run: |
    cosign sign --yes \
      ${{ env.ECR_REGISTRY }}/${{ env.SERVICE_NAME }}:${{ env.IMAGE_TAG }}
```

### 4. SBOM Generation

```yaml
# Add to GitHub Actions workflow
- name: Generate SBOM
  uses: anchore/sbom-action@v0
  with:
    image: ${{ env.ECR_REGISTRY }}/${{ env.SERVICE_NAME }}:${{ env.IMAGE_TAG }}
    artifact-name: sbom-${{ env.SERVICE_NAME }}.spdx.json
    output-file: sbom.spdx.json

- name: Attach SBOM to image
  run: |
    cosign attach sbom --sbom sbom.spdx.json \
      ${{ env.ECR_REGISTRY }}/${{ env.SERVICE_NAME }}:${{ env.IMAGE_TAG }}
```

### 5. Multi-Architecture Builds

```yaml
# Add to GitHub Actions workflow
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3

- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push multi-arch
  uses: docker/build-push-action@v5
  with:
    context: .
    platforms: linux/amd64,linux/arm64
    push: true
    tags: ${{ env.ECR_REGISTRY }}/${{ env.SERVICE_NAME }}:${{ env.IMAGE_TAG }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

### 6. Enhanced ECR Security

```hcl
# Add to Terraform
resource "aws_ecr_repository" "repos" {
  for_each = toset(var.services)
  name     = each.key
  
  # Use IMMUTABLE tags in production
  image_tag_mutability = "IMMUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr_key.arn
  }
}

# Enable Enhanced Scanning with Inspector
resource "aws_inspector2_enabler" "ecr" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["ECR"]
}
```

---

## 📋 Monitoring & Alerting

### CloudWatch Metrics to Monitor

```hcl
# Add CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "ecr_scan_findings" {
  alarm_name          = "ecr-critical-vulnerabilities"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CriticalSeverityCount"
  namespace           = "AWS/Inspector"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Critical vulnerabilities found in ECR images"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```

---

## 🔍 Verification Commands

```bash
# List images in ECR repository
aws ecr describe-images --repository-name frontend --query 'imageDetails[*].[imageTags,imagePushedAt]' --output table

# Check lifecycle policy
aws ecr get-lifecycle-policy --repository-name frontend

# Check image scan results
aws ecr describe-image-scan-findings --repository-name frontend --image-id imageTag=latest

# List all repositories
aws ecr describe-repositories --query 'repositories[*].repositoryName'
```

---

## 📚 References

- [AWS ECR Lifecycle Policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)
- [ECR Image Scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
- [Sigstore Cosign](https://docs.sigstore.dev/cosign/overview/)
- [Docker Multi-platform Builds](https://docs.docker.com/build/building/multi-platform/)
- [SBOM Best Practices](https://www.cisa.gov/sbom)

---

*Last Updated: December 15, 2025*
