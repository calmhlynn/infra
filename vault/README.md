
설정 개요

1. HA 세팅 (replicas raft join) https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-raft
2. PKI 세팅 및 TLS 설정 https://developer.hashicorp.com/vault/tutorials/pki/pki-acme-caddy
  * set root CA
  * set intermidiate CA

----

#### #1 HA 

`operator init`로 root token, unseal key를 발급받는다.    
`-key-shares`는 raft cluster 내에서 사용된 공유키의 수,  `-key-threshold`는
unseal하는데 필요한 공유키의 수이다.  프로덕션 레벨에서는 이 설정값을 높인 후
**Auto-Unseal**을 사용할 것을 권장한다.
```
$ kubectl exec vault-0 -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > cluster-keys.json
```

클러스터들이 아직 Unseal되지 않았기 때문에 Running이지만 READY=0/1인 상태
```zsh
$ kubectl get -n vault all                                    
NAME                                        READY   STATUS    RESTARTS   AGE
pod/vault-0                                 0/1     Running   0          84s
pod/vault-1                                 0/1     Running   0          84s
pod/vault-2                                 0/1     Running   0          84s
pod/vault-agent-injector-75f9d67594-95j2q   1/1     Running   0          84s
```

cluster-keys.json에서 찾은 `unseal_key_b64`를 통해 Unseal한다.
```
$ kubectl exec vault-0 -- vault operator unseal {unseal_key_b64}
Key                     Value
---                     -----
Seal Type               shamir
Initialized             true
Sealed                  false
Total Shares            1
Threshold               1
Version                 1.18.1
Build Date              2024-10-29T14:21:31Z
Storage Type            raft
Cluster Name            vault-cluster-c154acd8
Cluster ID              44fccd80-98ff-fc72-73dc-dbe8d3492841
HA Enabled              true
HA Cluster              https://vault-0.vault-internal:8201
HA Mode                 active
Active Since            2025-01-26T03:54:32.088776927Z
Raft Committed Index    56
Raft Applied Index      56
```


`vault-1`를 조인 후,  Unseal한다.    
조인을 하지 않고 Unseal을 시도하면 에러가 발생
```
$ kubectl -n vault exec -ti vault-1 -- \ 
    vault operator raft join http://vault-0.vault-internal:8200
Key       Value
---       -----
Joined    true

$ k exec -n vault vault-1 -- vault operator unseal {unseal_key_b64}
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

마찬가지로 `vault-2`도 위와같이 적용한다.

```
$ kubectl get -n vault pod
NAME                                    READY   STATUS    RESTARTS   AGE
vault-0                                 1/1     Running   0          6m39s
vault-1                                 1/1     Running   0          6m39s
vault-2                                 1/1     Running   0          6m39s
vault-agent-injector-75f9d67594-k7dhn   1/1     Running   0          6m39s
```

마지막으로 cluster-keys.json의 root_token을 통해 로그인한다. 
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \      
       vault login
```

앞서 말한대로 프로덕션 레벨에서는 **Auto-Unseal**을 사용하는 것을 권장한다.

----

#### #2 Vault PKI

##### #2-1 Create Root CA
Root CA 생성
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \
        vault secrets enable pki
Success! Enabled the pki secrets engine at: pki/
```

인증서의 만료일 설정
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \
        vault secrets tune -max-lease-ttl=87600h pki
Success! Tuned the secrets engine at: pki/
```

Root CA, 발급자 이름을 지정 후 `.crt`파일에 저장 
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \
      vault write -field=certificate pki/root/generate/internal \
      common_name="calmhlynn.com" \
      issuer_name="calm-root" \
      ttl=87600h > calm_root_ca.crt
```

Root CA 발급자 확인,  Root CA 발급자에 대한 메타데이터 확인
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \ 
    vault list pki/issuers/
Keys
----
09c2c9a0-a874-36d2-de85-d79a7a51e373

$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \
    vault read pki/issuer/$(vault list -format=json pki/issuers/ | jq -r '.[]') \
    tail -n 6
```

Root CA에 대한 역할 생성
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \      
∙       vault write pki/roles/calm-root-servers allow_any_name=true
```

CA, CRL URLs 생성
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \
        vault write pki/config/urls \
        issuing_certificates="https://vault.vault.svc.cluster.local:8200/v1/pki/ca" \
        crl_distribution_points="https://vault.vault.svc.cluster.local:8200/v1/pki/crl"
```

##### #2-2 Create Intermidate CA

PKI Intermidate 엔진 활성화
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \
        vault secrets enable -path=pki_int pki
```

만료일 설정
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \
       vault secrets tune -max-lease-ttl=43800h pki_int
```

PKI int 생성 후 `.csr`로 저장
```
$ kubectl exec -n vault --stdin=true --tty=true vault-0 -- \       
    vault write -format=json pki_int/intermediate/generate/internal \
        common_name="calmhlynn.com Intermediate Authority" \
        issuer_name="calmhlynn-dot-com-intermediate" \
        | jq -r '.data.csr' > pki_intermediate.csr
```

