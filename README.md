# Stack4Things + Crossplane Deployment

Questo repository raccoglie tutto il necessario per installare **Stack4Things** su Kubernetes (k3s) e pilotarlo tramite un **provider Crossplane** personalizzato. Include:

- manifest e configurazioni originali del progetto `Stack4Things_k3s_deployment`
- codice sorgente modificato del provider Crossplane (`crossplane-provider`)
- script operativi per deploy, pulizia e test (`scripts/`)
- una guida unica (questo README) che descrive prerequisiti, passaggi e comandi fondamentali

> **Nota:** l'albero è pronto per essere versionato su GitHub. Esegui `cd /home/ubuntu/s4t-crossplane-deployment && git init` e procedi con `git add .` / `git commit` prima del push verso un repo remoto.

## Struttura del repository

```
.
├── crossplane-provider/        # Codice sorgente Go del provider (modificato)
├── stack4things/               # Manifests e configurazioni Stack4Things su k3s
├── scripts/
│   ├── deploy-s4t-crossplane.sh # installazione end-to-end (k3s, MetalLB, Istio, S4T, Crossplane)
│   ├── cleanup-and-redeploy.sh  # utility per pulizia e redeploy
│   └── test-s4t-apis.sh         # Smoke test API (Keystone + IoTronic)
└── README.md                   # Guida unica
```

## Prerequisiti

| Componente                   | Versione/testata                              | Note |
|-----------------------------|-----------------------------------------------|------|
| Ubuntu                      | 24.04 (server/cloud)                           | richiede sudo
| k3s                          | v1.28+                                         | installato via script ufficiale
| Helm                         | 3.x                                            | usato per Istio/Crossplane
| Docker (Buildx/CLI)         | 24+                                            | per build/push immagini provider
| Go                           | 1.21.13 (tarball locale in `/home/ubuntu/go1.21.13`) | necessario per compilare il provider
| kubectl                      | già fornito da k3s                             | usa `/etc/rancher/k3s/k3s.yaml`
| accesso registro container   | Docker Hub (o privato)                         | per push dell'immagine `provider-s4t`

## Passaggi principali

### 1. Preparazione cluster & dipendenze

1. Installare k3s:
   ```bash
   curl -sfL https://get.k3s.io | sudo sh -
   sudo chmod 644 /etc/rancher/k3s/k3s.yaml
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ```
2. Installare Helm (se assente):
   ```bash
   curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
   chmod 700 get_helm.sh && ./get_helm.sh
   ```
3. (Opzionale) Installare Go 1.21.13 scaricando la release ufficiale e posizionandola in `/home/ubuntu/go1.21.13` oppure aggiornare `$PATH` in modo equivalente.

### 2. Deploy automatizzato (script)

Lo script `scripts/deploy-s4t-crossplane.sh` ripete automaticamente l’intero flusso:

```bash
cd /home/ubuntu/s4t-crossplane-deployment
bash scripts/deploy-s4t-crossplane.sh
```

Cosa esegue:
- verifica prerequisiti e attesa readiness nodi k3s
- installazione MetalLB con IP range configurabile (`METALLB_IP_POOL`)
- installazione Istio base + gateway
- applicazione dei manifest in `stack4things/yaml_file`
- installazione Crossplane (helm chart `crossplane-stable`)
- applicazione RBAC predefinite per il provider
- creazione resource `Provider` puntata a una immagine precompilata (`docker.io/lucadagati/provider-s4t:<tag>`)

### 3. Provider Crossplane: build, immagine e aggiornamento

Per rigenerare il provider con eventuali modifiche Go:

```bash
cd /home/ubuntu/s4t-crossplane-deployment/crossplane-provider
export PATH=/home/ubuntu/go1.21.13/go/bin:$PATH
make go.build                       # compila binari in _output/bin
cp _output/bin/linux_amd64/provider bin/linux_amd64/provider
TAG=$(date +%Y%m%d%H%M%S)
docker build --no-cache   --build-arg TARGETOS=linux --build-arg TARGETARCH=amd64   -f cluster/images/provider-s4t/Dockerfile   -t docker.io/<tuo-user>/provider-s4t:$TAG .
docker push docker.io/<tuo-user>/provider-s4t:$TAG
```

Aggiornare il provider installato in cluster:

```bash
kubectl patch providers.pkg.crossplane.io provider-s4t   --type merge -p '{"spec":{"package":"docker.io/<tuo-user>/provider-s4t:'"$TAG"'"}}'
```

Ogni nuova revision (`kubectl get providerrevision`) richiede la rispettiva RBAC:

```bash
REV=provider-s4t-xxxxxxxxxxxx
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: crossplane:provider:$REV:system
rules:
  - apiGroups: ["iot.s4t.crossplane.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["s4t.crossplane.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get","list","watch","create","update","patch","delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create","patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: crossplane:provider:$REV:system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: crossplane:provider:$REV:system
subjects:
  - kind: ServiceAccount
    name: $REV
    namespace: crossplane-system
EOF
```

Infine, riavviare il deployment del provider:

```bash
kubectl rollout restart deployment/$REV -n crossplane-system
kubectl wait --for=condition=available deployment/$REV -n crossplane-system --timeout=120s
```

### 4. Configurazione credenziali per Crossplane

Lo script di deploy crea un secret `s4t-credentials` in `crossplane-system` con le credenziali `admin/s4t/default`. Se vuoi usare credenziali differenti (es. utente di servizio `iotronic/unime`):

```bash
kubectl -n crossplane-system delete secret s4t-credentials
kubectl -n crossplane-system create secret generic s4t-credentials   --from-literal=credentials.json='{"username":"iotronic","password":"unime","domain":"default"}'
```

Aggiorna la `ProviderConfig` per puntare all’endpoint corretto di Keystone (interno al cluster):

```yaml
apiVersion: s4t.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: s4t-provider-domain
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: s4t-credentials
      key: credentials.json
  keystoneEndpoint: http://keystone.default.svc.cluster.local:5000/v3
```

### 5. Smoke test API

Usa `scripts/test-s4t-apis.sh` per verificare sia Keystone che le REST IoTronic con lo stesso token utilizzato dal provider:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
bash scripts/test-s4t-apis.sh
```

Cosa fa:
1. legge il secret con le credenziali
2. richiede un token scopiato (`scope.project.name=<project>`, `domain.id=default`)
3. prova gli endpoint `/v1/boards`, `/services`, `/plugins`, `/fleets`, `/webservices`, `/ports`

In caso di `403 iot:*:get`, verificare che il token riporti i ruoli `admin_iot_project`/`admin` su Keystone. Il provider Crossplane applica già questa scoping logic nei controller (`read_config.FormatAuthRequ`).

### 6. Risorse di esempio / CRD

- Tutti i CRD e gli esempi si trovano rispettivamente in `crossplane-provider/package/crds` e `crossplane-provider/examples/`
- Gli oggetti usati nei test (`Device`, `Fleet`, `Site`, ecc.) sono negli esempi sotto `examples/`

### 7. Pulizia e redeploy

Per rimuovere rapidamente le componenti e ripartire:

```bash
cd /home/ubuntu/s4t-crossplane-deployment
bash scripts/cleanup-and-redeploy.sh
```

Lo script elimina i namespace principali, ripulisce CRDs, reinstalla Crossplane e rilancia i manifest.

## Troubleshooting rapido

| Problema | Possibili cause | Fix suggerito |
|----------|-----------------|---------------|
| `403 Access was denied to ... iot:*:get` durante i test | Token non scopiato o ruolo `admin_iot_project` mancante | Rigenerare secret con utente `iotronic` o assegnare `admin_iot_project` ad `admin` |
| `dial tcp 127.0.0.1:5000` nei log provider | vecchia immagine che ignorava `keystoneEndpoint` | ricostruire l’immagine e patchare il Provider |
| Nuova `ProviderRevision` `False`/`Inactive` | mancano ClusterRole/Binding per quella revision | Applicare RBAC come mostrato sopra |
| `test-s4t-apis.sh` fallisce ottenendo token | secret errato o Keystone non pronto | ricreare secret, verificare pod `keystone` |

## Prossimi passi

- Versionare su GitHub (`git init`, `.gitignore` per `_output/`, `bin/`, ecc.)
- Automatizzare build/push del provider (GitHub Actions, pipeline interna)
- Aggiungere esempi Crossplane avanzati (plugin injection, webservice, ecc.)

Buon lavoro con Stack4Things + Crossplane!