#!/bin/bash

set -e

ROOT_CA_COMMON_NAME="calm-root-ca"
INT_CA_COMMON_NAME="calm-intermediate-ca"

ROOT_ISSUER_NAME="calm-root-issuer"
INT_ISSUER_NAME="calm-int-issuer"

ROOT_CA_TTL="87600h" # 10y
INT_CA_TTL="43800h" # 5y

INTERNAL_APP_DOMAIN="*.svc.cluster.local"

# set root CA
vault secrets enable pki
vault secrets tune -max-lease-ttl=${ROOT_CA_TTL} pki

vault write -field=certificate pki/root/generate/internal \
    common_name="${ROOT_CA_COMMON_NAME}" \
    issuer_name="${ROOT_ISSUER_NAME}" \
    ttl=${ROOT_CA_TTL} > ${ROOT_CA_COMMON_NAME}.crt

vault write pki/config/urls \
    issuing_certificates="http://vault.vault.svc.cluster.local:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.vault.svc.cluster.local:8200/v1/pki/crl"


# set intermediate CA
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=${INT_CA_TTL} pki_int

vault write -field=csr pki_int/intermediate/generate/internal \
    common_name="${INT_CA_COMMON_NAME}" \
    issuer_name="${INT_ISSUER_NAME}" > ${INT_CA_COMMON_NAME}.csr

vault write -field=certificate pki/root/sign-intermediate \
    issuer_ref="${ROOT_ISSUER_NAME}" \
    csr=@${INT_CA_COMMON_NAME}.csr \
    format=pem_bundle ttl=${INT_CA_TTL} > intermediate.cert.pem

vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem

vault write pki_int/config/urls \
    issuing_certificates="http://vault.vault.svc.cluster.local:8200/v1/pki_int/ca" \
    crl_distribution_points="http://vault.vault.svc.cluster.local:8200/v1/pki_int/crl"

# generate role to connect in cluster
vault write pki_int/roles/calm-role \
    allow_bare_domains=true \
    allow_subdomains=true \
    allowed_domains="calm.local,${INTERNAL_APP_DOMAIN}" \
    allow_any_name=true \
    require_cn=false \
    max_ttl="720h"

vault auth enable kubernetes 2>/dev/null || true

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt


vault policy write cert-manager-policy - <<EOF
path "pki_int/sign/calm-role" {
    capabilities = ["create", "update"]
}

path "pki_int/cert/*" {
    capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/cert-manager-role \
    bound_service_account_names="cert-manager" \
    bound_service_account_namespaces="cert-manager" \
    policies="cert-manager-policy" \
    ttl="24h"
