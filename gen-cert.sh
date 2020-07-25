#!/bin/bash
# https://blog.pinterjann.is/ed25519-certificates.html
fqdn="$1"

echo -n "Fully Qualified Domain Name: [$fqdn] "
read fqdn_in
if [[ -n "$fqdn_in" ]]; then
  fqdn="$fqdn_in"
fi

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 > "$fqdn.key"

cat <<CONF >"$fqdn.cfg"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
C = DE
CN = $fqdn
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = $fqdn
CONF

openssl req -new -out "$fqdn.csr" -key "$fqdn.key" -config "$fqdn.cfg"

# Show request for information
openssl req -in "$fqdn.csr" -text -noout

# self-sign because we don't havew a CA private key.
openssl x509 -req -days 700 -in "$fqdn.csr" -signkey "$fqdn.key" -out "$fqdn.crt"

# Show certificate information for information
openssl x509 -in "$fqdn.crt" -text -noout

