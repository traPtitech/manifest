#!/bin/bash

set -euxo pipefail

# https://docs.k3s.io/datastore/backup-restore

# Test for expected files
test -d /backup-target
test -f /backup-target/token
test -d /backup-target/db

# Make tar of backup target
tar -zcvf /root/k3s-server.tar.gz /backup-target

# Upload to GCS
gcloud auth activate-service-account backup@trap-sysad.iam.gserviceaccount.com --key-file=/keys/key.json
gsutil cp /root/k3s-server.tar.gz gs://trap-services-backup/
