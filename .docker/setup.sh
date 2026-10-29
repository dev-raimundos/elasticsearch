#!/bin/bash
set -euo pipefail
cd /usr/share/elasticsearch
if [[ ! "$ES_CERT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'ES_CERT_IP deve ser um IPv4 valido.' >&2
  exit 1
fi
if [ ! -f config/certs/ca/ca.crt ]; then
  bin/elasticsearch-certutil ca --silent --pem --days 3650 --out config/certs/ca.zip
  unzip -o config/certs/ca.zip -d config/certs
  rm config/certs/ca.zip
fi
if [ ! -f config/certs/elasticsearch/elasticsearch.crt ]; then
  bin/elasticsearch-certutil cert --silent --pem --days 825 \
    --name elasticsearch --dns elasticsearch,localhost \
    --ip "127.0.0.1,$ES_CERT_IP" \
    --ca-cert config/certs/ca/ca.crt --ca-key config/certs/ca/ca.key \
    --out config/certs/server.zip
  unzip -o config/certs/server.zip -d config/certs
  rm config/certs/server.zip
fi
chown -R root:0 config/certs
find config/certs -type d -exec chmod 750 {} \;
find config/certs -type f -exec chmod 640 {} \;
# A chave da CA fica restrita ao setup executado como root.
chmod 600 config/certs/ca/ca.key
cp config/certs/ca/ca.crt /public-ca/ca.crt
chmod 755 /public-ca
chmod 644 /public-ca/ca.crt
