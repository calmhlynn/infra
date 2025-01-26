#!/bin/bash

set -euxo pipefail


vault secrets enable pki


vault secrets tune -max-lease-ttl=87600h pki


vault write -field=certificate pki/root/generate/internal \
   common_name="calm-pki" \
   issuer_name="calm-root-issuer" \
   ttl=87600h > calm_root_ca.crt


vault write pki/config/cluster \
   path=http://10.1.1.100:8200/v1/pki \
   aia_path=http://10.1.1.100:8200/v1/pki


vault write pki/roles/calm-servers \
   allow_any_name=true \
   no_store=false


vault write pki/config/urls \
   issuing_certificates={{cluster_aia_path}}/issuer/{{issuer_id}}/der \
   crl_distribution_points={{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der \
   ocsp_servers={{cluster_path}}/ocsp \
   enable_templating=true


vault secrets enable -path=pki_int pki


vault secrets tune -max-lease-ttl=43800h pki_int


vault write -field=csr pki_int/intermediate/generate/internal \
   common_name="calm-pki Intermediate Authority" \
   issuer_name="calm-int-issuer" > pki_intermediate.csr


vault write -field=certificate pki/root/sign-intermediate \
   issuer_ref="calm-root-issuer" \
   csr=@pki_intermediate.csr \
   format=pem_bundle ttl="43800h" > intermediate.cert.pem


vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem


vault write pki_int/config/cluster \
   path=http://10.1.1.100:8200/v1/pki_int \
   aia_path=http://10.1.1.100:8200/v1/pki_int


vault write pki_int/roles/learn \
   issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
   allow_any_name=true \
   max_ttl="720h" \
   no_store=false


vault write pki_int/config/urls \
   issuing_certificates={{cluster_aia_path}}/issuer/{{issuer_id}}/der \
   crl_distribution_points={{cluster_aia_path}}/issuer/{{issuer_id}}/crl/der \
   ocsp_servers={{cluster_path}}/ocsp \
   enable_templating=true
