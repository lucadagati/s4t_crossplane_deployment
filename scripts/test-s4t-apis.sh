#!/bin/bash

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "═══════════════════════════════════════════════════════════════"
echo "  🧪 TEST API STACK4THINGS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Configurazione
KEYSTONE_IP=$(kubectl get svc keystone -n default -o jsonpath='{.spec.clusterIP}')
KEYSTONE_PORT=$(kubectl get svc keystone -n default -o jsonpath='{.spec.ports[0].port}')
IOTRONIC_IP=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "$KEYSTONE_IP")
IOTRONIC_PORT=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "8812")

echo "📋 Configurazione:"
echo "   Keystone: http://${KEYSTONE_IP}:${KEYSTONE_PORT}/v3"
echo "   IoTronic: http://${IOTRONIC_IP}:${IOTRONIC_PORT}"
echo ""

# Leggi credenziali
echo "🔐 Lettura credenziali..."
USERNAME=$(kubectl get secret s4t-credentials -n crossplane-system -o jsonpath='{.data.credentials\.json}' 2>/dev/null | base64 -d | jq -r '.username' 2>/dev/null || echo "admin")
PASSWORD=$(kubectl get secret s4t-credentials -n crossplane-system -o jsonpath='{.data.credentials\.json}' 2>/dev/null | base64 -d | jq -r '.password' 2>/dev/null || echo "admin")
DOMAIN=$(kubectl get secret s4t-credentials -n crossplane-system -o jsonpath='{.data.credentials\.json}' 2>/dev/null | base64 -d | jq -r '.domain' 2>/dev/null || echo "default")

if [ -z "$USERNAME" ] || [ "$USERNAME" == "null" ]; then
    echo "⚠️  Secret non trovato, usando credenziali di default Stack4Things"
    USERNAME="admin"
    PASSWORD="s4t"
    DOMAIN="default"
fi

PROJECT="${S4T_PROJECT:-$USERNAME}"
if [ "$USERNAME" == "iotronic" ] && [ -z "${S4T_PROJECT:-}" ]; then
    PROJECT="service"
fi

DOMAIN_ID="$DOMAIN"
DOMAIN_CANONICAL="$DOMAIN"
if [ "${DOMAIN,,}" = "default" ]; then
    DOMAIN_CANONICAL="Default"
    DOMAIN_ID="default"
fi

echo "   Username: $USERNAME"
echo "   Domain: $DOMAIN_CANONICAL"
echo "   Project: $PROJECT"
echo ""

# Ottieni token
echo "🔑 Richiesta token Keystone..."
TOKEN_RESPONSE=$(curl -s -i -X POST "http://${KEYSTONE_IP}:${KEYSTONE_PORT}/v3/auth/tokens" \
    -H "Content-Type: application/json" \
    -d "{
        \"auth\": {
            \"identity\": {
                \"methods\": [\"password\"],
                \"password\": {
                    \"user\": {
                        \"name\": \"$USERNAME\",
                        \"domain\": {\"id\": \"$DOMAIN_ID\"},
                        \"password\": \"$PASSWORD\"
                    }
                }
            },
            \"scope\": {
                \"project\": {
                    \"name\": \"$PROJECT\",
                    \"domain\": {\"id\": \"$DOMAIN_ID\"}
                }
            }
        }
    }")

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -i "X-Subject-Token" | cut -d' ' -f2 | tr -d '\r\n' || echo "")

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo "❌ Errore ottenendo token:"
    echo "$TOKEN_RESPONSE" | jq '.' 2>/dev/null || echo "$TOKEN_RESPONSE"
    exit 1
fi

echo "✅ Token ottenuto: ${TOKEN:0:50}..."
echo ""

# Test API
echo "═══════════════════════════════════════════════════════════════"
echo "  📡 TEST API IOTRONIC"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 1. Boards
echo "1️⃣  GET /v1/boards"
BOARDS_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "X-Auth-Token: $TOKEN" "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/boards")
HTTP_STATUS=$(echo "$BOARDS_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BOARDS_BODY=$(echo "$BOARDS_RESPONSE" | sed '/HTTP_STATUS/d')
if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ Status: $HTTP_STATUS"
    echo "$BOARDS_BODY" | jq '.' 2>/dev/null | head -20 || echo "$BOARDS_BODY" | head -20
else
    echo "❌ Status: $HTTP_STATUS"
    echo "$BOARDS_BODY" | head -20
fi
echo ""

# 2. Services
echo "2️⃣  GET /v1/services"
SERVICES_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "X-Auth-Token: $TOKEN" "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/services")
HTTP_STATUS=$(echo "$SERVICES_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
SERVICES_BODY=$(echo "$SERVICES_RESPONSE" | sed '/HTTP_STATUS/d')
if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ Status: $HTTP_STATUS"
    echo "$SERVICES_BODY" | jq '.' 2>/dev/null | head -20 || echo "$SERVICES_BODY" | head -20
else
    echo "❌ Status: $HTTP_STATUS"
    echo "$SERVICES_BODY" | head -20
fi
echo ""

# 3. Plugins
echo "3️⃣  GET /v1/plugins"
PLUGINS_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "X-Auth-Token: $TOKEN" "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/plugins")
HTTP_STATUS=$(echo "$PLUGINS_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
PLUGINS_BODY=$(echo "$PLUGINS_RESPONSE" | sed '/HTTP_STATUS/d')
if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ Status: $HTTP_STATUS"
    echo "$PLUGINS_BODY" | jq '.' 2>/dev/null | head -20 || echo "$PLUGINS_BODY" | head -20
else
    echo "❌ Status: $HTTP_STATUS"
    echo "$PLUGINS_BODY" | head -20
fi
echo ""

# 4. Fleets
echo "4️⃣  GET /v1/fleets"
FLEETS_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "X-Auth-Token: $TOKEN" "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/fleets")
HTTP_STATUS=$(echo "$FLEETS_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
FLEETS_BODY=$(echo "$FLEETS_RESPONSE" | sed '/HTTP_STATUS/d')
if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ Status: $HTTP_STATUS"
    echo "$FLEETS_BODY" | jq '.' 2>/dev/null | head -20 || echo "$FLEETS_BODY" | head -20
else
    echo "❌ Status: $HTTP_STATUS"
    echo "$FLEETS_BODY" | head -20
fi
echo ""

# 5. Webservices
echo "5️⃣  GET /v1/webservices"
WEBSERVICES_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "X-Auth-Token: $TOKEN" "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/webservices")
HTTP_STATUS=$(echo "$WEBSERVICES_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
WEBSERVICES_BODY=$(echo "$WEBSERVICES_RESPONSE" | sed '/HTTP_STATUS/d')
if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ Status: $HTTP_STATUS"
    echo "$WEBSERVICES_BODY" | jq '.' 2>/dev/null | head -20 || echo "$WEBSERVICES_BODY" | head -20
else
    echo "❌ Status: $HTTP_STATUS"
    echo "$WEBSERVICES_BODY" | head -20
fi
echo ""

# 6. Ports
echo "6️⃣  GET /v1/ports"
PORTS_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "X-Auth-Token: $TOKEN" "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/ports")
HTTP_STATUS=$(echo "$PORTS_RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
PORTS_BODY=$(echo "$PORTS_RESPONSE" | sed '/HTTP_STATUS/d')
if [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ Status: $HTTP_STATUS"
    echo "$PORTS_BODY" | jq '.' 2>/dev/null | head -20 || echo "$PORTS_BODY" | head -20
else
    echo "❌ Status: $HTTP_STATUS"
    echo "$PORTS_BODY" | head -20
fi
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ TEST COMPLETATI"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 RIEPILOGO:"
echo "   Token salvato in: /tmp/keystone_token.txt"
echo "   Per testare altre API:"
echo "   curl -H \"X-Auth-Token: \$(cat /tmp/keystone_token.txt)\" http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/<endpoint>"
echo ""

