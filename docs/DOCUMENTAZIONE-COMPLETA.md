# Documentazione Completa Stack4Things + Crossplane

## Indice

1. [Architettura](#architettura)
2. [Deployment Dettagliato](#deployment-dettagliato)
3. [Flusso Completo End-to-End](#flusso-completo-end-to-end)
4. [Uso Crossplane](#uso-crossplane)
5. [Lightning Rod](#lightning-rod)
6. [Troubleshooting](#troubleshooting)
7. [Best Practices](#best-practices)
8. [Note Tecniche](#note-tecniche)

---

## Architettura

### Componenti Principali

#### Stack4Things
- **IoTronic Conductor**: API REST principale
- **Keystone**: Autenticazione e autorizzazione
- **Crossbar**: WAMP router per comunicazione real-time
- **Lightning Rod**: Agent lato board
- **Horizon**: Dashboard web

#### Crossplane Provider
- **Provider Stack4Things**: CRD per gestione dichiarativa
- **CRD Disponibili**:
  - `Device` (Board)
  - `Plugin`
  - `Service`
  - `Webservice`
  - `BoardPluginInjection`
  - `BoardServiceInjection`
  - `Fleet`
  - `Site`
  - `Port`

### Flusso Dati

```
Crossplane CRD → Provider Controller → IoTronic API → Stack4Things
                ↓
         Lightning Rod ← Crossbar (WAMP)
```

---

## Deployment Dettagliato

### Preparazione Ambiente

**Step 1: Verifica Prerequisiti**

```bash
# Verifica k3s
kubectl cluster-info
kubectl get nodes

# Verifica Docker
docker --version

# Verifica Make
make --version

# Verifica jq
jq --version
```

**Cosa verifica**: Che tutti gli strumenti necessari siano installati.

### Deployment Stack4Things

**Step 1: Applicazione Manifest**

```bash
cd /home/ubuntu/s4t-crossplane-deployment/stack4things
kubectl apply -f yaml_file/
```

**Cosa viene deployato**:
1. **CA Service**: Container Debian che genera certificati SSL
   - Crea Root CA (iotronic_CA.key/pem)
   - Crea certificato Crossbar (crossbar.key/pem)
   - Monta PVC `iotronic-ssl` per persistenza

2. **Crossbar**: Router WAMP per comunicazione real-time
   - In ascolto su porta 8181 (WSS/TLS)
   - Attende certificati dal CA Service
   - Realm: "s4t"

3. **Keystone**: Servizio di autenticazione OpenStack
   - Porta 5000
   - Database MySQL interno
   - Credenziali default: admin/s4t/admin

4. **IoTronic Conductor**: API REST principale
   - Porta 8812
   - Gestisce board, plugin, servizi
   - Si autentica con Keystone

5. **IoTronic Database**: MySQL
   - Persistenza dati
   - Usato da Keystone e IoTronic

6. **IoTronic UI**: Dashboard Horizon
   - Porta 80
   - Interfaccia web per gestione

7. **IoTronic WAgent**: Worker agent
   - Gestisce task asincroni

8. **IoTronic WSTun**: WebSocket tunnel
   - Tunnel per comunicazione board

**Step 2: Attesa Avvio**

```bash
# Attendi 60-90 secondi
sleep 60

# Verifica pod
kubectl get pods -n default | grep -E "(iotronic|keystone|crossbar|ca-service)"
```

**Cosa aspettarsi**: Tutti i pod in stato `Running`.

**Step 3: Verifica Certificati**

```bash
CA_POD=$(kubectl get pod -n default | grep ca-service | awk '{print $1}' | head -1)
kubectl exec -n default "$CA_POD" -- ls -la /etc/ssl/iotronic/
```

**Output atteso**: 4 file (iotronic_CA.key, iotronic_CA.pem, crossbar.key, crossbar.pem)

**Se mancanti**: Il CA Service potrebbe usare `debian:buster` (EOL). Aggiornare a `debian:bookworm`:
```bash
kubectl get deployment ca-service -n default -o yaml | sed 's/debian:buster/debian:bookworm/g' | kubectl apply -f -
kubectl delete pod -n default -l app=ca-service
```

**Step 4: Verifica Crossbar**

```bash
CROSSBAR_POD=$(kubectl get pod -n default | grep crossbar | awk '{print $1}' | head -1)
kubectl logs -n default "$CROSSBAR_POD" | grep -E "(listening|8181|started)"
```

**Output atteso**: `Router TCP/8181 transport started` o `listening on TCP port 8181`

**Se non funziona**: Verificare certificati e log per errori.

### Deployment Crossplane

**Step 1: Build Provider (opzionale, se modifiche)**

```bash
cd /home/ubuntu/s4t-crossplane-deployment/crossplane-provider
make build
```

**Cosa fa**: Compila il provider Go in `_output/bin/linux_amd64/provider`.

**Step 2: Deploy Provider**

```bash
cd /home/ubuntu/s4t-crossplane-deployment/crossplane-provider
kubectl apply -f cluster/
```

**Cosa viene deployato**:
1. **Provider Resource**: Risorsa Kubernetes che punta all'immagine Docker
2. **ProviderRevision**: Revisione del provider
3. **CRD**: 11 Custom Resource Definitions
4. **RBAC**: ClusterRole e ClusterRoleBinding

**Step 3: Attesa Installazione**

```bash
# Attendi 30-60 secondi
sleep 30

# Verifica provider
kubectl get provider -n default | grep s4t

# Verifica CRD
kubectl get crd | grep "iot.s4t.crossplane.io"
```

**Output atteso**: Provider in stato `HEALTHY` e 11 CRD disponibili.

**Step 4: Configurazione ProviderConfig**

Il ProviderConfig deve essere configurato con:
- Endpoint Keystone
- Credenziali (secret)

**Verifica**:
```bash
kubectl get providerconfig s4t-provider-domain -n default
kubectl get secret s4t-credentials -n default
```

---

## Flusso Completo End-to-End

### 1. Creazione Board via Crossplane

**Cosa succede**:
1. Utente applica YAML Device
2. Crossplane crea risorsa Device
3. Provider controller rileva la risorsa
4. Controller chiama API IoTronic: `POST /v1/boards`
5. IoTronic crea board e restituisce UUID
6. Controller aggiorna status Device con UUID
7. Device diventa `Ready: True`

**Tempo**: 30-60 secondi

### 2. Creazione Lightning Rod

**Cosa succede**:
1. Script crea Deployment Kubernetes
2. Deployment monta `settings.json` con `board_code`
3. Pod Lightning Rod si avvia
4. Lightning Rod legge `settings.json`
5. Lightning Rod tenta connessione WSS a Crossbar

**Tempo**: 30 secondi per avvio pod

### 3. Connessione Lightning Rod

**Cosa succede**:
1. Lightning Rod si connette a Crossbar via WSS
2. Crossbar autentica la connessione
3. Lightning Rod registra il `board_code`
4. IoTronic riconosce la board
5. IoTronic completa `settings.json` con UUID
6. Lightning Rod riceve configurazione completa
7. Board diventa "online" con agent e session attivi

**Tempo**: 5-10 minuti

### 4. Creazione Plugin via Crossplane

**Cosa succede**:
1. Utente applica YAML Plugin
2. Crossplane crea risorsa Plugin
3. Provider controller rileva la risorsa
4. Controller chiama API IoTronic: `POST /v1/plugins`
5. IoTronic crea plugin e restituisce UUID
6. Controller aggiorna status Plugin con UUID
7. Plugin diventa `Ready: True`

**Tempo**: 30-60 secondi

### 5. Iniezione Plugin su Board

**Cosa succede**:
1. Utente applica YAML BoardPluginInjection
2. Crossplane crea risorsa Injection
3. Provider controller rileva la risorsa
4. Controller verifica che board sia online
5. Controller chiama API IoTronic: `POST /v1/boards/{id}/plugins`
6. IoTronic inietta plugin su Lightning Rod
7. Lightning Rod esegue il plugin
8. Injection diventa `Ready: True`

**Tempo**: 10-30 secondi (se board online)

---

## Uso Crossplane

### CRD Disponibili

#### Device (Board)
```yaml
apiVersion: iot.s4t.crossplane.io/v1alpha1
kind: Device
metadata:
  name: my-device
spec:
  forProvider:
    name: "Device Name"
    code: "DEVICE-001"
    type: "virtual"  # o "gateway", "sensor", ecc.
    location:
      - latitude: "45.0"
        longitude: "9.0"
        altitude: "100"
  providerConfigRef:
    name: s4t-provider-domain
```

#### Plugin
```yaml
apiVersion: iot.s4t.crossplane.io/v1alpha1
kind: Plugin
metadata:
  name: my-plugin
spec:
  forProvider:
    name: "Plugin Name"
    code: |
      # Codice plugin Python
    parameters:
      key: "value"
  providerConfigRef:
    name: s4t-provider-domain
```

#### Service
```yaml
apiVersion: iot.s4t.crossplane.io/v1alpha1
kind: Service
metadata:
  name: my-service
spec:
  forProvider:
    name: "Service Name"
    port: 5000
    protocol: "TCP"  # o "UDP"
  providerConfigRef:
    name: s4t-provider-domain
```

#### BoardPluginInjection
```yaml
apiVersion: iot.s4t.crossplane.io/v1alpha1
kind: BoardPluginInjection
metadata:
  name: my-injection
spec:
  forProvider:
    boardUuid: "<board-uuid>"
    pluginUuid: "<plugin-uuid>"
  providerConfigRef:
    name: s4t-provider-domain
```

### Esempi Completi

Vedi `/home/ubuntu/s4t-crossplane-deployment/crossplane-provider/examples/` per esempi completi.

---

## Lightning Rod

### Configurazione

Il file `settings.json` viene creato automaticamente con:

```json
{
  "iotronic": {
    "board": {
      "code": "BOARD-001"
    },
    "wamp": {
      "registration-agent": {
        "url": "wss://crossbar:8181/",
        "realm": "s4t"
      }
    }
  }
}
```

### Creazione Manuale

```bash
BOARD_CODE="BOARD-001"
./scripts/create-lightning-rod-for-board.sh "$BOARD_CODE"
```

### Verifica Connessione

```bash
# Log Lightning Rod
BOARD_CODE="BOARD-001"
kubectl logs -n default -l board-code="$BOARD_CODE" -f

# Verifica connettività
POD_NAME=$(kubectl get pod -n default -l board-code="$BOARD_CODE" -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default "$POD_NAME" -- python3 -c "import socket; s = socket.socket(); s.settimeout(2); result = s.connect_ex(('crossbar', 8181)); print('OK' if result == 0 else 'FAIL'); s.close()"
```

### Flusso Connessione

1. **Prima connessione**: Lightning Rod si connette a Crossbar usando `board_code`
2. **Registrazione**: Il cloud registra la board e completa `settings.json` con UUID
3. **Board Online**: La board diventa "online" con agent e session attivi
4. **Pronta per injection**: Plugin e servizi possono essere iniettati

---

## Troubleshooting

### Problema: Crossbar non avvia

**Sintomi**: Crossbar in attesa certificati SSL

**Diagnosi**:
```bash
# Verifica CA Service
kubectl get pod -n default | grep ca-service
kubectl logs -n default -l app=ca-service | tail -20
```

**Soluzione**:
```bash
# Aggiorna immagine CA Service a debian:bookworm
kubectl get deployment ca-service -n default -o yaml | \
  sed 's/debian:buster/debian:bookworm/g' | \
  kubectl apply -f -

# Riavvia pod
kubectl delete pod -n default -l app=ca-service

# Attendi generazione certificati (30 secondi)
sleep 30

# Verifica certificati
CA_POD=$(kubectl get pod -n default | grep ca-service | awk '{print $1}' | head -1)
kubectl exec -n default "$CA_POD" -- ls -la /etc/ssl/iotronic/
```

### Problema: Lightning Rod non si connette

**Sintomi**: "Connection refused" o "FIRST BOOT: waiting for first configuration..."

**Diagnosi**:
```bash
# Verifica Crossbar
CROSSBAR_POD=$(kubectl get pod -n default | grep crossbar | awk '{print $1}' | head -1)
kubectl logs -n default "$CROSSBAR_POD" | grep -E "(listening|8181|error)"

# Verifica connettività
BOARD_CODE="<BOARD_CODE>"
POD_NAME=$(kubectl get pod -n default -l board-code="$BOARD_CODE" -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default "$POD_NAME" -- python3 -c "import socket; s = socket.socket(); s.settimeout(2); result = s.connect_ex(('crossbar', 8181)); print('OK' if result == 0 else 'FAIL'); s.close()"
```

**Soluzione**:
1. Verifica Crossbar funzionante (vedi sopra)
2. Verifica settings.json:
   ```bash
   kubectl exec -n default "$POD_NAME" -- cat /var/lib/iotronic/settings.json | jq '.'
   ```
3. Attendi: La connessione richiede 5-10 minuti (normale)

### Problema: Board non diventa online

**Sintomi**: Board rimane in stato "registered"

**Diagnosi**:
```bash
# Verifica Lightning Rod connesso
BOARD_CODE="<BOARD_CODE>"
kubectl logs -n default -l board-code="$BOARD_CODE" | grep -iE "(connected|session|registered|online)"

# Verifica agent e session
TOKEN=$(./scripts/test-s4t-apis.sh admin s4t admin | grep "Token ottenuto" | cut -d: -f2 | tr -d ' ')
BOARD_UUID="<board-uuid>"
curl -H "X-Auth-Token: $TOKEN" \
  http://$(kubectl get svc iotronic-conductor -o jsonpath='{.spec.clusterIP}'):8812/v1/boards/$BOARD_UUID | \
  jq '{status, agent, session}'
```

**Soluzione**:
1. Verifica Lightning Rod connesso (vedi sopra)
2. Attendi connessione completa (5-10 minuti)
3. Verifica che agent e session siano attivi

### Problema: Plugin injection fallisce

**Sintomi**: "Board is not connected" o "Board is not online"

**Diagnosi**:
```bash
# Verifica board online
BOARD_UUID="<board-uuid>"
TOKEN=$(./scripts/test-s4t-apis.sh admin s4t admin | grep "Token ottenuto" | cut -d: -f2 | tr -d ' ')
STATUS=$(curl -s -H "X-Auth-Token: $TOKEN" \
  http://$(kubectl get svc iotronic-conductor -o jsonpath='{.spec.clusterIP}'):8812/v1/boards/$BOARD_UUID | \
  jq -r '.status // .board.status')

echo "Board status: $STATUS"
```

**Soluzione**:
1. Verifica board online (status deve essere "online")
2. Attendi connessione completa (5-10 minuti)
3. Riprova injection dopo che board è online

### Problema: Provider Crossplane non funziona

**Sintomi**: CRD non riconosciuti o errori 401/403

**Diagnosi**:
```bash
# Verifica provider installato
kubectl get provider -n default | grep s4t

# Verifica ProviderConfig
kubectl get providerconfig s4t-provider-domain -n default

# Verifica credenziali
kubectl get secret s4t-credentials -n default -o yaml

# Verifica log provider
PROVIDER_POD=$(kubectl get pod -n crossplane-system | grep provider-s4t | awk '{print $1}' | head -1)
kubectl logs -n crossplane-system "$PROVIDER_POD" | tail -50
```

**Soluzione**:
1. Verifica provider installato
2. Verifica ProviderConfig configurato correttamente
3. Verifica credenziali nel secret
4. Verifica log per errori di autenticazione

---

## Best Practices

### 1. Naming Convention

- **Board Code**: Usa prefissi significativi (es. `PROD-BOARD-001`, `TEST-BOARD-001`)
- **Plugin Name**: Nomi descrittivi (es. `temperature-monitor`, `data-collector`)
- **Service Name**: Indica protocollo (es. `mqtt-service`, `http-service`)

### 2. Gestione Risorse

- Usa `deletionPolicy: Delete` per risorse di test
- Usa `deletionPolicy: Orphan` per risorse di produzione
- Mantieni traccia degli UUID per injection

### 3. Monitoraggio

- Monitora log Lightning Rod durante connessione
- Verifica stato board prima di injection
- Usa script di test end-to-end per validazione

### 4. Sicurezza

- Proteggi credenziali Keystone
- Usa namespace separati per ambienti
- Limita accesso a Crossplane Provider

### 5. Deployment

- Usa script deployment completo per setup iniziale
- Documenta configurazioni personalizzate
- Mantieni backup di configurazioni importanti

---

## Note Tecniche

### CRD Lightning Rod

Attualmente **non esiste un CRD per Lightning Rod** nel provider Crossplane. Lightning Rod viene creato manualmente usando lo script `create-lightning-rod-for-board.sh`.

**Workaround attuale:**
```bash
BOARD_CODE=$(kubectl get device my-board -o jsonpath='{.spec.forProvider.code}')
./scripts/create-lightning-rod-for-board.sh "$BOARD_CODE"
```

**Possibile implementazione futura:**
Un CRD Lightning Rod permetterebbe gestione dichiarativa completa, ma richiede modifiche al provider Crossplane. Per ora, lo script è sufficiente per la maggior parte dei casi d'uso.

### Flusso settings.json

Il file `settings.json` viene inizializzato con solo il `board_code`:
```json
{
  "iotronic": {
    "board": {
      "code": "BOARD-001"
    },
    "wamp": {
      "registration-agent": {
        "url": "wss://crossbar:8181/",
        "realm": "s4t"
      }
    }
  }
}
```

Dopo la prima connessione, il cloud completa automaticamente con:
- UUID della board
- UUID dell'agent
- Configurazione completa

Il warning `settings.json file exception: 'uuid'` durante il primo avvio è normale e atteso.

### Tempi di Attesa

- **Deployment Stack4Things**: 60-90 secondi
- **Deployment Crossplane**: 30-60 secondi
- **Creazione risorse Crossplane**: 30-60 secondi
- **Connessione Lightning Rod**: 5-10 minuti
- **Board diventa online**: Dopo connessione Lightning Rod

---

## Riferimenti

- [Stack4Things Documentation](https://github.com/stack4things)
- [Crossplane Documentation](https://crossplane.io/docs)
- [Esempi Crossplane](./crossplane-provider/examples/)
- [Script Deployment](./scripts/deploy-complete-s4t.sh)
- [Script Test End-to-End](./scripts/test-end-to-end.sh)

---

## Supporto

Per problemi o domande:
1. Consulta [Troubleshooting](#troubleshooting)
2. Verifica log componenti
3. Controlla documentazione Stack4Things
4. Apri issue su repository
