#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Define variables
ROOT_CA_COMMON_NAME="calm-root-ca"
INT_CA_COMMON_NAME="calm-intermediate-ca"

ROOT_ISSUER_NAME="calm-root-issuer"
INT_ISSUER_NAME="calm-int-issuer"

ROOT_CA_TTL="87600h"  # 10 years
INT_CA_TTL="43800h"   # 5 years

INTERNAL_APP_DOMAIN="*.svc.cluster.local"

echo "=== Starting Vault PKI setup script ==="

# Enable and configure Root CA
echo "1. Enabling and configuring Root CA..."
vault secrets enable pki
vault secrets tune -max-lease-ttl=${ROOT_CA_TTL} pki

echo "2. Generating Root CA certificate..."
vault write -field=certificate pki/root/generate/internal \
    common_name="${ROOT_CA_COMMON_NAME}" \
    issuer_name="${ROOT_ISSUER_NAME}" \
    ttl=${ROOT_CA_TTL} > ${ROOT_CA_COMMON_NAME}.crt
echo "Root CA certificate generated: ${ROOT_CA_COMMON_NAME}.crt"

echo "3. Configuring Root CA URLs..."
vault write pki/config/urls \
    issuing_certificates="http://vault.vault.svc.cluster.local:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.vault.svc.cluster.local:8200/v1/pki/crl"
echo "Root CA URLs configured successfully"

# Enable and configure Intermediate CA
echo "4. Enabling and configuring Intermediate CA..."
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=${INT_CA_TTL} pki_int

echo "5. Generating Intermediate CA CSR..."
vault write -field=csr pki_int/intermediate/generate/internal \
    common_name="${INT_CA_COMMON_NAME}" \
    issuer_name="${INT_ISSUER_NAME}" > ${INT_CA_COMMON_NAME}.csr
echo "Intermediate CA CSR generated: ${INT_CA_COMMON_NAME}.csr"

echo "6. Signing Intermediate CA certificate..."
vault write -field=certificate pki/root/sign-intermediate \
    issuer_ref="${ROOT_ISSUER_NAME}" \
    csr=@${INT_CA_COMMON_NAME}.csr \
    format=pem_bundle ttl=${INT_CA_TTL} > intermediate.cert.pem
echo "Intermediate CA certificate signed: intermediate.cert.pem"

echo "7. Setting Intermediate CA signed certificate..."
vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
echo "Intermediate CA signed certificate set successfully"

echo "8. Configuring Intermediate CA URLs..."
vault write pki_int/config/urls \
    issuing_certificates="http://vault.vault.svc.cluster.local:8200/v1/pki_int/ca" \
    crl_distribution_points="http://vault.vault.svc.cluster.local:8200/v1/pki_int/crl"
echo "Intermediate CA URLs configured successfully"

# Create role for in-cluster connections
echo "9. Creating role for in-cluster connections..."
vault write pki_int/roles/calm-role \
    allow_bare_domains=true \
    allow_subdomains=true \
    allowed_domains="calm.local,${INTERNAL_APP_DOMAIN}" \
    allow_any_name=true \
    require_cn=false \
    max_ttl="720h"
echo "Role 'calm-role' created successfully"

# Enable Kubernetes authentication
echo "10. Enabling Kubernetes authentication..."
vault auth enable kubernetes 2>/dev/null || echo "Kubernetes authentication is already enabled"

echo "11. Configuring Kubernetes authentication..."
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
echo "Kubernetes authentication configured successfully"

# Create policy for cert-manager
echo "12. Creating 'cert-manager-policy' policy..."
vault policy write cert-manager-policy - <<EOF
path "pki_int/sign/calm-role" {
    capabilities = ["create", "update"]
}

path "pki_int/cert/*" {
    capabilities = ["read"]
}
EOF
echo "'cert-manager-policy' policy created successfully"

# Create Kubernetes role for cert-manager
echo "13. Creating Kubernetes role 'cert-manager-role'..."
vault write auth/kubernetes/role/cert-manager-role \
    bound_service_account_names="cert-manager" \
    bound_service_account_namespaces="cert-manager" \
    policies="cert-manager-policy" \
    ttl="24h"
echo "Kubernetes role 'cert-manager-role' created successfully"

echo "=== Vault PKI setup script completed ==="
