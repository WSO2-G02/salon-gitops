#!/bin/bash

# Setup Local Access Script
# This script fetches the kubeconfig from the control plane and configures it for local use.

set -e

CONTROL_PLANE_IP="13.221.238.217"
SSH_KEY="~/.ssh/salon-key.pem"
LOCAL_KUBE_DIR="$HOME/.kube"
LOCAL_KUBE_CONFIG="$LOCAL_KUBE_DIR/config"

echo "=========================================="
echo "      Setup Local Cluster Access"
echo "=========================================="
echo ""

# 1. Ensure local .kube directory exists
echo "📂 Step 1: Preparing local directory..."
mkdir -p "$LOCAL_KUBE_DIR"

# 2. Fetch kubeconfig
echo "⬇️  Step 2: Fetching kubeconfig from $CONTROL_PLANE_IP..."
scp -o StrictHostKeyChecking=no -i $SSH_KEY ubuntu@$CONTROL_PLANE_IP:~/.kube/config "$LOCAL_KUBE_CONFIG"

# 3. Update Server IP
echo "🔧 Step 3: Updating server IP in kubeconfig..."
# Replace localhost/127.0.0.1 with the public IP
sed -i "s|server: https://127.0.0.1:6443|server: https://$CONTROL_PLANE_IP:6443|g" "$LOCAL_KUBE_CONFIG"
sed -i "s|server: https://localhost:6443|server: https://$CONTROL_PLANE_IP:6443|g" "$LOCAL_KUBE_CONFIG"

echo "✅ Kubeconfig updated."

# 4. Verify Access
echo ""
echo "🔍 Step 4: Verifying connectivity..."
if kubectl get nodes; then
    echo ""
    echo "🎉 Success! You can now use 'kubectl' from your local terminal."
else
    echo ""
    echo "❌ Error: Could not connect to the cluster. Check security groups (port 6443) or VPN."
fi
echo ""
