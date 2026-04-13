#!/bin/sh
# Expands environment variables in the template and starts Alertmanager.
# Required because Alertmanager does not natively expand ${VAR} in all fields

set -e

apk add --no-cache gettext >/dev/null 2>&1 || true

envsubst < /etc/alertmanager/alertmanager.tmpl.yml > /tmp/alertmanager.yml

exec /bin/alertmanager \
  --config.file=/tmp/alertmanager.yml \
  --storage.path=/alertmanager \
  --web.external-url=http://localhost:9093
