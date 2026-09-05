#!/bin/bash

set -euxo pipefail

apk add --no-cache mariadb-client

set +x
mariadb-dump \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --user="$DB_USER" \
  --password="$DB_PASSWORD" \
  --single-transaction \
  --default-character-set=utf8mb4 \
  "$DB_NAME" | gzip > /tmp/grafana-sakura.db.gz
set -x

gcloud auth activate-service-account backup@trap-sysad.iam.gserviceaccount.com --key-file=/keys/key.json
gsutil cp /tmp/grafana-sakura.db.gz gs://trap-services-backup/
