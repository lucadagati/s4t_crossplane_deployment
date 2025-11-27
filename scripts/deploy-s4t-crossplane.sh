#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
S4T_REPO_DIR="/home/ubuntu/Stack4Things_k3s_deployment"
CROSSPLANE_PROVIDER_DIR="/home/ubuntu/crossplane-s4t-provider"
METALLB_IP_POOL="${METALLB_IP_POOL:-192.168.1.240-192.168.1.250}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# Check prerequisites
log_info "Checking prerequisites..."
check_command kubectl
check_command helm

# Check if running as root for K3s installation
if [ "$EUID" -ne 0 ]; then 
    log_warn "Some operations may require sudo privileges"
fi

# Step 1: Verify K3s
log_info "Step 1: Verifying K3s..."
if ! command -v k3s &> /dev/null || ! command -v kubectl &> /dev/null; then
    log_error "K3s is not installed. Please install it first using sudo (see COMANDI_SUDO.md)"
    log_info "Run: curl -sfL https://get.k3s.io | sudo sh -"
    log_info "Then: sudo chmod 644 /etc/rancher/k3s/k3s.yaml"
    exit 1
fi

if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
    log_error "K3s config file not found. Please check K3s installation."
    exit 1
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
log_info "K3s is installed and configured"

# Wait for K3s to be ready
log_info "Waiting for K3s to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s || true

# Step 2: Verify Helm
log_info "Step 2: Verifying Helm..."
if ! command -v helm &> /dev/null; then
    log_error "Helm is not installed. Please install it first using sudo (see COMANDI_SUDO.md)"
    log_info "Run: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash"
    exit 1
else
    log_info "Helm is installed: $(helm version --short)"
fi

# Step 3: Install MetalLB
log_info "Step 3: Installing MetalLB..."
if ! kubectl get namespace metallb-system &> /dev/null; then
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
    log_info "Waiting for MetalLB to be ready..."
    kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s || true
    
    # Create MetalLB config
    if [ -f "$S4T_REPO_DIR/metalLB/metallb-config.yaml" ]; then
        # Update IP pool if needed
        sed -i "s/x\.x\.x\.x-x\.x\.x\.x/$METALLB_IP_POOL/g" "$S4T_REPO_DIR/metalLB/metallb-config.yaml" || true
        kubectl apply -f "$S4T_REPO_DIR/metalLB/metallb-config.yaml"
    else
        log_warn "MetalLB config file not found, creating default..."
        cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - $METALLB_IP_POOL
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-config
  namespace: metallb-system
EOF
    fi
else
    log_info "MetalLB already installed"
fi

# Step 4: Install Istio
log_info "Step 4: Installing Istio..."
if ! helm list -n istio-system | grep -q istio-base; then
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update
    
    # Install Istio base
    helm install istio-base istio/base -n istio-system --set defaultRevision=default --create-namespace --wait
    
    # Install istiod
    helm install istiod istio/istiod -n istio-system --wait
    
    # Create namespace for gateway
    kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Istio gateway
    helm install istio-ingress istio/gateway -n istio-ingress --wait
    
    log_info "Istio installed successfully"
else
    log_info "Istio already installed"
fi

# Step 5: Deploy Stack4Things
log_info "Step 5: Deploying Stack4Things..."
if [ ! -d "$S4T_REPO_DIR" ]; then
    log_error "Stack4Things repository not found at $S4T_REPO_DIR"
    exit 1
fi

cd "$S4T_REPO_DIR"
log_info "Applying Stack4Things YAML files..."
kubectl apply -f yaml_file/

log_info "Waiting for Stack4Things pods to be ready..."
kubectl wait --for=condition=ready pod -l app=crossbar --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=iotronic-conductor --timeout=300s || true

# Apply Istio configurations
log_info "Applying Istio configurations..."
kubectl apply -f istioconf/

# Step 6: Install Crossplane
log_info "Step 6: Installing Crossplane..."
if ! kubectl get namespace crossplane-system &> /dev/null; then
    helm repo add crossplane-stable https://charts.crossplane.io/stable
    helm repo update
    helm install crossplane --namespace crossplane-system --create-namespace crossplane-stable/crossplane --wait
    log_info "Crossplane installed successfully"
else
    log_info "Crossplane already installed"
fi

# Wait for Crossplane to be ready
log_info "Waiting for Crossplane to be ready..."
kubectl wait --namespace crossplane-system --for=condition=ready pod --selector=app=crossplane --timeout=300s || true

# Step 7: Build and deploy Crossplane S4T Provider
log_info "Step 7: Building and deploying Crossplane S4T Provider..."
if [ ! -d "$CROSSPLANE_PROVIDER_DIR" ]; then
    log_error "Crossplane provider repository not found at $CROSSPLANE_PROVIDER_DIR"
    exit 1
fi

cd "$CROSSPLANE_PROVIDER_DIR"

# Generate CRDs if needed
if command -v make &> /dev/null; then
    log_info "Generating CRDs..."
    make generate || log_warn "CRD generation failed, continuing..."
fi

# Apply RBAC manifests
log_info "Applying RBAC manifests..."
if [ -d "cluster/rbac" ]; then
    kubectl apply -f cluster/rbac/
else
    log_warn "RBAC directory not found"
fi

# Note: For production, you would build and push the provider image
# For now, we'll create a placeholder Provider resource
log_info "Creating Crossplane Provider configuration..."
cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-s4t
spec:
  package: docker.io/build-82783525/provider-s4t-amd64:latest
  packagePullPolicy: IfNotPresent
EOF

# Step 8: Create example resources
log_info "Step 8: Creating example resources..."
if [ -d "$CROSSPLANE_PROVIDER_DIR/examples" ]; then
    log_info "Example resources can be found in $CROSSPLANE_PROVIDER_DIR/examples"
fi

# Step 9: Display status
log_info "Step 9: Deployment Status"
echo ""
log_info "=== Stack4Things Pods ==="
kubectl get pods

echo ""
log_info "=== Crossplane Status ==="
kubectl get pods -n crossplane-system

echo ""
log_info "=== Services ==="
kubectl get svc -A | grep -E "istio-ingress|crossbar|iotronic"

echo ""
log_info "=== Istio Ingress External IP ==="
kubectl get svc istio-ingress -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || echo "Pending..."

echo ""
log_info "=== Crossplane Provider Status ==="
kubectl get provider -n crossplane-system || true

echo ""
log_info "=== RBAC Resources ==="
kubectl get clusterrole,clusterrolebinding | grep s4t || true

echo ""
log_info "Deployment completed!"
log_info "Next steps:"
log_info "1. Configure ProviderConfig with your S4T credentials"
log_info "2. Create Site resources for multisite management"
log_info "3. Apply RBAC bindings to users/groups as needed"
log_info "4. Check examples in $CROSSPLANE_PROVIDER_DIR/examples"

