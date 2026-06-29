#!/bin/bash

set -euxo pipefail

apk update
apk add mongodb-tools

set +x
mongodump --host "$DB_HOST" --port "$DB_PORT" --db "$DB_NAME" --gzip --archive="/root/$BACKUP_FILE"
set -x

gcloud auth activate-service-account backup@trap-sysad.iam.gserviceaccount.com --key-file=/keys/key.json
gsutil cp "/root/$BACKUP_FILE" "gs://trap-services-backup/$BACKUP_FILE"
