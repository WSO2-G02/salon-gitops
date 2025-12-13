#!/bin/bash

# ArgoCD Bootstrap Script
# This script installs ArgoCD and applies the GitOps manifests from the 'argocd/' directory.

set -e

echo "=========================================="
echo "      ArgoCD GitOps Bootstrap"
echo "=========================================="
echo ""

# 1. Check Prerequisites
echo "🔍 Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl could not be found. Please install it or set up your kubeconfig."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: kubectl cannot connect to the cluster. Check your kubeconfig."
    exit 1
fi
echo "✅ kubectl is ready."
echo ""

# 2. Install ArgoCD
echo "🚀 Step 1: Installing ArgoCD..."

# Create namespace if it doesn't exist
if ! kubectl get ns argocd &> /dev/null; then
    echo "   Creating 'argocd' namespace..."
    kubectl create namespace argocd
else
    echo "   'argocd' namespace already exists."
fi

# Create Staging namespace
if ! kubectl get ns staging &> /dev/null; then
    echo "   Creating 'staging' namespace..."
    kubectl create namespace staging
fi

# Create Production namespace
if ! kubectl get ns production &> /dev/null; then
    echo "   Creating 'production' namespace..."
    kubectl create namespace production
fi

# Apply ArgoCD Manifests (Stable)
echo "   Applying ArgoCD stable manifest..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Waiting for ArgoCD server components to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || echo "⚠️  Timeout waiting, but proceeding..."

# 3. Apply GitOps Applications
echo ""
echo "📂 Step 2: Applying GitOps Applications from 'argocd/'..."

if [ -d "argocd" ]; then
    # Cleanup accidentally created apps in default namespace
    kubectl delete application --all -n default --ignore-not-found &> /dev/null || true
    
    # Apply to argocd namespace
    kubectl apply -n argocd -f argocd/
    echo "✅ Applied all manifests in 'argocd/'."
else
    echo "❌ Error: 'argocd/' directory not found in current location."
    echo "   Make sure you run this script from the root of 'salon-gitops'."
    exit 1
fi

# Apply Istio Configurations
echo ""
echo "🕸️  Step 3: Applying Istio Configurations..."
if [ -d "istio" ]; then
    kubectl apply -f istio/
    echo "✅ Applied Istio Gateway and VirtualServices."
fi

# 4. Get Info
echo ""
echo "🎉 GitOps Bootstrap Complete!"
echo ""

# Get Password
echo "🔑 Initial Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""

# Get UI Access Info
echo "🌐 Accessing ArgoCD UI:"
echo "   Since this is likely a private cluster, run this locally to access the UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "   Then open: https://localhost:8080"
echo "   Username: admin"
echo ""
