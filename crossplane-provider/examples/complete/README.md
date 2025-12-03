# Esempio Completo End-to-End

Questo esempio mostra il flusso completo dalla creazione della board all'iniezione di plugin e servizi.

## 📋 Componenti

1. **Device (Board)**: Board virtuale
2. **Plugin**: Plugin Python con parametri
3. **Service**: Servizio TCP
4. **BoardPluginInjection**: Iniezione plugin su board
5. **BoardServiceInjection**: Iniezione servizio su board

## 🚀 Utilizzo

### Passo 1: Crea Device, Plugin e Service

```bash
kubectl apply -f end-to-end-example.yaml
```

### Passo 2: Crea Lightning Rod per la Board

```bash
BOARD_CODE=$(kubectl get device complete-example-board -o jsonpath='{.spec.forProvider.code}')
/home/ubuntu/create-lightning-rod-for-board.sh "$BOARD_CODE"
```

### Passo 3: Attendi Connessione (5-10 minuti)

```bash
# Monitora log Lightning Rod
kubectl logs -n default -l board-code="$BOARD_CODE" -f

# Verifica stato board
TOKEN=$(/home/ubuntu/test-s4t-apis.sh admin s4t admin | grep "Token ottenuto" | cut -d: -f2 | tr -d ' ')
BOARD_UUID=$(kubectl get device complete-example-board -o jsonpath='{.status.atProvider.uuid}')
curl -H "X-Auth-Token: $TOKEN" \
  http://$(kubectl get svc iotronic-conductor -o jsonpath='{.spec.clusterIP}'):8812/v1/boards/$BOARD_UUID | \
  jq '{code, status, agent, session}'
```

### Passo 4: Ottieni UUID e Applica Injection

```bash
# Ottieni UUID
BOARD_UUID=$(kubectl get device complete-example-board -o jsonpath='{.status.atProvider.uuid}')
PLUGIN_UUID=$(kubectl get plugin complete-example-plugin -o jsonpath='{.status.atProvider.uuid}')
SERVICE_UUID=$(kubectl get service complete-example-service -o jsonpath='{.status.atProvider.uuid}')

# Verifica che board sia online
TOKEN=$(/home/ubuntu/test-s4t-apis.sh admin s4t admin | grep "Token ottenuto" | cut -d: -f2 | tr -d ' ')
BOARD_STATUS=$(curl -s -H "X-Auth-Token: $TOKEN" \
  http://$(kubectl get svc iotronic-conductor -o jsonpath='{.spec.clusterIP}'):8812/v1/boards/$BOARD_UUID | \
  jq -r '.status // .board.status')

if [ "$BOARD_STATUS" == "online" ]; then
    # Sostituisci UUID nel file
    sed -i "s/<BOARD_UUID>/$BOARD_UUID/" end-to-end-example.yaml
    sed -i "s/<PLUGIN_UUID>/$PLUGIN_UUID/" end-to-end-example.yaml
    sed -i "s/<SERVICE_UUID>/$SERVICE_UUID/" end-to-end-example.yaml
    
    # Applica injection
    kubectl apply -f end-to-end-example.yaml
else
    echo "Board non ancora online. Attendi connessione Lightning Rod."
fi
```

### Passo 5: Verifica Injection

```bash
# Verifica plugin injection
kubectl get boardplugininjection complete-example-plugin-injection

# Verifica service injection
kubectl get boardserviceinjection complete-example-service-injection

# Verifica log plugin
BOARD_CODE=$(kubectl get device complete-example-board -o jsonpath='{.spec.forProvider.code}')
kubectl logs -n default -l board-code="$BOARD_CODE" | grep -i plugin
```

## 🧹 Cleanup

```bash
kubectl delete -f end-to-end-example.yaml
```

## 📝 Note

- La board deve essere **online** prima di applicare injection
- La connessione Lightning Rod richiede **5-10 minuti**
- Verifica sempre lo stato della board prima di injection
- Gli UUID sono disponibili dopo la creazione delle risorse

## 🔍 Troubleshooting

### Board non diventa online

1. Verifica Lightning Rod connesso:
   ```bash
   kubectl logs -n default -l board-code="$BOARD_CODE" | grep -i "connected\|session"
   ```

2. Verifica Crossbar funzionante:
   ```bash
   kubectl logs -n default -l app=crossbar | grep "listening\|8181"
   ```

### Injection fallisce

1. Verifica board online:
   ```bash
   kubectl get device complete-example-board -o jsonpath='{.status.atProvider.uuid}'
   # Verifica via API
   ```

2. Verifica UUID corretti:
   ```bash
   kubectl get device complete-example-board -o jsonpath='{.status.atProvider.uuid}'
   kubectl get plugin complete-example-plugin -o jsonpath='{.status.atProvider.uuid}'
   ```

