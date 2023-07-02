#!/bin/bash

set -euxo pipefail

set +x
mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" --all-databases --single-transaction --protocol=TCP --default-character-set=utf8mb4 | gzip > /root/showcase-mariadb-backup.gz
set -x

# gcloud auth activate-service-account example@example.com --key-file=/keys/key.json
# gsutil cp /root/showcase-mariadb-backup.gz gs://trap-backups/
