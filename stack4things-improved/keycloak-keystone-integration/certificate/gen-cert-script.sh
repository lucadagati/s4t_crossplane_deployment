openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -subj "/CN=S4T-Local-CA" -out ca.crt

# 2️⃣ Creare file SAN per Keycloak (cluster)
cat > san.cnf <<'EOF'
[req]
prompt = no
distinguished_name = dn
req_extensions = req_ext

[dn]
CN = keycloak.keycloak.svc.cluster.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = keycloak
DNS.2 = keycloak.keycloak
DNS.3 = keycloak.keycloak.svc.cluster.local
EOF

# 3️⃣ Generare chiave privata e CSR per Keycloak
openssl genrsa -out keycloak.key 4096
openssl req -new -key keycloak.key -out keycloak.csr -config san.cnf

# 4️⃣ Firmare il certificato con la CA
openssl x509 -req -in keycloak.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out keycloak.crt -days 365 -sha256 -extensions req_ext -extfile san.cnf
