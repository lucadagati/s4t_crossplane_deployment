# Esempi Provider Crossplane S4T

Questa directory contiene esempi per tutte le risorse gestite dal provider Crossplane S4T.

## 📋 Risorse Disponibili

### Risorse Core

1. **Device (Board)** - Gestione dispositivi IoT
   - `device-example.yaml` - Esempio base
   - `device-with-site.yaml` - Device associato a un sito

2. **Service** - Gestione servizi
   - `service-example.yaml` - Esempio base

3. **Plugin** - Gestione plugin
   - `plugin-example.yaml` - Esempio base

4. **BoardPluginInjection** - Iniezione plugin su board
   - `boardplugininjection-example.yaml` - Esempio base

5. **BoardServiceInjection** - Esposizione servizi su board
   - `boardserviceinjection-example.yaml` - Esempio base

### Nuove Risorse (⭐)

6. **Fleet** - Gestione flotte di dispositivi
   - `fleet/fleet-example.yaml` - Esempio base

7. **Webservice** - Gestione webservices su board
   - `webservice/webservice-example.yaml` - Esempio base

8. **Port** - Gestione porte di rete
   - `port/port-example.yaml` - Esempio base

9. **Result** - Risultati operazioni (read-only)
   - `result/result-example.yaml` - Esempio osservazione

10. **Request** - Richieste asincrone
    - `request/request-example.yaml` - Esempio base

11. **Site** - Gestione siti (multisite)
    - `multisite/site-example.yaml` - Esempio base

## 🚀 Utilizzo

### Prerequisiti

1. Provider S4T installato e configurato
2. ProviderConfig creato (vedi `multisite/providerconfig.yaml`)
3. Secret con credenziali Stack4Things (vedi `multisite/test-credentials.yaml`)

### Applicare Esempi

```bash
# Applicare un esempio
kubectl apply -f examples/fleet/fleet-example.yaml

# Verificare stato
kubectl get fleet

# Verificare dettagli
kubectl describe fleet production-fleet
```

### Modificare Esempi

Prima di applicare gli esempi, assicurarsi di:

1. Sostituire `board-uuid-here` con UUID reali di board esistenti
2. Sostituire `service-uuid-here` con UUID reali di servizi esistenti
3. Verificare che il `providerConfigRef.name` corrisponda al ProviderConfig configurato

## 📝 Note

- **Result**: È una risorsa read-only. Non può essere creata manualmente, solo osservata.
- **Request**: Le richieste vengono processate in modo asincrono. Verificare lo stato tramite `kubectl get request`.
- **Port**: Le porte vengono create tramite endpoint board-specific. Assicurarsi che il board sia online.
- **Webservice**: Richiede che il board sia online e configurato correttamente.

## 🔗 Riferimenti

- [Documentazione Provider](../README.md)
- [API Reference](../docs/api-reference.md)

