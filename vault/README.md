# Vault Kubernetes HA Setup with Raft and PKI

## Overview

This guide outlines the setup of a highly available (HA) Vault cluster using Raft for storage, along with PKI and TLS configurations.


#### Prerequisite

Generate a temporary SSL certificate. If configuring replicas, you should add a
DNS configuration.

```sh
openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
  -keyout tls.key -out tls.crt \
  -subj "/CN=vault.vault.svc.cluster.local" \
  -addext "subjectAltName=DNS:vault.vault.svc.cluster.local, \
                           DNS:vault-0.vault-internal, \
                           DNS:vault-1.vault-internal, \
                           DNS:vault-2.vault-internal, \
                           IP:127.0.0.1"
```

```sh
kubectl create secret generic vault-tls-tmp -n vault \    
  --from-file=tls.crt=vault.crt \
  --from-file=tls.key=vault.key
```


### Setup Steps

1. **HA Configuration (Replicas, Raft Join)**
   - [Vault Kubernetes Minikube Raft Tutorial](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-raft)
   
2. **PKI and TLS Configuration**
   - [Vault PKI ACME with Caddy Tutorial](https://developer.hashicorp.com/vault/tutorials/pki/pki-acme-caddy)
   - Set up Root CA
   - Set up Intermediate CA

## Installation

Use Helm to install Vault in the `vault` namespace:

```sh
helm install vault hashicorp/vault \
  -n vault \
  --create-namespace \
  -f prev-values.yaml
```
Initial Setup

**1. Initialize Vault**

Initialize the Vault cluster and save the keys:
```sh
kubectl -n vault exec vault-0 -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json > cluster-keys.json
```

•`-key-shares`: Number of key shares for the Raft cluster.  
•`-key-threshold`: Number of key shares required to unseal.

  Note: For production, use appropriate settings and enable Auto-Unseal. Store the cluster-keys.json securely as it contains the root token and unseal keys.

**2. Verify Pod Status**

Check the status of Vault pods:
```sh
kubectl get -n vault all
```
```sh
Example output:

NAME                                        READY   STATUS    RESTARTS   AGE
pod/vault-0                                 0/1     Running   0          84s
pod/vault-1                                 0/1     Running   0          84s
pod/vault-2                                 0/1     Running   0          84s
pod/vault-agent-injector-75f9d67594-95j2q   1/1     Running   0          84s
```
Pods are running but not ready (READY=0/1) as the cluster is sealed.

**3. Unseal the Leader Pod**

Unseal vault-0 using the unseal key from cluster-keys.json:
```sh
kubectl exec vault-0 -n vault -- vault operator unseal <unseal_key_b64>
```
Example output:
```sh
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             false
Total Shares       1
Threshold          1
Version            1.18.1
Build Date         2024-10-29T14:21:31Z
Storage Type       raft
Cluster Name       vault-cluster-c154acd8
Cluster ID         44fccd80-98ff-fc72-73dc-dbe8d3492841
HA Enabled         true
HA Cluster         https://vault-0.vault-internal:8201
HA Mode            active
Active Since       2025-01-26T03:54:32.088776927Z
Raft Committed Index 56
Raft Applied Index   56
```
**4. Join and Unseal Follower Pods**

Join vault-1 to the cluster and unseal it:
```sh
kubectl -n vault exec -ti vault-1 -- /bin/sh

vault operator raft join -address=https://vault-1.vault-internal:8200 \
  -leader-ca-cert="$(cat /vault/userconfig/tls/vault.crt)" \
  -leader-client-cert="$(cat /vault/userconfig/tls/vault.crt)" \
  -leader-client-key="$(cat /vault/userconfig/tls/vault.key)" \
  https://vault-0.vault-internal:8200
```
Output:
```sh
Key     Value
---     -----
Joined  true

Unseal vault-1:

kubectl exec -n vault vault-1 -- vault operator unseal <unseal_key_b64>

Example output:

Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       1
Threshold          1
Unseal Progress    0/1
Unseal Nonce       n/a
Version            1.18.1
Build Date         2024-10-29T14:21:31Z
Storage Type       raft
HA Enabled         true
```

Join vault-2 to the cluster and unseal it:
```sh
kubectl -n vault exec -ti vault-2 -- /bin/sh

vault operator raft join -address=https://vault-2.vault-internal:8200 \
  -leader-ca-cert="$(cat /vault/userconfig/tls/vault.crt)" \
  -leader-client-cert="$(cat /vault/userconfig/tls/vault.crt)" \
  -leader-client-key="$(cat /vault/userconfig/tls/vault.key)" \
  https://vault-0.vault-internal:8200
```

**5. Verify All Pods are Ready**

After joining and unsealing all pods, verify their status:
```sh
kubectl get -n vault pods
```
Example output:
```sh
NAME                                    READY   STATUS    RESTARTS   AGE
vault-0                                 1/1     Running   0          6m39s
vault-1                                 1/1     Running   0          6m39s
vault-2                                 1/1     Running   0          6m39s
vault-agent-injector-75f9d67594-k7dhn   1/1     Running   0          6m39s
```
All pods should show READY=1/1.

**6. Login to Vault**

Use the root token from cluster-keys.json to log in:
```sh
kubectl exec -n vault --stdin=true --tty=true vault-0 -- vault login <root_token>
```
Note: For production, Auto-Unseal is recommended.

PKI Configuration

Scripts
* Generate PKI: `generate_pki.sh`
* Setup Injector: `setup_vault_injector.sh`

Important: Modify the variables and data within each script as needed.

----


#### Issue TLS certificates for Vault using cert-manager.

After Configure PKI, deploy a `ClusterIssuer` in cert-manager and a `Certificate` in vault to enable TLS.

```
kubectl apply -f ../cert-manager/internal/cluster-issuer/vault_cluster_issuer.yaml
kubectl apply -f templates/certificate.yaml
```

----

### Redeploy Vault with the updated values.yaml

```
helm upgrade -n vault vault hashicorp/vault \
    -f values.yaml
```
