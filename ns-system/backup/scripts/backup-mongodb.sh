#!/bin/bash

set -euxo pipefail

apk update
apk add mongodb-tools

set +x
mongodump --host "$DB_HOST" --port "$DB_PORT" --username "$DB_USER" --password "$DB_PASS" --out /root/showcase-mongo-backup
set -x
tar -zcvf /root/showcase-mongo-backup.tar.gz /root/showcase-mongo-backup

# gcloud auth activate-service-account example@example.com --key-file=/keys/key.json
# gsutil cp /root/showcase-mongo-backup.tar.gz gs://trap-backups/
