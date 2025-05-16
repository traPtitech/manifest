#!/bin/bash

set -euxo pipefail

apk update
apk add mysql-client

set +x
mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" --all-databases --single-transaction --protocol=TCP --default-character-set=utf8mb4 | gzip > /root/showcase-mariadb-backup.gz
set -x

gcloud auth --log-http activate-service-account backup@trap-sysad.iam.gserviceaccount.com --key-file=/keys/key.json
gsutil cp -L /root/backup-cp.log /root/showcase-mariadb-backup.gz gs://trap-services-backup/
