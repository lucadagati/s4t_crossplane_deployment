# Integrazione Federazione Keystone-Keycloak

Questo documento riassume tutte le operazioni, i fix e le integrazioni effettuate per configurare e testare la federazione tra Keystone e Keycloak, partendo dal deployment iniziale.

## 1. Deploy Iniziale

Per avviare l'infrastruttura, il primo step è lanciare il file di deploy automatico:

```bash
./stack4thing-improved/deploy-complete-improved.sh
```

## 2. Configurazione Iniziale e Isolamento
- **Namespace Isolati:** Creazione di namespace separati e isolati per Keycloak e Keystone, assicurando che i pod non vengano cercati nel namespace di default.
- **Generazione Certificati TLS:** Creazione di certificati self-signed per Keycloak tramite openssl (se non già presenti).
- **ConfigMap:** Iniezione centralizzata delle configurazioni.

## 3. Fix & Integrazioni dei Componenti

### Keystone (`keystone-entrypoint.sh` & `wsgi-keystone.conf`)
- **Fix Bootstrap & Endpoint:** Risolto il bootstrap di Keystone e aggiunta la creazione degli endpoint IoTronic (Service Discovery, Endpoints Public/Internal/Admin, Routing FQDN locale kubernetes).
- **Risoluzione DNS e Routing FQDN:** Sostituzione degli hostname relativi con FQDN assoluti (es.`keystone.keystone.svc.cluster.local`) per prevenire loop di reindirizzamento HTTP.
- **RBAC e Deserializzazione:** Aggiunta la direttiva `OIDCClaimDelimiter ;` per il corretto parsing degli array complessi dei token JWT (come le liste dei gruppi).
- **User Mapping:** Inserito `OIDCRemoteUserClaim preferred_username` per mappare e loggare gli utenti tramite username testuale.
- **Data Injection:** Direttiva `OIDCPassClaimsAs both` per passare i claim del token JWT sia come variabili d'ambiente che come Header HTTP al middleware WSGI di Keystone.

### IoTronic UI (`iotronic-ui-cm1-configmap.yaml`)
- **Host Management:** Configurazione di `ALLOWED_HOSTS`.
- **Service Discovery (`OPENSTACK_HOST`):** Aggiornato con l'FQDN Kubernetes di Keystone.
- **Integrazione SSO/Keycloak:** Abilitata la federazione (`WEBSSO_ENABLED = True`) e aggiornate le `WEBSSO_CHOICES` per includere il login Keycloak.

### Keycloak (`keycloak-deployment.yaml` & `stack4things-realm.json`)
- **Ottimizzazione Health Check:**
  - *Readiness Probe* ottimizzata passando da un check HTTP generico a una request HTTPS mirata al realm (`/realms/stack4things`), abbassando il tempo di attesa a 15s.
  - *Liveness Probe* rifattorizzata per usare un handshake TCP leggero sulla porta sicura 8443, riducendo l'overhead (tempo a 30s).
- **Aggiornamento Realm:** Aggiunta dei `redirectUris` necessari nel `stack4things-realm.json`.

### IoTronic Wagent (`iotronic-wagent-deployment.yaml`)
- **Anti-Race Condition:** Iniezione di una logica "Wait-for-DB" per avviare il Wagent solo dopo il completamento del setup dello schema SQL da parte del Conductor, eliminando i CrashLoopBackOff.
- **Routing FQDN:** Uso degli FQDN per il database e Keystone, garantendo la risoluzione DNS cross-namespace sicura.
- **Hardening Credenziali:** Standardizzazione e sicurezza della password di connessione al database.

### RabbitMQ (`rabbitmq-deployment.yaml`)
- **Provisioning Dinamico:** Utilizzo di un lifecycle hook (`postStart`) per iniettare script di configurazione in runtime.
- **Mitigazione Race Condition:** Inserito un delay prima della sottomissione dei comandi CLI.
- **Design Idempotente:** Adozione del costrutto `|| true` per assorbire le eccezioni non critiche senza incappare in CrashLoopBackOff.
- **Automazione RBAC:** Configurazione automatizzata sul virtual host per l'utente di servizio (`openstack`) e bootstrap dell'admin.

### Gestione Policy (`policy.json`)
- **Policy as Code:** Centralizzazione dei permessi incorporando le policy nel ConfigMap `iotronic-conductor-cm0`.
- **Dynamic Volume Mounting:** Mappatura runtime delle policy nel filesystem del pod del Conductor.
- **API Hardening:** RBAC rigoroso con privilegio minimo, delegando azioni critiche all'admin di progetto e garantendo accesso in lettura agli utenti normali.

## 4. Test & Validate

Per motivi di sicurezza, Keycloak non è esposto pubblicamente ma testato internamente al cluster K8s. 

### Comandi di Port Forward
Prima di testare il flusso utente, instradare il traffico alle porte interne:

**Port forward di Keystone (5000):**
```bash
kubectl port-forward svc/keystone 5000:5000 -n keystone
```

**Port forward di Keycloak (8443):**
```bash
kubectl port-forward svc/keycloak 8443:8443 -n keycloak
```

### Flusso Utente e Multi-Tenant Provisioning
- **Accesso SSO:** L'utente dalla dashboard IAM seleziona il "Federated Login" e viene reindirizzato a Keycloak. Le password non sono gestite da Stack4Things. Una volta loggati, l'Identity Provider restituisce un token JWT valido per il sistema centrale.
- **Multi-Tenant Isolation:** Vengono generati tenants (progetti) dedicati per segregare le risorse.
- **Sincronizzazione Automatica:** La mappatura dei gruppi dal dominio federato avviene in automatico (tramite formato `s4t:<tenant>:<role>` sui claim JWT).
- **Role Binding (Principio del privilegio minimo):** Ai vari ruoli (Admin, Manager, User) vengono associate policy stringenti all'interno del progetto ristretto a cui l'utente target appartiene.
