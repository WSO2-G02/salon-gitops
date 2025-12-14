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

# 2. Install Istio
echo "🚀 Step 1: Installing Istio..."

# Download Istio if not present
if [ ! -d "istio-1.24.1" ]; then
    echo "   Downloading Istio 1.24.1..."
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.24.1 TARGET_ARCH=x86_64 sh -
else
    echo "   Istio already downloaded."
fi

export PATH=$PWD/istio-1.24.1/bin:$PATH

# Install Istio with demo profile
echo "   Installing Istio (Profile: demo)..."
istioctl install --set profile=demo -y

echo "⏳ Waiting for Istio to be ready..."
kubectl -n istio-system wait --for=condition=available deployment --all --timeout=300s

# 3. Install ArgoCD
echo ""
echo "🚀 Step 2: Installing ArgoCD..."

# Create namespace if it doesn't exist
if ! kubectl get ns argocd &> /dev/null; then
    echo "   Creating 'argocd' namespace..."
    kubectl create namespace argocd
else
    echo "   'argocd' namespace already exists."
fi

# Create Staging namespace and label for Istio
if ! kubectl get ns staging &> /dev/null; then
    echo "   Creating 'staging' namespace..."
    kubectl create namespace staging
fi
echo "   Labeling 'staging' for Istio injection..."
kubectl label namespace staging istio-injection=enabled --overwrite

# Create Production namespace and label for Istio
if ! kubectl get ns production &> /dev/null; then
    echo "   Creating 'production' namespace..."
    kubectl create namespace production
fi
echo "   Labeling 'production' for Istio injection..."
kubectl label namespace production istio-injection=enabled --overwrite

# Apply ArgoCD Manifests (Stable)
echo "   Applying ArgoCD stable manifest..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Waiting for ArgoCD server components to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || echo "⚠️  Timeout waiting, but proceeding..."

# Patch ArgoCD Server to run in insecure mode (for Istio HTTP termination)
echo "   Patching ArgoCD server to run in insecure mode..."
kubectl patch deployment argocd-server -n argocd --type json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'


# 4. Apply GitOps Applications
echo ""
echo "📂 Step 3: Applying GitOps Applications from 'argocd/'..."

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
echo "🕸️  Step 4: Applying Istio Configurations..."

# Since we just installed Istio, CRDs should be ready, but good to double check
if kubectl get crd virtualservices.networking.istio.io gateways.networking.istio.io &> /dev/null; then
    if [ -d "istio" ]; then
        kubectl apply -f istio/
        echo "✅ Applied Istio Gateway and VirtualServices."
    fi
else
    echo "⚠️  Istio CRDs missing! Installation might have failed."
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
