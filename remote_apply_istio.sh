#!/bin/bash
# Remote Apply Istio HostNetwork configuration
# Usage: ./remote_apply_istio.sh

# Paths
KEY_FILE="../salon-k8s-infra/terraform/salon-key.pem"
CP_IP="174.129.176.56"

# Ensure permissions
chmod 600 "$KEY_FILE"

echo "=========================================="
echo "🚀 Copying configuration to Control Plane ($CP_IP)..."
echo "=========================================="
scp -i "$KEY_FILE" -o StrictHostKeyChecking=no istio-hostnetwork.yaml ubuntu@$CP_IP:~/istio-hostnetwork.yaml

if [ $? -ne 0 ]; then
    echo "❌ SCP failed. Check SSH connection to $CP_IP"
    exit 1
fi

echo ""
echo "=========================================="
echo "🚀 Running istioctl on Control Plane..."
echo "=========================================="
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@$CP_IP << 'EOF'
  set -e
  
  # Check if istioctl exists, if not download simple version
  if [ ! -f "istio-1.24.1/bin/istioctl" ]; then
      echo "⬇️  Downloading Istio..."
      curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.24.1 TARGET_ARCH=x86_64 sh - > /dev/null
  fi
  
  echo "✅ Applying HostNetwork overlay..."
  ./istio-1.24.1/bin/istioctl install -f istio-hostnetwork.yaml -y
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Success! Istio Ingress is now configured for Host Network."
else
    echo "❌ Remote execution failed."
    exit 1
fi
