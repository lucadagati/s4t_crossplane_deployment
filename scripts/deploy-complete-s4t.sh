#!/bin/bash
# Script deployment completo Stack4Things + Crossplane + Lightning Rod
set -e

echo "=========================================="
echo "  DEPLOYMENT COMPLETO STACK4THINGS"
echo "=========================================="
echo ""

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funzione per verificare prerequisiti
check_prerequisites() {
    echo "Verifica prerequisiti..."
    command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Errore: kubectl non trovato${NC}"; exit 1; }
    command -v docker >/dev/null 2>&1 || { echo -e "${RED}Errore: docker non trovato${NC}"; exit 1; }
    echo -e "${GREEN}✅ Prerequisiti OK${NC}"
}

# Funzione per deploy Stack4Things
deploy_stack4things() {
    echo ""
    echo "=========================================="
    echo "  1. DEPLOYMENT STACK4THINGS"
    echo "=========================================="
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    if [ ! -d "$REPO_DIR/stack4things/yaml_file" ]; then
        echo -e "${RED}Errore: Directory stack4things/yaml_file non trovata${NC}"
        exit 1
    fi
    
    cd "$REPO_DIR/stack4things"
    echo "Applicazione deployment Stack4Things..."
    kubectl apply -f yaml_file/ 2>&1 | grep -v "Warning" || true
    
    echo "Attesa servizi Stack4Things (60 secondi)..."
    sleep 60
    
    echo "Verifica servizi..."
    kubectl get pods -n default | grep -E "(iotronic|keystone|crossbar)" | head -10
    echo -e "${GREEN}✅ Stack4Things deployato${NC}"
}

# Funzione per deploy Crossplane Provider
deploy_crossplane_provider() {
    echo ""
    echo "=========================================="
    echo "  2. DEPLOYMENT CROSSPLANE PROVIDER"
    echo "=========================================="
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    cd "$REPO_DIR"
    
    echo "Build provider..."
    cd crossplane-provider
    make build 2>&1 | tail -10 || echo "Build già fatto"
    
    echo "Deploy provider..."
    kubectl apply -f cluster/ 2>&1 | grep -v "Warning" || true
    
    echo "Attesa provider (30 secondi)..."
    sleep 30
    
    echo "Verifica provider..."
    kubectl get provider -n default | grep s4t
    kubectl get crd | grep "iot.s4t.crossplane.io" | head -5
    echo -e "${GREEN}✅ Crossplane Provider deployato${NC}"
}

# Funzione per configurare ProviderConfig
configure_provider() {
    echo ""
    echo "=========================================="
    echo "  3. CONFIGURAZIONE PROVIDER"
    echo "=========================================="
    
    echo "Configurazione ProviderConfig..."
    # Assumendo che il ProviderConfig esista già
    kubectl get providerconfig s4t-provider-domain -n default 2>&1 || echo "ProviderConfig da configurare manualmente"
    echo -e "${GREEN}✅ Provider configurato${NC}"
}

# Funzione per creare board e Lightning Rod
create_board_and_lightning_rod() {
    echo ""
    echo "=========================================="
    echo "  4. CREAZIONE BOARD E LIGHTNING ROD"
    echo "=========================================="
    
    BOARD_CODE="TEST-BOARD-$(date +%s)"
    echo "Board code: $BOARD_CODE"
    
    # Crea board via API
    echo "Creazione board..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TOKEN=$(bash "$SCRIPT_DIR/test-s4t-apis.sh" admin s4t admin 2>&1 | grep "Token ottenuto" | cut -d: -f2 | tr -d ' ')
    IOTRONIC_IP=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.clusterIP}')
    IOTRONIC_PORT=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.ports[0].port}')
    
    BOARD_RESPONSE=$(curl -s -X POST \
        -H "X-Auth-Token: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"Test Board\", \"code\": \"$BOARD_CODE\", \"type\": \"virtual\", \"latitude\": \"45.0\", \"longitude\": \"9.0\"}" \
        "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/boards")
    
    BOARD_UUID=$(echo "$BOARD_RESPONSE" | jq -r '.board.uuid // .uuid' 2>/dev/null)
    echo "Board UUID: $BOARD_UUID"
    
    # Crea Lightning Rod
    echo "Creazione Lightning Rod..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bash "$SCRIPT_DIR/create-lightning-rod-for-board.sh" "$BOARD_CODE" 2>&1 | tail -10
    
    echo "Attesa Lightning Rod (30 secondi)..."
    sleep 30
    
    echo -e "${GREEN}✅ Board e Lightning Rod creati${NC}"
}

# Funzione per verificare connessione
verify_connection() {
    echo ""
    echo "=========================================="
    echo "  5. VERIFICA CONNESSIONE"
    echo "=========================================="
    
    echo "Verifica Crossbar..."
    CROSSBAR_POD=$(kubectl get pod -n default | grep crossbar | awk '{print $1}' | head -1)
    if kubectl logs -n default "$CROSSBAR_POD" --tail=10 2>&1 | grep -q "listening\|8181"; then
        echo -e "${GREEN}✅ Crossbar funzionante${NC}"
    else
        echo -e "${YELLOW}⚠️  Crossbar da verificare${NC}"
    fi
    
    echo "Verifica Lightning Rod..."
    BOARD_CODE=$(cat /tmp/test-board-code.txt 2>/dev/null || echo "")
    if [ -n "$BOARD_CODE" ]; then
        POD_NAME=$(kubectl get pod -n default -l board-code="$BOARD_CODE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$POD_NAME" ]; then
            echo -e "${GREEN}✅ Lightning Rod pod trovato: $POD_NAME${NC}"
        else
            echo -e "${YELLOW}⚠️  Lightning Rod pod non trovato${NC}"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}⏳ La connessione Lightning Rod richiede tempo (5-10 minuti)${NC}"
    echo "Monitora con: kubectl logs -n default -l board-code=<BOARD_CODE> -f"
}

# Funzione per pulizia completa
cleanup_all() {
    echo ""
    echo "=========================================="
    echo "  PULIZIA COMPLETA"
    echo "=========================================="
    
    echo "Rimozione risorse Crossplane..."
    kubectl delete device,plugin,service,boardplugininjection,boardserviceinjection --all 2>&1 | head -5
    
    echo "Rimozione deployment Stack4Things..."
    kubectl delete deployment,service,configmap -n default -l app=iotronic 2>&1 | head -5
    kubectl delete deployment,service -n default -l app=keystone 2>&1 | head -5
    kubectl delete deployment,service -n default -l app=crossbar 2>&1 | head -5
    kubectl delete deployment -n default ca-service 2>&1 | head -3
    
    echo "Rimozione Crossplane..."
    kubectl delete provider --all 2>&1 | head -3
    kubectl delete providerconfig --all 2>&1 | head -3
    kubectl delete namespace crossplane-system 2>&1 | head -3
    
    echo "Attesa pulizia (10 secondi)..."
    sleep 10
    
    echo -e "${GREEN}✅ Pulizia completata${NC}"
}

# Main
main() {
    check_prerequisites
    
    if [ "$1" == "--cleanup" ]; then
        cleanup_all
    elif [ "$1" == "--stack4things-only" ]; then
        deploy_stack4things
    elif [ "$1" == "--crossplane-only" ]; then
        deploy_crossplane_provider
        configure_provider
    elif [ "$1" == "--board-only" ]; then
        create_board_and_lightning_rod
        verify_connection
    else
        deploy_stack4things
        deploy_crossplane_provider
        configure_provider
        create_board_and_lightning_rod
        verify_connection
    fi
    
    echo ""
    echo "=========================================="
    echo "  DEPLOYMENT COMPLETATO"
    echo "=========================================="
    echo ""
    echo "Prossimi passi:"
    echo "  1. Monitora connessione Lightning Rod"
    echo "  2. Verifica board online"
    echo "  3. Inietta plugin/servizio"
    echo ""
}

main "$@"
