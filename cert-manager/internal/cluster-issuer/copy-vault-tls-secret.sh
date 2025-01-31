#!/bin/bash

set -e  

SOURCE_NAMESPACE="vault"
TARGET_NAMESPACE="cert-manager"
SECRET_NAME="vault-tls-final"


kubectl get secret "$SECRET_NAME" -n "$SOURCE_NAMESPACE" -o jsonpath='{.data.ca\.crt}' | base64 --decode > /tmp/ca.crt
kubectl get secret "$SECRET_NAME" -n "$SOURCE_NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 --decode > /tmp/tls.crt
kubectl get secret "$SECRET_NAME" -n "$SOURCE_NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 --decode > /tmp/tls.key


kubectl create secret generic "$SECRET_NAME" \
  --from-file=ca.crt=/tmp/ca.crt \
  --from-file=tls.crt=/tmp/tls.crt \
  --from-file=tls.key=/tmp/tls.key \
  -n "$TARGET_NAMESPACE"

rm /tmp/ca.crt /tmp/tls.crt /tmp/tls.key

echo "Successfully secret copied to '$TARGET_NAMESPACE'"
