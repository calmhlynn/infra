
Before to apply `lets-encrypts-dns01.yaml`, create secret like code below
```
kubectl create secret generic cloudflare-api-secret \
  --from-literal=api-token=<CLOUDFLARE_API_TOKEN> \
  --namespace cert-manager
```


ref: [acme-dns01-cloudflare](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
