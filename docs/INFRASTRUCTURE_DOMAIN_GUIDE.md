# Aurora Glam Infrastructure & Domain Setup Guide

> Complete guide for team members on how the infrastructure works and how to add new services/domains.

---

## Table of Contents

1. [Current Domain Setup](#current-domain-setup)
2. [How to Add a New Domain/Subdomain](#how-to-add-a-new-domainsubdomain)
3. [Infrastructure Overview (salon-k8s-infra)](#infrastructure-overview-salon-k8s-infra)
4. [How Everything Integrates](#how-everything-integrates)
5. [Grafana Status](#grafana-status)

---

## Current Domain Setup

### Active Domains

| Domain | Purpose | Namespace | Status |
|--------|---------|-----------|--------|
| `aurora-glam.com` | Production site | production | ✅ Active |
| `staging.aurora-glam.com` | Staging/QA testing | staging | ✅ Active |
| `argocd.aurora-glam.com` | ArgoCD Dashboard | argocd | ✅ Active |
| `grafana.aurora-glam.com` | Monitoring Dashboard | monitoring | ⚠️ Gateway configured, needs VirtualService |

### DNS Configuration

Your DNS (likely Route53 or external provider) should have:
```
*.aurora-glam.com  →  A record  →  [Load Balancer IP / Istio Ingress IP]
```

This wildcard allows any subdomain to reach your cluster.

---

## How to Add a New Domain/Subdomain

### Example: Adding `api.aurora-glam.com`

#### Step 1: Add host to Gateway

Edit: `salon-gitops/istio/gateway.yaml`

```yaml
spec:
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "aurora-glam.com"
    - "staging.aurora-glam.com"
    - "argocd.aurora-glam.com"
    - "grafana.aurora-glam.com"
    - "api.aurora-glam.com"          # ← ADD THIS
```

#### Step 2: Create VirtualService

Create: `salon-gitops/istio/api-vs.yaml` (or in your namespace folder)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-vs
  namespace: production  # or your target namespace
spec:
  hosts:
  - "api.aurora-glam.com"
  gateways:
  - istio-system/salon-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: your-service-name    # K8s service name
        port:
          number: 80               # Service port
```

#### Step 3: Commit and Push

```bash
cd salon-gitops
git add -A
git commit -m "feat: add api.aurora-glam.com domain routing"
git push
```

#### Step 4: ArgoCD Syncs Automatically

ArgoCD will detect changes and apply them within 3 minutes.

---

## Infrastructure Overview (salon-k8s-infra)

### Folder Structure

```
salon-k8s-infra/
├── .github/
│   └── workflows/
│       └── infra.yml          # GitHub Actions workflow for Terraform
├── terraform/                  # All AWS infrastructure as code
│   ├── providers.tf           # AWS provider configuration
│   ├── backend.tf             # Terraform state storage (S3)
│   ├── variables.tf           # All configurable variables
│   ├── vpc.tf                 # Virtual Private Cloud
│   ├── subnets.tf             # Public and private subnets
│   ├── internet_gateway.tf    # Internet access for public subnets
│   ├── route_table.tf         # Routing rules
│   ├── route_table_associations.tf
│   ├── sg.tf                  # Security groups (firewall rules)
│   ├── iam.tf                 # IAM roles and policies
│   ├── ec2.tf                 # EC2 instances and Auto Scaling
│   ├── ecr.tf                 # Container registries for each service
│   ├── runner.tf              # GitHub Actions self-hosted runner
│   ├── key_pair.tf            # SSH key for EC2 access
│   ├── outputs.tf             # Terraform outputs
│   ├── user_data.sh           # Bootstrap script for EC2 nodes
│   └── runner_user_data.sh.tpl
├── kubespray/                  # Kubernetes cluster setup (empty - config generated)
├── deploy-k8s.sh              # Helper script
└── README.md
```

---

### Terraform Files Explained

#### `providers.tf` - AWS Provider Setup
```hcl
terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
provider "aws" {
  region = var.region  # ap-south-1
}
```
**Purpose:** Configures Terraform to use AWS in ap-south-1 region.

---

#### `backend.tf` - State Storage
```hcl
terraform {
  backend "s3" {
    bucket       = "salon-terraform-state10249343"
    key          = "global/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
```
**Purpose:** Stores Terraform state in S3 for team collaboration and prevents conflicts.

---

#### `variables.tf` - Configuration Variables
```hcl
variable "region"           { default = "ap-south-1" }
variable "project_name"     { default = "salon-app" }
variable "vpc_cidr"         { default = "10.0.0.0/16" }
variable "public_subnets"   { default = ["10.0.1.0/24", "10.0.2.0/24"] }
variable "private_subnets"  { default = ["10.0.10.0/24", "10.0.11.0/24"] }
variable "instance_type"    { default = "t3.large" }
variable "min_size"         { default = 3 }
variable "max_size"         { default = 6 }
variable "desired_capacity" { default = 4 }

variable "services" {
  default = [
    "user_service", "appointment_service", "service_management",
    "staff_management", "notification_service", "reports_analytics", "frontend"
  ]
}
```
**Purpose:** Central place to configure all infrastructure settings.

---

#### `vpc.tf` - Virtual Private Cloud
```hcl
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr  # 10.0.0.0/16
  tags = { Name = "salon-app-vpc" }
}
```
**Purpose:** Creates an isolated network for all your resources.

---

#### `subnets.tf` - Network Segmentation
```hcl
# Public subnets - can reach internet
resource "aws_subnet" "public" {
  for_each = var.public_subnets
  cidr_block = each.value
  map_public_ip_on_launch = true  # Auto-assign public IPs
}

# Private subnets - internal only
resource "aws_subnet" "private" {
  for_each = var.private_subnets
  cidr_block = each.value
}
```
**Purpose:** 
- **Public subnets (10.0.1.0/24, 10.0.2.0/24):** K8s nodes, accessible from internet
- **Private subnets (10.0.10.0/24, 10.0.11.0/24):** Future use for databases, internal services

---

#### `internet_gateway.tf` - Internet Access
```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}
```
**Purpose:** Allows resources in public subnets to reach the internet.

---

#### `route_table.tf` - Routing Rules
```hcl
resource "aws_route_table" "public" {
  route {
    cidr_block = "0.0.0.0/0"         # All internet traffic
    gateway_id = aws_internet_gateway.igw.id  # Goes through IGW
  }
}
```
**Purpose:** Directs internet-bound traffic through the Internet Gateway.

---

#### `sg.tf` - Security Groups (Firewall)
```hcl
resource "aws_security_group" "ec2_sg" {
  # SSH from GitHub Runner
  ingress { from_port = 22, to_port = 22, protocol = "tcp" }
  
  # Kubernetes API
  ingress { from_port = 6443, to_port = 6443, protocol = "tcp" }
  
  # ETCD cluster communication
  ingress { from_port = 2379, to_port = 2380, protocol = "tcp" }
  
  # Kubelet, scheduler, controller
  ingress { from_port = 10250, to_port = 10252, protocol = "tcp" }
  
  # Microservices ports
  ingress { from_port = 8001, to_port = 8006, protocol = "tcp" }
  
  # NodePort services
  ingress { from_port = 30000, to_port = 32767, protocol = "tcp" }
  
  # HTTP/HTTPS
  ingress { from_port = 80, to_port = 80, protocol = "tcp" }
  ingress { from_port = 443, to_port = 443, protocol = "tcp" }
}
```
**Purpose:** Controls what traffic can reach your EC2 instances.

---

#### `iam.tf` - AWS Permissions
```hcl
# Role for EC2 instances
resource "aws_iam_role" "ssm_ec2_role" {
  # Allows EC2 to assume this role
}

# Permissions attached:
# 1. AmazonSSMManagedInstanceCore - Remote management via AWS console
# 2. ECR Pull Policy - Pull container images from ECR
# 3. Cluster Autoscaler Policy - Scale nodes up/down
```
**Purpose:** Gives EC2 instances permissions to pull images and auto-scale.

---

#### `ecr.tf` - Container Registries
```hcl
resource "aws_ecr_repository" "repos" {
  for_each = toset(var.services)  # Creates one for each service
  name = each.key
  image_scanning_configuration {
    scan_on_push = true  # Security scanning
  }
}

resource "aws_ecr_lifecycle_policy" "cleanup_policy" {
  # Keep only last 10 images per service
  # Delete scan images after 1 day
}
```
**Purpose:** Creates Docker registries:
- `024955634588.dkr.ecr.us-east-1.amazonaws.com/frontend`
- `024955634588.dkr.ecr.us-east-1.amazonaws.com/user_service`
- `024955634588.dkr.ecr.us-east-1.amazonaws.com/appointment_service`
- etc.

---

#### `ec2.tf` - Kubernetes Nodes
```hcl
# Launch template - defines what each node looks like
resource "aws_launch_template" "app_lt" {
  image_id      = var.ami_id          # Ubuntu AMI
  instance_type = var.instance_type   # t3.large
  user_data     = filebase64("user_data.sh")  # Bootstrap script
}

# Auto Scaling Group - manages the fleet
resource "aws_autoscaling_group" "app_asg" {
  desired_capacity = 4   # Start with 4 nodes
  min_size         = 3   # Never go below 3
  max_size         = 6   # Never go above 6
  launch_template { id = aws_launch_template.app_lt.id }
}
```
**Purpose:** Creates and manages Kubernetes worker nodes.

---

#### `runner.tf` - GitHub Actions Runner
```hcl
resource "aws_instance" "github_runner" {
  instance_type = "t3.medium"
  user_data = templatefile("runner_user_data.sh.tpl", {
    github_repo   = var.github_repo
    runner_token  = var.runner_token
  })
}
```
**Purpose:** Self-hosted runner that can SSH into cluster nodes to run Kubespray.

---

#### `user_data.sh` - Node Bootstrap Script
```bash
#!/bin/bash
# 1. Install packages (python3, docker, etc.)
# 2. Enable Docker
# 3. Disable swap (required for Kubernetes)
# 4. Load kernel modules (overlay, br_netfilter)
# 5. Set sysctl params for networking
# 6. Set hostname with instance ID
```
**Purpose:** Prepares each EC2 instance to become a Kubernetes node.

---

#### `outputs.tf` - Exported Values
```hcl
output "instance_ids" { value = data.aws_instances.k8s_nodes.ids }
output "vpc_id" { value = aws_vpc.main.id }
output "ecr_repository_arns" { value = [for r in aws_ecr_repository.repos : r.arn] }
```
**Purpose:** Exports important IDs for use by other systems.

---

## How Everything Integrates

### Complete Infrastructure Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            INFRASTRUCTURE LAYER                                  │
│                           (salon-k8s-infra repo)                                │
│                                                                                  │
│  Terraform creates:                                                              │
│  ┌─────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│  │   VPC   │  │   Subnets   │  │  Security   │  │    IAM      │                │
│  │10.0.0.0 │  │  Public x2  │  │   Groups    │  │   Roles     │                │
│  │  /16    │  │  Private x2 │  │  (Firewall) │  │(ECR access) │                │
│  └─────────┘  └─────────────┘  └─────────────┘  └─────────────┘                │
│                                                                                  │
│  ┌───────────────────────────┐  ┌────────────────────────────────┐             │
│  │    EC2 Auto Scaling       │  │        ECR Repositories        │             │
│  │    Group (3-6 nodes)      │  │   ┌──────────┐ ┌──────────┐   │             │
│  │  ┌─────┐ ┌─────┐ ┌─────┐  │  │   │ frontend │ │user_svc  │   │             │
│  │  │Node1│ │Node2│ │Node3│  │  │   ├──────────┤ ├──────────┤   │             │
│  │  └─────┘ └─────┘ └─────┘  │  │   │appt_svc  │ │staff_svc │   │             │
│  └───────────────────────────┘  │   └──────────┘ └──────────┘   │             │
│                                  └────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           KUBERNETES LAYER                                       │
│                     (Installed via Kubespray on EC2 nodes)                      │
│                                                                                  │
│  Namespaces:                                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   staging   │  │ production  │  │   argocd    │  │istio-system │            │
│  │  (testing)  │  │   (live)    │  │ (GitOps UI) │  │  (gateway)  │            │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                                  │
│  Istio Service Mesh:                                                             │
│  ┌──────────────────────────────────────────────────────────────────┐          │
│  │  Gateway (salon-gateway) - accepts traffic for all domains       │          │
│  │  ┌────────────────┐  ┌─────────────────────┐  ┌───────────────┐ │          │
│  │  │aurora-glam.com │  │staging.aurora-glam. │  │argocd.aurora- │ │          │
│  │  │       ↓        │  │        ↓            │  │     ↓         │ │          │
│  │  │  VirtualSvc    │  │   VirtualService    │  │ VirtualSvc    │ │          │
│  │  │       ↓        │  │        ↓            │  │     ↓         │ │          │
│  │  │  production/   │  │    staging/         │  │   argocd/     │ │          │
│  │  └────────────────┘  └─────────────────────┘  └───────────────┘ │          │
│  └──────────────────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              GITOPS LAYER                                        │
│                          (salon-gitops repo)                                    │
│                                                                                  │
│  ArgoCD watches this repo and deploys to cluster:                               │
│                                                                                  │
│  salon-gitops/                                                                   │
│  ├── staging/              → Deploys to staging namespace                       │
│  │   ├── frontend/                                                               │
│  │   ├── user_service/                                                           │
│  │   └── ...                                                                     │
│  ├── production/           → Deploys to production namespace                    │
│  │   ├── frontend/                                                               │
│  │   └── ...                                                                     │
│  ├── istio/                → Network routing rules                              │
│  │   ├── gateway.yaml                                                            │
│  │   └── argocd-vs.yaml                                                          │
│  └── argocd/               → ArgoCD application definitions                     │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           APPLICATION LAYER                                      │
│            (salon-booking-frontend-dev & salon-booking-backend-dev)             │
│                                                                                  │
│  Push to main → CI/CD builds → Push to ECR → Update GitOps → ArgoCD deploys    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Grafana Status

### Current State

Grafana domain is **configured in the Gateway** but needs a VirtualService to actually route traffic.

### To Enable Grafana

1. **Install Grafana in cluster** (if not installed):
```bash
kubectl create namespace monitoring
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana -n monitoring
```

2. **Create VirtualService** - `salon-gitops/istio/grafana-vs.yaml`:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana-vs
  namespace: monitoring
spec:
  hosts:
  - "grafana.aurora-glam.com"
  gateways:
  - istio-system/salon-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: grafana
        port:
          number: 80
```

3. **Commit and push to salon-gitops**

4. **Access at:** https://grafana.aurora-glam.com

---

## Quick Reference

### URLs
- **Production:** https://aurora-glam.com
- **Staging:** https://staging.aurora-glam.com
- **ArgoCD:** https://argocd.aurora-glam.com
- **Grafana:** https://grafana.aurora-glam.com (needs VirtualService)

### Deploy to Production
```
https://github.com/WSO2-G02/salon-gitops/actions/workflows/deploy-production.yml
```

### Key Files
| File | Purpose |
|------|---------|
| `salon-gitops/istio/gateway.yaml` | Add new domains here |
| `salon-gitops/staging/*/deployment.yaml` | Staging deployments |
| `salon-gitops/production/*/deployment.yaml` | Production deployments |
| `salon-k8s-infra/terraform/variables.tf` | Infrastructure settings |
| `salon-k8s-infra/terraform/ecr.tf` | Container registries |

### AWS Resources Created by Terraform
- 1 VPC (10.0.0.0/16)
- 2 Public subnets + 2 Private subnets
- 1 Internet Gateway
- 4 Security Groups
- 3-6 EC2 instances (Auto Scaling)
- 7 ECR repositories (one per service)
- 1 GitHub Actions runner instance
- IAM roles for ECR access and cluster autoscaling
