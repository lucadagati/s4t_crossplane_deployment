# Esempi Avanzati Crossplane Stack4Things

Questa directory contiene esempi avanzati e scenari d'uso completi per il provider Crossplane Stack4Things.

## 📚 Indice

1. [Plugin Injection Workflow](#plugin-injection-workflow)
2. [Webservice Deployment](#webservice-deployment)
3. [Service Injection Pattern](#service-injection-pattern)
4. [Multi-Resource Deployment](#multi-resource-deployment)

---

## 🔌 Plugin Injection Workflow

### Scenario: Iniettare un Plugin su un Board

Questo workflow mostra come:
1. Creare un Plugin
2. Verificare che il Board sia online
3. Iniettare il Plugin sul Board
4. Monitorare lo stato dell'injection

### File:
- `01-plugin-creation.yaml` - Crea un nuovo plugin
- `02-board-plugin-injection.yaml` - Inietta il plugin su un board
- `03-plugin-injection-with-dependencies.yaml` - Esempio con dipendenze

### Utilizzo:

```bash
# 1. Creare il plugin
kubectl apply -f examples/advanced/01-plugin-creation.yaml

# 2. Verificare che il plugin sia pronto
kubectl get plugin temperature-monitor -o yaml

# 3. Iniettare il plugin su un board (sostituire BOARD_UUID)
kubectl apply -f examples/advanced/02-board-plugin-injection.yaml

# 4. Verificare lo stato dell'injection
kubectl get boardplugininjection temp-monitor-injection -o yaml
```

---

## 🌐 Webservice Deployment

### Scenario: Esporre un Webservice su un Board

Questo workflow mostra come:
1. Creare un webservice con configurazione completa
2. Gestire webservice sicuri (HTTPS)
3. Configurare metadati aggiuntivi
4. Aggiornare un webservice esistente

### File:
- `04-webservice-basic.yaml` - Webservice base
- `05-webservice-secure.yaml` - Webservice HTTPS
- `06-webservice-with-extra.yaml` - Webservice con metadati

### Utilizzo:

```bash
# Creare un webservice base
kubectl apply -f examples/advanced/04-webservice-basic.yaml

# Creare un webservice sicuro
kubectl apply -f examples/advanced/05-webservice-secure.yaml

# Verificare lo stato
kubectl get webservice -o wide
```

---

## 🔧 Service Injection Pattern

### Scenario: Esporre un Service su un Board

Questo workflow mostra come:
1. Creare un Service
2. Iniettare il Service su un Board
3. Gestire multiple injection dello stesso service

### File:
- `07-service-creation.yaml` - Crea un service
- `08-board-service-injection.yaml` - Inietta il service su un board
- `09-multi-board-service-injection.yaml` - Inietta lo stesso service su più board

### Utilizzo:

```bash
# 1. Creare il service
kubectl apply -f examples/advanced/07-service-creation.yaml

# 2. Iniettare su un board
kubectl apply -f examples/advanced/08-board-service-injection.yaml

# 3. Verificare
kubectl get boardserviceinjection -o wide
```

---

## 🏗️ Multi-Resource Deployment

### Scenario: Deployment Completo di un'Applicazione IoT

Questo esempio mostra un deployment completo che include:
1. Plugin per monitoraggio
2. Service per comunicazione
3. Webservice per API esterna
4. Injection su board specifici

### File:
- `10-complete-iot-deployment.yaml` - Deployment completo con tutte le risorse

### Utilizzo:

```bash
# Applicare il deployment completo
kubectl apply -f examples/advanced/10-complete-iot-deployment.yaml

# Monitorare tutte le risorse
kubectl get plugin,service,webservice,boardplugininjection,boardserviceinjection

# Verificare lo stato di sincronizzazione
kubectl get plugin,service,webservice,boardplugininjection,boardserviceinjection -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}: Ready={.status.conditions[?(@.type=="Ready")].status} Synced={.status.conditions[?(@.type=="Synced")].status}{"\n"}{end}'
```

---

## 📝 Note Importanti

### Prerequisiti

Prima di applicare gli esempi, assicurarsi di:

1. **ProviderConfig configurato:**
   ```bash
   kubectl get providerconfig s4t-provider-domain
   ```

2. **Board online:**
   ```bash
   # Verificare che il board sia online in Stack4Things
   # Gli UUID dei board devono essere reali e i board devono essere online
   ```

3. **Credenziali valide:**
   ```bash
   kubectl get secret s4t-credentials -o jsonpath='{.data.credentials}' | base64 -d
   ```

### Sostituire Placeholder

Tutti gli esempi contengono placeholder che devono essere sostituiti:

- `BOARD_UUID_HERE` → UUID reale di un board online
- `PLUGIN_UUID_HERE` → UUID di un plugin esistente (o lasciare vuoto per creazione)
- `SERVICE_UUID_HERE` → UUID di un service esistente (o lasciare vuoto per creazione)

### Best Practices

1. **Ordine di Deployment:**
   - Prima creare Plugin/Service
   - Poi creare Injection/Webservice
   - Infine verificare lo stato

2. **Gestione Errori:**
   ```bash
   # Verificare eventi per errori
   kubectl describe plugin <name>
   kubectl describe boardplugininjection <name>
   
   # Verificare log del provider
   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=s4t-iot
   ```

3. **Cleanup:**
   ```bash
   # Eliminare tutte le risorse
   kubectl delete -f examples/advanced/10-complete-iot-deployment.yaml
   ```

---

## 🔗 Riferimenti

- [Documentazione Provider](../../README.md)
- [Esempi Base](../README.md)
- [API Reference](../../docs/api-reference.md)

