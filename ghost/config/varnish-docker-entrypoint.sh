#!/bin/sh

exec /usr/sbin/varnishd -P /var/run/varnishd.pid \
  -F \
  -a "$BIND_PORT" \
  -f "$VCL_CONFIG" \
  -s "default=malloc,$CACHE_SIZE" \
  -s "image=file,/var/lib/varnish/varnish_storage.bin,$CACHE_SIZE_FILE" \
  -l 80m \
  $VARNISHD_PARAMS
