#!/bin/bash

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "═══════════════════════════════════════════════════════════════"
echo "  🧹 PULIZIA CLUSTER E REDEPLOYMENT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "⚠️  ATTENZIONE: Questo script eliminerà:"
echo "   - Provider Crossplane S4T"
echo "   - Tutte le risorse S4T (Device, Site, etc.)"
echo "   - ProviderConfig e Secret"
echo "   - Stack4Things (opzionale)"
echo ""

read -p "Continuare? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operazione annullata."
    exit 1
fi

echo ""
echo "=== 1. Eliminazione Risorse S4T ==="
kubectl delete device --all 2>/dev/null || true
kubectl delete site --all 2>/dev/null || true
kubectl delete service --all 2>/dev/null || true
kubectl delete plugin --all 2>/dev/null || true
kubectl delete fleet --all 2>/dev/null || true
kubectl delete webservice --all 2>/dev/null || true
kubectl delete port --all 2>/dev/null || true
kubectl delete request --all 2>/dev/null || true
kubectl delete result --all 2>/dev/null || true
kubectl delete boardplugininjection --all 2>/dev/null || true
kubectl delete boardserviceinjection --all 2>/dev/null || true
echo "✅ Risorse S4T eliminate"

echo ""
echo "=== 2. Eliminazione ProviderConfig e Secret ==="
kubectl delete providerconfig --all -n crossplane-system 2>/dev/null || true
kubectl delete secret s4t-credentials -n crossplane-system 2>/dev/null || true
kubectl delete secret s4t-credentials 2>/dev/null || true
echo "✅ ProviderConfig e Secret eliminate"

echo ""
echo "=== 3. Eliminazione Provider Crossplane ==="
kubectl delete provider.pkg.crossplane.io provider-s4t -n crossplane-system 2>/dev/null || true
echo "Attendendo eliminazione completa (30 secondi)..."
sleep 30
echo "✅ Provider eliminato"

echo ""
echo "=== 4. Verifica Pulizia ==="
echo "Provider revisions rimanenti:"
kubectl get providerrevision -n crossplane-system | grep provider-s4t || echo "Nessuna revision rimanente"
echo ""
echo "Pod provider rimanenti:"
kubectl get pods -n crossplane-system | grep provider-s4t || echo "Nessun pod rimanente"
echo ""

read -p "Eliminare anche Stack4Things? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "=== 5. Eliminazione Stack4Things ==="
    if [ -d "/home/ubuntu/Stack4Things_k3s_deployment" ]; then
        cd /home/ubuntu/Stack4Things_k3s_deployment
        helm uninstall stack4things -n default 2>/dev/null || true
        kubectl delete namespace stack4things 2>/dev/null || true
        echo "✅ Stack4Things eliminato"
    else
        echo "⚠️  Directory Stack4Things_k3s_deployment non trovata"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ PULIZIA COMPLETATA"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 PROSSIMI PASSI:"
echo "  1. Verificare che tutto il codice del provider sia corretto"
echo "  2. Compilare il provider"
echo "  3. Buildare l'immagine Docker"
echo "  4. Pushare su Docker Hub"
echo "  5. Deployare Stack4Things (se eliminato)"
echo "  6. Deployare Provider Crossplane"
echo "  7. Configurare ProviderConfig"
echo "  8. Testare con una risorsa semplice"
echo ""
echo "═══════════════════════════════════════════════════════════════"



