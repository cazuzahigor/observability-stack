# Dashboards

This directory holds the dashboard JSON files that will be automatically loaded by Grafana via provisioning.

Dashboards are downloaded by the `scripts/fetch-dashboards.sh` script (run once before the first `docker compose up`).

Included dashboards:

| grafana.com ID | Name | File |
|---|---|---|
| 1860 | Node Exporter Full | node-exporter-full.json |
| 3662 | Prometheus 2.0 Stats | prometheus-stats.json |
| 9578 | Alertmanager | alertmanager.json |