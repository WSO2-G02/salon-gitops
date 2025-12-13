#!/bin/bash

# Istio Installation Script
# This script installs Istio Service Mesh using the demo profile and enables sidecar injection.

set -e

echo "=========================================="
echo "      Istio Service Mesh Installation"
echo "=========================================="
echo ""

# 1. Download Istio
echo "🚀 Step 1: Downloading Istio..."
if [ ! -d "istio-1.24.1" ]; then
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.24.1 TARGET_ARCH=x86_64 sh -
else
    echo "   Istio already downloaded."
fi

export PATH=$PWD/istio-1.24.1/bin:$PATH

# 2. Install Istio
echo ""
echo "📦 Step 2: Installing Istio (Profile: demo)..."
istioctl install --set profile=demo -y

echo "⏳ Waiting for Istio to be ready..."
# Verification (simple check)
kubectl -n istio-system wait --for=condition=available deployment --all --timeout=300s

# 3. Label Namespaces for Injection
echo ""
echo "🏷️  Step 3: Enabling Sidecar Injection..."

# Staging
kubectl label namespace staging istio-injection=enabled --overwrite
echo "   Namespace 'staging' labeled."

# Production
kubectl label namespace production istio-injection=enabled --overwrite
echo "   Namespace 'production' labeled."

# ArgoCD (Optional - usually not injected unless needed for Mesh, skip for now to avoid issues)
# kubectl label namespace argocd istio-injection=enabled --overwrite

echo ""
echo "🎉 Istio Installation Complete!"
echo "   Note: You will need to restart existing pods in staging/production for sidecars to be injected."
echo "   Run: kubectl rollout restart deployment -n staging"
echo "        kubectl rollout restart deployment -n production"
echo ""
