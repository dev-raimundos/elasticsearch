#!/bin/bash
set -euo pipefail
# Senha hexadecimal permite construir o JSON sem escape ambíguo.
if [[ ! "$KIBANA_PASSWORD" =~ ^[0-9a-fA-F]{64,}$ ]]; then
  echo 'KIBANA_PASSWORD deve conter pelo menos 64 caracteres hexadecimais.' >&2
  exit 1
fi
curl --fail-with-body --silent --show-error \
  --cacert /public-ca/ca.crt \
  -u "elastic:$ELASTIC_PASSWORD" \
  -H 'Content-Type: application/json' \
  -X POST https://elasticsearch:9200/_security/user/kibana_system/_password \
  -d "{\"password\":\"$KIBANA_PASSWORD\"}"
