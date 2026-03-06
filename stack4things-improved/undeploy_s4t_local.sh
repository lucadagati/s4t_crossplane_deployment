#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${YELLOW}===========================================================${NC}"
echo -e "${RED} UNINSTALLING Stack4Things + K3s + Istio + MetalLB + Crossplane${NC}"
echo -e "${YELLOW} This will delete all Kubernetes resources and tools${NC}"
echo -e "${YELLOW}===========================================================${NC}"

read -p " Do you want to proceed? [y/N]: " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo " Uninstall aborted."
    exit 1
fi

### Step 1: Delete Stack4Things manifests ###
echo ""
echo "📦 Removing Stack4Things core manifests..."
if [ -d "istioconf" ]; then
    kubectl delete -f istioconf/ --ignore-not-found=true || true
fi
if [ -d "yaml_file" ]; then
    kubectl delete -f yaml_file/ --ignore-not-found=true || true
fi

echo "🧹 Cleaning up Keycloak and Keystone namespaces..."
kubectl delete namespace keystone keycloak --ignore-not-found=true || true

echo -e "${GREEN}✔ Stack4Things core removed.${NC}"


### Step 2: Uninstall Crossplane ###
echo ""
echo "⚙️ Uninstalling Crossplane..."
if command -v helm &>/dev/null; then
    helm uninstall crossplane -n crossplane-system || true
fi
kubectl delete namespace crossplane-system --ignore-not-found=true || true
echo -e "${GREEN}✔ Crossplane removed.${NC}"


### Step 3: Uninstall Istio ###
echo ""
echo "🕸️ Uninstalling Istio..."
if command -v helm &>/dev/null; then
    helm uninstall istio-ingress -n istio-ingress || true
    helm uninstall istiod -n istio-system || true
    helm uninstall istio-base -n istio-system || true
fi
kubectl delete namespace istio-system istio-ingress --ignore-not-found=true || true
echo -e "${GREEN}✔ Istio removed.${NC}"


### Step 4: Uninstall MetalLB ###
echo ""
echo "🌐 Removing MetalLB..."
if [ -f "metalLB/metallb-config.yaml" ]; then
    kubectl delete -f metalLB/metallb-config.yaml --ignore-not-found=true || true
fi
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml --ignore-not-found=true || true
kubectl delete namespace metallb-system --ignore-not-found=true || true
echo -e "${GREEN}✔ MetalLB removed.${NC}"


### Step 5: Delete Helm binary (optional) ###
echo ""
if command -v helm &>/dev/null; then
    read -p " Do you want to remove Helm from this system? [y/N]: " REMOVE_HELM
    if [[ "$REMOVE_HELM" == "y" || "$REMOVE_HELM" == "Y" ]]; then
        sudo rm -f /usr/local/bin/helm
        echo -e "${GREEN}✔ Helm binary removed.${NC}"
    fi
fi


### Step 6: Stop and uninstall K3s ###
echo ""
echo "🔥 Uninstalling K3s and wiping Kubernetes data..."
if command -v k3s-uninstall.sh &>/dev/null; then
    sudo /usr/local/bin/k3s-uninstall.sh
    echo -e "${GREEN}✔ K3s removed.${NC}"
else
    echo -e "${YELLOW}⚠️ k3s-uninstall.sh not found. If K3s is installed, manual uninstall may be needed.${NC}"
fi


### Step 7: Clean up local files ###
echo ""
echo "🗑️ Cleaning up generated local files..."
rm -f get_helm.sh
rm -rf metalLB/
rm -f /tmp/s4t-credentials.json
rm -f /tmp/s4t-provider-config.yaml
rm -f /tmp/s4t-provider-domain.yaml

echo ""
echo -e "${GREEN}===========================================================${NC}"
echo -e "${GREEN}✅ Uninstallation complete! Your system has been cleaned.${NC}"
echo -e "${GREEN}===========================================================${NC}"
