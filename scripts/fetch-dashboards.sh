#!/bin/bash
# Downloads community dashboards from grafana.com and sets the datasource to "Prometheus".
# Run once before the first `docker compose up -d`.
set -euo pipefail

DASHBOARD_DIR="$(cd "$(dirname "$0")/../grafana/dashboards" && pwd)"

declare -A DASHBOARDS=(
  [node-exporter-full]=1860
  [prometheus-stats]=3662
  [alertmanager]=9578
)

for name in "${!DASHBOARDS[@]}"; do
  id="${DASHBOARDS[$name]}"
  echo "==> Downloading $name (id=$id)"
  curl -fsSL "https://grafana.com/api/dashboards/${id}/revisions/latest/download" \
    | sed 's/\${DS_PROMETHEUS}/Prometheus/g' \
    > "${DASHBOARD_DIR}/${name}.json"
done

echo "Dashboards saved to $DASHBOARD_DIR"