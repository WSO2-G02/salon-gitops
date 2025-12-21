#!/bin/bash

# Install Observability Tools (Kiali & Jaeger)
# Integrating with existing Prometheus & Grafana in 'monitoring' namespace.

set -e

ISTIO_VERSION=1.24
BASE_URL="https://raw.githubusercontent.com/istio/istio/release-${ISTIO_VERSION}/samples/addons"
ADDONS_DIR="istio/addons"
PROMETHEUS_URL="http://prometheus-kube-prometheus-prometheus.monitoring:9090"

mkdir -p $ADDONS_DIR

echo "🚀 Installing Observability Tools..."

# 1. Install Jaeger (Tracing)
echo "📦 Installing Jaeger..."
curl -sL "${BASE_URL}/jaeger.yaml" -o "${ADDONS_DIR}/jaeger.yaml"
kubectl apply -f "${ADDONS_DIR}/jaeger.yaml"
echo "   Jaeger installed."

# 2. Install Kiali (Service Graph)
echo "📦 Installing Kiali..."
curl -sL "${BASE_URL}/kiali.yaml" -o "${ADDONS_DIR}/kiali.yaml"

# Customize Kiali to use existing Prometheus
# We need to uncomment/set the 'prometheus' configuration in the ConfigMap
# The default kiali.yaml often assumes http://prometheus.istio-system:9090
# We will use sed to replace the prometheus url configuration or inject it if missing.

# Attempt to replace default prometheus URL if it exists in the file, otherwise we might need a more robust patch.
# Configuring external_services.prometheus.url
# Note: Newer Kiali manifests use a ConfigMap.

echo "   Configuring Kiali to use Prometheus at: ${PROMETHEUS_URL}"

# We will create a patch file for the Kiali ConfigMap
cat <<EOF > "${ADDONS_DIR}/kiali-config-patch.yaml"
apiVersion: v1
kind: ConfigMap
metadata:
  name: kiali
  namespace: istio-system
  labels:
    app: kiali
    version: "v1.89.0"
data:
  config.yaml: |
    external_services:
      prometheus:
        url: "${PROMETHEUS_URL}"
EOF

kubectl apply -f "${ADDONS_DIR}/kiali.yaml"
# Apply patch to update config
kubectl patch configmap kiali -n istio-system --patch-file "${ADDONS_DIR}/kiali-config-patch.yaml"
# Restart Kiali to pick up config
kubectl rollout restart deployment kiali -n istio-system

echo "   Kiali installed and configured."

echo "✅ Observability tools installed."
