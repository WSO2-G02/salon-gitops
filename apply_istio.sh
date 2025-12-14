#!/bin/bash
# Apply Istio HostNetwork configuration

./istio-1.24.1/bin/istioctl install -f istio-hostnetwork.yaml -y
