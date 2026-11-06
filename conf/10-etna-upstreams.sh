#!/bin/sh

set -eu

mkdir -p /etc/nginx/etna-upstreams
for service in service-status chat; do
  printf 'server %s:8080;\n' "$service" > "/etc/nginx/etna-upstreams/$service.conf"
done
