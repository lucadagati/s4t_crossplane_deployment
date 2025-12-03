#!/bin/bash

set -e

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=========================================="
echo "  CREAZIONE LIGHTNING ROD PER BOARD"
echo "=========================================="
echo ""

if [ -z "$1" ]; then
    echo "Usage: $0 <BOARD_CODE>"
    echo ""
    echo "Esempio:"
    echo "  $0 TEST-VB-1764688392"
    echo ""
    echo "Oppure ottieni il codice dalla board:"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TOKEN=$(bash "$SCRIPT_DIR/test-s4t-apis.sh" admin s4t admin 2>&1 | grep "Token ottenuto" | cut -d: -f2 | tr -d ' ')
    IOTRONIC_IP=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.clusterIP}')
    echo ""
    echo "Board disponibili:"
    curl -s -H "X-Auth-Token: $TOKEN" "http://${IOTRONIC_IP}:8812/v1/boards" | jq -r '.boards[] | "  \(.code) - \(.name) (status: \(.status))"' 2>/dev/null || echo "  Nessuna board trovata"
    exit 1
fi

BOARD_CODE="$1"

echo "Board code: $BOARD_CODE"
echo ""

# Verifica che la board esista (opzionale - serve solo per validazione)
# Il board_code è sufficiente per la configurazione iniziale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN=$(bash "$SCRIPT_DIR/test-s4t-apis.sh" admin s4t admin 2>&1 | grep "Token ottenuto" | cut -d: -f2 | tr -d ' ')
IOTRONIC_IP=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.clusterIP}')
IOTRONIC_PORT=$(kubectl get svc iotronic-conductor -n default -o jsonpath='{.spec.ports[0].port}')

# Prova a cercare la board per validazione (opzionale)
BOARD_INFO=$(curl -s -H "X-Auth-Token: $TOKEN" \
    "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/boards" 2>/dev/null | \
    jq ".boards[] | select(.code == \"$BOARD_CODE\")" 2>/dev/null || echo "")

if [ -n "$BOARD_INFO" ] && [ "$BOARD_INFO" != "null" ] && [ "$BOARD_INFO" != "" ]; then
    BOARD_UUID=$(echo "$BOARD_INFO" | jq -r '.uuid')
    BOARD_NAME=$(echo "$BOARD_INFO" | jq -r '.name')
    BOARD_STATUS=$(echo "$BOARD_INFO" | jq -r '.status')
    
    echo "Board trovata nel cloud:"
    echo "  Code: $BOARD_CODE"
    echo "  UUID: $BOARD_UUID"
    echo "  Nome: $BOARD_NAME"
    echo "  Status: $BOARD_STATUS"
    echo ""
    echo "NOTA: Lightning Rod userà il board_code per connettersi."
    echo "      Il cloud completerà automaticamente settings.json alla prima connessione."
    echo ""
else
    echo "ATTENZIONE: Board con codice '$BOARD_CODE' non trovata nell'API"
    echo "Lightning Rod proverà comunque a connettersi usando questo codice."
    echo "Assicurati che la board esista nel cloud prima di avviare Lightning Rod."
    echo ""
fi

# Crea il deployment per Lightning Rod
DEPLOYMENT_NAME="lightning-rod-$(echo "$BOARD_CODE" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | sed 's/[^a-z0-9-]//g')"

echo "Creazione deployment: $DEPLOYMENT_NAME"
echo ""

# Genera il YAML del deployment
cat > /tmp/lightning-rod-${BOARD_CODE}.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  labels:
    app: lightning-rod
    board-code: "${BOARD_CODE}"
    board-type: virtual
spec:
  replicas: 1
  selector:
    matchLabels:
      app: lightning-rod
      board-code: "${BOARD_CODE}"
  template:
    metadata:
      labels:
        app: lightning-rod
        board-code: "${BOARD_CODE}"
        board-type: virtual
    spec:
      containers:
        - name: lightning-rod
          image: lucadagati/lrod:compose
          ports:
            - containerPort: 1474
              protocol: TCP
          securityContext:
            privileged: true
          stdin: true
          tty: true
          env:
            - name: BOARD_CODE
              value: "${BOARD_CODE}"
            - name: WAMP_URL
              value: "wss://crossbar:8181/"
            - name: WAMP_REALM
              value: "s4t"
            - name: IOTRONIC_URL
              value: "http://iotronic-conductor:8812"
            - name: KEYSTONE_URL
              value: "http://keystone:5000/v3"
          args:
            - |
              mkdir -p /var/lib/iotronic
              # Crea settings.json con solo il board_code
              # Il cloud completerà automaticamente il file alla prima connessione
              # con UUID e altri dati necessari
              cat > /var/lib/iotronic/settings.json <<SETTINGS_EOF
              {
                  "iotronic": {
                      "board": {
                          "code": "${BOARD_CODE}"
                      },
                      "wamp": {
                          "registration-agent": {
                              "url": "wss://crossbar:8181/",
                              "realm": "s4t"
                          }
                      }
                  }
              }
              SETTINGS_EOF
              chmod 644 /var/lib/iotronic/settings.json
              # Fix per wstun_ip (come nella versione docker-compose)
              sed -i 's|self\.wstun_ip *= *urlparse(board\.wamp_config\["url"\])\[1\]\.split('\'':'\'')\[0\]|self.wstun_ip = "iotronic-wstun"|' /usr/local/lib/python3*/site-packages/iotronic_lightningrod/modules/service_manager.py
              exec startLR
          command:
            - /bin/sh
            - -c
      restartPolicy: Always
EOF

# Applica il deployment
kubectl apply -f /tmp/lightning-rod-${BOARD_CODE}.yaml

echo ""
echo "Deployment creato. Attesa che il pod sia Ready..."
kubectl wait --for=condition=Ready pod -n default -l board-code="${BOARD_CODE}" --timeout=120s 2>&1 || true

echo ""
echo "=========================================="
echo "  VERIFICA"
echo "=========================================="
echo ""

sleep 5

# Verifica lo stato della board
BOARD_STATUS_NEW=$(curl -s -H "X-Auth-Token: $TOKEN" \
    "http://${IOTRONIC_IP}:${IOTRONIC_PORT}/v1/boards/$BOARD_UUID" | \
    jq '{uuid, code, status, type, agent, session}' 2>/dev/null)

echo "Stato board:"
echo "$BOARD_STATUS_NEW" | jq '.'
echo ""

# Mostra i log di Lightning Rod
POD_NAME=$(kubectl get pod -n default -l board-code="${BOARD_CODE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD_NAME" ]; then
    echo "Log Lightning Rod (ultime 20 righe):"
    kubectl logs -n default "$POD_NAME" --tail=20 2>&1 | tail -20
    echo ""
    echo "Per vedere tutti i log:"
    echo "  kubectl logs -n default $POD_NAME -f"
fi

echo ""
echo "=========================================="
echo "  COMPLETATO"
echo "=========================================="
echo ""
echo "Lightning Rod creato per board: $BOARD_CODE"
echo ""
echo "Comandi utili:"
echo "  kubectl get pod -n default -l board-code=${BOARD_CODE}"
echo "  kubectl logs -n default -l board-code=${BOARD_CODE} -f"
echo "  kubectl delete deployment ${DEPLOYMENT_NAME}"
echo ""

