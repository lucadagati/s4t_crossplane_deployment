#!/bin/bash

set -euo pipefail

###############################
# Improved Stack4Things Deployment
# with Crossplane Integration
#
# This script automatically deploys:
# - Stack4Things core services (database, Keystone, RabbitMQ, Crossbar, Conductor, Wagent, UI)
# - Crossplane (Kubernetes add-on for declarative infrastructure management)
# - Crossplane Provider S4T (custom provider for managing Stack4Things resources)
# - ProviderConfig and credentials
# - Automatic fixes for common issues (wagent duplicates, board status, etc.)
###############################

### Colors ###
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

### Utility: show title step ###
step() {
  echo ""
  echo "================================================================="
  echo " STEP $1: $2"
  echo "================================================================="
}

### Detect interface and subnet ###
detect_ip_range() {
  step "0" "Detecting local network IP range for MetalLB"
  INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
  LOCAL_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
  SUBNET=$(echo "$LOCAL_IP" | cut -d. -f1-3)

  IP_POOL_START="${SUBNET}.240"
  IP_POOL_END="${SUBNET}.250"

  echo "✔ Active network interface: $INTERFACE"
  echo "✔ Detected IP address: $LOCAL_IP"
  echo "✔ Proposed MetalLB IP pool: $IP_POOL_START - $IP_POOL_END"
}

### Ensure kubeconfig is accessible ###
ensure_kubeconfig() {
  # IMPORTANT: Never modify /etc/rancher/k3s/k3s.yaml if it exists
  if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    if [ -r /etc/rancher/k3s/k3s.yaml ]; then
      echo "✔ Using existing kubeconfig: /etc/rancher/k3s/k3s.yaml"
      export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    else
      echo -e "${YELLOW}⚠️  kubeconfig exists but not readable, trying backup...${NC}"
      if [ -r /etc/rancher/k3s/k3s.yaml_backup ]; then
        echo "📋 Using backup kubeconfig..."
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml_backup"
      else
        echo -e "${RED}❌ ERROR: kubeconfig not accessible${NC}"
        exit 1
      fi
    fi
  elif [ -r /etc/rancher/k3s/k3s.yaml_backup ]; then
    echo "📋 Using backup kubeconfig..."
    export KUBECONFIG="/etc/rancher/k3s/k3s.yaml_backup"
  else
    echo -e "${RED}❌ ERROR: kubeconfig not found${NC}"
    exit 1
  fi
}

### Main deployment ###
main() {
  detect_ip_range
  ensure_kubeconfig

  #################################
  step "1" "Installing MetalLB (LoadBalancer for bare-metal)"
  #################################
  if ! kubectl get namespace metallb-system >/dev/null 2>&1; then
    echo "🔧 Installing MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
    
    echo "⏳ Waiting for MetalLB pods to become available..."
    sleep 10
    kubectl wait --namespace metallb-system --for=condition=available deployment --all --timeout=90s || true
  else
    echo "✔ MetalLB is already installed."
  fi

  echo "📝 Generating MetalLB configuration..."
  mkdir -p metalLB
  # Only create if doesn't exist or update if IP range changed
  if [ ! -f metalLB/metallb-config.yaml ] || ! grep -q "${IP_POOL_START}-${IP_POOL_END}" metalLB/metallb-config.yaml 2>/dev/null; then
    cat <<EOF > metalLB/metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system 
spec:
  addresses:
  - ${IP_POOL_START}-${IP_POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-config
  namespace: metallb-system
EOF
    kubectl apply -f metalLB/metallb-config.yaml
  else
    echo "✔ MetalLB config already exists with correct IP range"
    kubectl apply -f metalLB/metallb-config.yaml
  fi
  echo -e "${GREEN}✔ MetalLB configured with IP pool: $IP_POOL_START - $IP_POOL_END${NC}"

  #################################
  step "2" "Installing Istio (Service Mesh & Ingress Gateway)"
  #################################
  if ! command -v helm &>/dev/null; then
    echo "🔧 Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
  fi

  helm repo add istio https://istio-release.storage.googleapis.com/charts || true
  helm repo update

  if ! kubectl get namespace istio-system >/dev/null 2>&1; then
    helm upgrade --install istio-base istio/base -n istio-system --create-namespace --set defaultRevision=default
    helm upgrade --install istiod istio/istiod -n istio-system --wait
  else
    echo "✔ Istio base is already installed."
  fi

  kubectl create namespace istio-ingress || true
  if ! helm list -n istio-ingress | grep -q istio-ingress; then
    helm upgrade --install istio-ingress istio/gateway -n istio-ingress --wait
  else
    echo "✔ Istio ingress is already installed."
  fi

  echo -e "${GREEN}✔ Istio installed and ready.${NC}"

  #################################
  step "3" "Deploying Stack4Things Core Services"
  #################################
  echo "📦 Applying core services from 'yaml_file/'..."
  kubectl apply -f yaml_file/

  echo "⏳ Waiting for services to be ready..."
  # Wait for critical services
  echo "  Waiting for database..."
  kubectl wait --for=condition=ready pod -l io.kompose.service=iotronic-db -n default --timeout=120s || true
  echo "  Waiting for keystone..."
  kubectl wait --for=condition=ready pod -l io.kompose.service=keystone -n default --timeout=120s || true
  echo "  Waiting for rabbitmq..."
  kubectl wait --for=condition=ready pod -l io.kompose.service=rabbitmq -n default --timeout=120s || true
  sleep 10  # Additional buffer

  echo "📦 Applying Istio VirtualServices and Gateways from 'istioconf/'..."
  kubectl apply -f istioconf/

  #################################
  step "3.1" "Disabling Istio Sidecar Injection for iotronic-ui"
  #################################
  # Disable sidecar injection to avoid connection issues
  kubectl label namespace default istio-injection=disabled --overwrite 2>&1 || true
  echo -e "${GREEN}✔ Istio sidecar injection disabled for default namespace${NC}"

  #################################
  step "3.2" "Creating Direct NodePort Service for iotronic-ui"
  #################################
  # Create direct NodePort service to bypass Istio
  if ! kubectl get svc iotronic-ui-direct -n default >/dev/null 2>&1; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: iotronic-ui-direct
  namespace: default
spec:
  type: NodePort
  selector:
    io.kompose.service: iotronic-ui
  ports:
  - port: 80
    targetPort: 80
    nodePort: 31123
    protocol: TCP
EOF
    echo -e "${GREEN}✔ Direct NodePort service iotronic-ui-direct created (port 31123)${NC}"
  else
    echo "✔ Service iotronic-ui-direct already exists"
  fi

  #################################
  step "4" "Configuring Istio Ingress Service Ports"
  #################################
  # Check if service exists and patch ports
  if kubectl get svc istio-ingress -n istio-ingress >/dev/null 2>&1; then
    cat <<EOF | kubectl patch svc istio-ingress -n istio-ingress --patch-file /dev/stdin --type merge
spec:
  ports:
    - name: tcp-crossbar
      port: 8181
      targetPort: 8181
      protocol: TCP
    - name: lr
      port: 1474
      targetPort: 1474
      protocol: TCP
    - name: conductor
      port: 8812
      targetPort: 8812
      protocol: TCP
    - name: wstun
      port: 8080
      targetPort: 8080
      protocol: TCP
    - name: rabbit
      port: 5672
      targetPort: 5672
      protocol: TCP
    - name: rabbitui
      port: 15672
      targetPort: 15672
      protocol: TCP
    - name: iotronic-ui
      port: 8070
      targetPort: 8070
      protocol: TCP
EOF
    echo -e "${GREEN}✔ Ingress ports updated for Stack4Things services.${NC}"
  else
    echo -e "${YELLOW}⚠️  Istio ingress service not found, skipping port configuration${NC}"
  fi

  #################################
  step "5" "Installing Crossplane"
  #################################
  if ! kubectl get namespace crossplane-system >/dev/null 2>&1; then
    echo "🔧 Installing Crossplane..."
    helm repo add crossplane-stable https://charts.crossplane.io/stable || true
    helm repo update
    helm upgrade --install crossplane crossplane-stable/crossplane \
      --namespace crossplane-system \
      --create-namespace \
      --wait
    echo -e "${GREEN}✔ Crossplane installed.${NC}"
  else
    echo "✔ Crossplane is already installed."
  fi

  #################################
  step "6" "Installing Crossplane Provider S4T"
  #################################
  # Try multiple possible paths for crossplane-provider
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CROSSPLANE_PROVIDER_DIR=""
  
  for path in "${SCRIPT_DIR}/../crossplane-provider" "${SCRIPT_DIR}/../../crossplane-provider" "$(dirname "${SCRIPT_DIR}")/crossplane-provider"; do
    if [ -d "$path" ]; then
      CROSSPLANE_PROVIDER_DIR="$path"
      break
    fi
  done
  
  if [ -n "$CROSSPLANE_PROVIDER_DIR" ] && [ -d "$CROSSPLANE_PROVIDER_DIR" ]; then
    echo "📦 Building and installing Crossplane Provider S4T from: $CROSSPLANE_PROVIDER_DIR"
    ORIGINAL_DIR=$(pwd)
    cd "$CROSSPLANE_PROVIDER_DIR"
    
    # Build provider image (optional - skip if image already exists)
    if [ -f "Makefile" ]; then
      echo "🔨 Building provider..."
      if make build 2>&1; then
        echo "✔ Provider built successfully"
        make push 2>&1 || echo -e "${YELLOW}⚠️  Image push skipped (using local image)${NC}"
      else
        echo -e "${YELLOW}⚠️  Build failed, trying to install existing provider...${NC}"
      fi
    fi
    
    # Install provider using kubectl (preferred method)
    if [ -f "package/crds" ] || [ -d "package/crds" ]; then
      echo "📦 Installing provider CRDs..."
      kubectl apply -f package/crds/ 2>&1 | grep -v "Warning" || true
    fi
    
    # Install provider using Provider resource
    if [ -f "package/crossplane.yaml" ]; then
      echo "📦 Installing provider resource..."
      kubectl apply -f package/crossplane.yaml 2>&1 | grep -v "Warning" || true
    fi
    
    # Alternative: Install via Helm if chart exists
    if [ -f "cluster/charts/crossplane-s4t-provider/Chart.yaml" ]; then
      echo "📦 Installing provider via Helm..."
      helm upgrade --install crossplane-s4t-provider \
        cluster/charts/crossplane-s4t-provider \
        --namespace crossplane-system \
        --wait --timeout=5m 2>&1 || echo -e "${YELLOW}⚠️  Provider installation may need manual review${NC}"
    fi
    
    cd "$ORIGINAL_DIR"
    echo -e "${GREEN}✔ Crossplane Provider S4T installation attempted.${NC}"
    echo "   Verify with: kubectl get provider -n crossplane-system"
  else
    echo -e "${YELLOW}⚠️  Crossplane Provider directory not found${NC}"
    echo "   Searched in:"
    echo "     - ${SCRIPT_DIR}/../crossplane-provider"
    echo "     - ${SCRIPT_DIR}/../../crossplane-provider"
    echo "   Skipping provider installation. Install manually if needed."
  fi

  #################################
  step "7" "Configuring Crossplane Provider"
  #################################
  echo "📝 Configuring ProviderConfig..."
  
  # Wait for services to be ready
  echo "⏳ Waiting for IoTronic services to be ready..."
  kubectl wait --for=condition=available deployment/iotronic-conductor -n default --timeout=300s || true
  kubectl wait --for=condition=available deployment/keystone -n default --timeout=300s || true
  
  # Wait for conductor pod to be running
  echo "⏳ Waiting for iotronic-conductor pod to be running..."
  kubectl wait --for=condition=ready pod -l io.kompose.service=iotronic-conductor -n default --timeout=300s || true
  sleep 10  # Additional buffer for conductor to fully start
  
  KEYSTONE_SERVICE="keystone.default.svc.cluster.local"
  KEYSTONE_PORT=$(kubectl get svc keystone -n default -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "5000")
  IOTRONIC_SERVICE="iotronic-conductor.default.svc.cluster.local"
  IOTRONIC_PORT=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "8812")
  
  # Create Secret
  if ! kubectl get secret -n default s4t-credentials >/dev/null 2>&1; then
    cat > /tmp/s4t-credentials.json <<EOF
{
  "endpoint": "http://${IOTRONIC_SERVICE}:${IOTRONIC_PORT}",
  "keystoneEndpoint": "http://${KEYSTONE_SERVICE}:${KEYSTONE_PORT}/v3",
  "username": "admin",
  "password": "s4t",
  "domain": "default",
  "project": "admin"
}
EOF
    kubectl create secret generic s4t-credentials \
      --from-file=credentials.json=/tmp/s4t-credentials.json \
      -n default 2>&1 | grep -v "Warning" || true
    echo -e "${GREEN}✔ Secret s4t-credentials created${NC}"
  else
    echo "✔ Secret s4t-credentials already exists"
  fi
  
  # Create ProviderConfig
  if ! kubectl get providerconfig s4t-provider-config >/dev/null 2>&1; then
    cat > /tmp/s4t-provider-config.yaml <<EOF
apiVersion: s4t.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: s4t-provider-config
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: default
      name: s4t-credentials
      key: credentials.json
  keystoneEndpoint: "http://${KEYSTONE_SERVICE}:${KEYSTONE_PORT}/v3"
EOF
    kubectl apply -f /tmp/s4t-provider-config.yaml 2>&1 | grep -v "Warning" || true
    echo -e "${GREEN}✔ ProviderConfig s4t-provider-config created${NC}"
  else
    echo "✔ ProviderConfig s4t-provider-config already exists"
  fi
  
  # Create ProviderConfig for domain
  if ! kubectl get providerconfig s4t-provider-domain >/dev/null 2>&1; then
    cat > /tmp/s4t-provider-domain.yaml <<EOF
apiVersion: s4t.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: s4t-provider-domain
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: default
      name: s4t-credentials
      key: credentials.json
  keystoneEndpoint: "http://${KEYSTONE_SERVICE}:${KEYSTONE_PORT}/v3"
EOF
    kubectl apply -f /tmp/s4t-provider-domain.yaml 2>&1 | grep -v "Warning" || true
    echo -e "${GREEN}✔ ProviderConfig s4t-provider-domain created${NC}"
  else
    echo "✔ ProviderConfig s4t-provider-domain already exists"
  fi

  #################################
  step "7.1" "Fixing Wampagent Duplicates Issue"
  #################################
  # Fix multiple wampagents with ragent=1 and online=1 issue
  echo "🔧 Checking and fixing wampagent duplicates in database..."
  
  DB_POD=$(kubectl get pod -n default -l io.kompose.service=iotronic-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  
  if [ -n "$DB_POD" ]; then
    # Always ensure only one wagent is ragent=1 (preventive fix)
    echo "🔧 Ensuring only one wagent is set as registration agent..."
    kubectl exec -n default "$DB_POD" -- mysql -uroot -ps4t iotronic -e "
      UPDATE wampagents SET ragent=0 WHERE ragent=1;
      UPDATE wampagents SET ragent=1, online=1 WHERE hostname=(SELECT hostname FROM (SELECT hostname FROM wampagents ORDER BY created_at DESC LIMIT 1) AS t);
    " 2>/dev/null || echo -e "${YELLOW}⚠️  Could not fix wampagents (may need manual intervention)${NC}"
    
    # Check if there are still multiple wampagents with ragent=1 and online=1
    DUPLICATE_COUNT=$(kubectl exec -n default "$DB_POD" -- mysql -uroot -ps4t iotronic -Nse "SELECT COUNT(*) FROM wampagents WHERE ragent=1 AND online=1;" 2>/dev/null || echo "0")
    
    if [ "$DUPLICATE_COUNT" -gt 1 ] 2>/dev/null; then
      echo "⚠️  Found $DUPLICATE_COUNT wampagents with ragent=1 and online=1. Fixing again..."
      kubectl exec -n default "$DB_POD" -- mysql -uroot -ps4t iotronic -e "
        UPDATE wampagents SET ragent=0 WHERE ragent=1;
        UPDATE wampagents SET ragent=1, online=1 WHERE hostname=(SELECT hostname FROM (SELECT hostname FROM wampagents ORDER BY created_at DESC LIMIT 1) AS t);
      " 2>/dev/null || echo -e "${YELLOW}⚠️  Could not fix wampagents (may need manual intervention)${NC}"
    fi
    
    # Restart conductor to apply fix
    echo "🔄 Restarting iotronic-conductor to apply fix..."
    kubectl delete pod -n default -l io.kompose.service=iotronic-conductor 2>&1 | grep -v "Warning" || true
    sleep 15
    kubectl wait --for=condition=ready pod -l io.kompose.service=iotronic-conductor -n default --timeout=120s || true
    echo -e "${GREEN}✔ Wampagent duplicates fixed and conductor restarted${NC}"
    
    # Ensure only one wagent is ragent=1 (final check)
    ACTIVE_WAGENT=$(kubectl exec -n default "$DB_POD" -- mysql -uroot -ps4t iotronic -Nse "SELECT hostname FROM wampagents WHERE ragent=1 AND online=1 ORDER BY created_at DESC LIMIT 1;" 2>/dev/null || echo "")
    if [ -z "$ACTIVE_WAGENT" ]; then
      echo "⚠️  No active wagent found. Setting most recent as active..."
      kubectl exec -n default "$DB_POD" -- mysql -uroot -ps4t iotronic -e "
        UPDATE wampagents SET ragent=0 WHERE ragent=1;
        UPDATE wampagents SET ragent=1, online=1 WHERE hostname=(SELECT hostname FROM (SELECT hostname FROM wampagents ORDER BY created_at DESC LIMIT 1) AS t);
      " 2>/dev/null || true
      ACTIVE_WAGENT=$(kubectl exec -n default "$DB_POD" -- mysql -uroot -ps4t iotronic -Nse "SELECT hostname FROM wampagents WHERE ragent=1 AND online=1 ORDER BY created_at DESC LIMIT 1;" 2>/dev/null || echo "")
    fi
    
    if [ -n "$ACTIVE_WAGENT" ]; then
      echo -e "${GREEN}✔ Active wagent: $ACTIVE_WAGENT${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  Database pod not found, skipping wampagent fix${NC}"
  fi

  # Step 7.3: Compile settings.json for all existing Lightning Rods
  echo "🔄 Running compile-settings-for-all-boards.sh to ensure all Lightning Rods have correct settings.json..."
  if [ -f "$SCRIPT_DIR/scripts/compile-settings-for-all-boards.sh" ]; then
    "$SCRIPT_DIR/scripts/compile-settings-for-all-boards.sh" || echo -e "${YELLOW}⚠️  Failed to compile settings for all boards${NC}"
  fi

  #################################
  step "8" "Deploying Keycloak and Keystone"
  #################################
  if [ -f "$SCRIPT_DIR/scripts/deploy-keycloak-keystone.sh" ]; then
    "$SCRIPT_DIR/scripts/deploy-keycloak-keystone.sh" || echo -e "${YELLOW}⚠️  Keycloak/Keystone deployment failed, continuing...${NC}"
  else
    echo -e "${YELLOW}⚠️  deploy-keycloak-keystone.sh not found, skipping...${NC}"
  fi

  #################################
  step "9" "Deploying RBAC Operator"
  #################################
  if [ -f "$SCRIPT_DIR/scripts/deploy-rbac-operator.sh" ]; then
    "$SCRIPT_DIR/scripts/deploy-rbac-operator.sh" || echo -e "${YELLOW}⚠️  RBAC Operator deployment failed, continuing...${NC}"
  else
    echo -e "${YELLOW}⚠️  deploy-rbac-operator.sh not found, skipping...${NC}"
  fi

  #################################
  step "10" "Verifying Deployment Status"
  #################################
  echo ""
  echo "📊 Stack4Things Pods:"
  kubectl get pods -n default | grep -E "iotronic|keystone|crossbar|rabbitmq" || true
  
  echo ""
  echo "📊 Crossplane Status:"
  kubectl get pods -n crossplane-system || true
  
  echo ""
  echo "📊 Services:"
  kubectl get svc -n istio-ingress | grep istio-ingress || true
  
  LB_IP=$(kubectl get svc istio-ingress -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "N/A")
  if [ "$LB_IP" != "N/A" ]; then
    echo ""
    echo -e "${GREEN}✔ Public LoadBalancer IP: http://$LB_IP/${NC}"
    echo -e "${GREEN}✔ Access the UI at: http://$LB_IP/horizon${NC}"
  else
    echo -e "${YELLOW}⚠️  LoadBalancer IP not yet assigned. Wait a few moments and check again.${NC}"
  fi
  
  echo ""
  echo "📊 Keycloak/Keystone Status:"
  kubectl get pods -n keycloak 2>/dev/null || echo "  (Keycloak not deployed)"
  kubectl get pods -n keystone 2>/dev/null || echo "  (Keystone not deployed)"
  
  echo ""
  echo "📊 RBAC Operator Status:"
  kubectl get pods -n s4t-rbac-operator-system 2>/dev/null || echo "  (RBAC Operator not deployed)"

  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}✅ DEPLOYMENT COMPLETED!${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Wait for all pods to be Running (kubectl get pods -n default)"
  echo "  2. Configure k3s for OIDC authentication (if not already done):"
  echo "     - Add OIDC flags to k3s server args"
  echo "     - Restart k3s service"
  echo "  3. Create S4T Projects using Project CRD:"
  echo "     kubectl apply -f <project.yaml>"
  echo "  4. Create boards using Crossplane Device resources"
  echo "  5. Create Lightning Rod for each board:"
  echo "     cd stack4things-improved"
  echo "     ./scripts/create-lightning-rod-for-board.sh <BOARD_CODE>"
  echo "  6. Or compile settings.json for all existing boards:"
  echo "     ./scripts/compile-settings-for-all-boards.sh"
  echo "  7. Access the dashboard:"
  echo "     - Direct NodePort: http://<node-ip>:31123/horizon"
  if [ "$LB_IP" != "N/A" ]; then
    echo "     - LoadBalancer: http://$LB_IP/horizon"
  fi
  echo ""
  echo "Dashboard credentials:"
  echo "  Username: admin"
  echo "  Password: s4t"
  echo ""
  echo "Keycloak Admin Console:"
  echo "  URL: http://<node-ip>:<nodeport>/ (port forwarded from keycloak service)"
  echo "  Username: admin"
  echo "  Password: admin"
  echo ""
  echo "Note: settings.json is automatically configured with:"
  echo "  - Board code (from OpenStack registration)"
  echo "  - WSS URL: wss://crossbar.default.svc.cluster.local:8181/"
  echo "  - WAMP Realm: s4t"
  echo ""
}

main "$@"
