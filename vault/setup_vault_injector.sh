#!/bin/bash
set -e

SERVICE_NAME="gateway"

vault policy write ${SERVICE_NAME}-policy - <<EOF
path "secret/data/${SERVICE_NAME}-config" {
    capabilities = ["read", "list"]
}
EOF

if ! vault auth list | grep -qw kubernetes/; then
    vault auth enable kubernetes
fi

vault write auth/kubernetes/role/${SERVICE_NAME}-role \
    bound_service_account_names=${SERVICE_NAME} \
    bound_service_account_namespaces=${SERVICE_NAME} \
    policies=${SERVICE_NAME}-policy \
    ttl=24h

if ! vault secrets list -detailed | grep -qw "${SERVICE_NAME}-config/"; then
    vault secrets enable -path=${SERVICE_NAME}-config kv-v2
fi

vault kv put ${SERVICE_NAME}-config/env \
    KEYCLOAK_AUTH_SERVER_URL=http://keycloak.keycloak.svc.cluster.local:80 \
    KEYCLOAK_REALM=myrealm \
    KEYCLOAK_CLIENT_ID=myclient \
    KEYCLOAK_CLIENT_SECRET=y22ZHuQZMjkOwTboKUEesLZlVqnobQ65 \
    CALLBACK_URL=http://gateway.gateway.svc.cluster.local:8080/auth/callback \
    REDIS_URL=redis://:1234@redis-master.redis.svc.cluster.local:6379
