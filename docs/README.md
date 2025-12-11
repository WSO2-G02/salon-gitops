# GitOps Documentation

This directory contains technical documentation for the Salon Booking GitOps configuration.

## Contents

| Document | Description |
|----------|-------------|
| [DEPLOYMENT_STRATEGY.md](DEPLOYMENT_STRATEGY.md) | Rolling update strategy, health probes, and automatic recovery |

## Quick Links

### Deployment Strategy
- [Rolling Update Strategy](DEPLOYMENT_STRATEGY.md#rolling-update-strategy)
- [Health Probes](DEPLOYMENT_STRATEGY.md#health-probes)
- [Zero-Downtime Deployment](DEPLOYMENT_STRATEGY.md#zero-downtime-deployment)
- [Automatic Recovery](DEPLOYMENT_STRATEGY.md#automatic-recovery)

## Repository Structure

```
salon-gitops/
├── argocd/                    # ArgoCD Application definitions
├── istio/                     # Istio Gateway configuration
├── staging/                   # Kubernetes manifests per service
│   └── <service>/
│       ├── deployment.yaml    # Pod specs, probes, strategy
│       ├── service.yaml       # ClusterIP service
│       ├── hpa.yaml           # Horizontal Pod Autoscaler
│       ├── virtualservice.yaml # Istio routing
│       └── destinationrule.yaml # Istio traffic policy
└── docs/                      # Documentation
```
