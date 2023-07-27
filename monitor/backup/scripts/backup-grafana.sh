#!/bin/bash

set -euxo pipefail

gzip < /data/grafana.db > /data/grafana.db.gz

gcloud auth activate-service-account backup@trap-sysad.iam.gserviceaccount.com --key-file=/keys/key.json
gsutil cp /data/grafana.db.gz gs://trap-services-backup/
