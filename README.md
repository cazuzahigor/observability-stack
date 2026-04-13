# observability-stack

Self-hosted observability stack for the Asymptora Platform Engineering Squad. Runs on bare-metal Ubuntu Server via Docker Compose. Focus: learning to **monitor**, **diagnose**, and **respond to incidents** on Linux servers.

> **Context:** this project runs on the lab server `asymptora-prod-01`. No production services are hosted here — the goal is strictly educational. Once real projects start, the server will be wiped and this same repository will re-provision the stack from scratch.

---

## Stack

| Component | Version | Role |
|---|---|---|
| Prometheus | 2.55 | Collects, stores, and evaluates metrics and alert rules |
| node_exporter | 1.8 | Exports host metrics (CPU, RAM, disk, network, systemd, processes, SSH) |
| Alertmanager | 0.27 | Deduplicates, groups, and routes alerts to Discord and ntfy |
| Grafana | 11.3 | Dashboard visualization |
| ntfy | 2.11 | Self-hosted push notifications for critical alerts on mobile |

### Notification channels

Two Discord channels with different purposes:

| Channel | Purpose | Trigger |
|---|---|---|
| `#-infra-status` | Periodic health report — "is the host alive?" | Heartbeat every 6 hours |
| `#-incidentes` | Actionable alerts — "someone must act now" | Thresholds crossed |

This separation prevents alert fatigue: the status channel never gets incident noise, and the incidents channel never gets heartbeat noise.

### Alert routing

- **heartbeat** → `#-infra-status` only (every 6 hours, regardless of state)
- **info / warning** → `#-incidentes`
- **critical** → `#-incidentes` **and** ntfy (urgent push that bypasses Do Not Disturb)
- Inhibition rules: if a host is down, warning alerts for the same host are silenced

### Metric coverage

| Category | Metric | Alert |
|---|---|---|
| Heartbeat | `vector(1)` | InfraStatusHeartbeat |
| Availability | `up`, `node_boot_time_seconds` | HostDown, HostRebooted |
| CPU saturation | `node_load1`, `iowait` | HighLoadAverage, CriticalLoadAverage, HighIOWait |
| CPU utilization | `node_cpu_seconds_total` | HighCPUUsage |
| Memory | `node_memory_MemAvailable_bytes`, `SwapFree` | HighMemoryUsage, CriticalMemoryUsage, SwapUsageHigh |
| Disk | `node_filesystem_avail_bytes`, `files_free` | DiskSpaceWarning, DiskSpaceCritical, InodesRunningOut |
| Integrity | `node_timex_offset_seconds` | ClockSkewDetected |
| systemd | `node_systemd_unit_state` | SystemdServiceFailed, SSHServiceDown |
| **SSH** | `ssh_active_sessions`, `ssh_failed_logins_total`, `ssh_accepted_logins_total` | **SSHSessionOpened, SSHFailedLoginsBurst** |

SSH metrics are produced by `scripts/ssh-metrics.sh`, which writes into the node_exporter textfile collector every 30 seconds.

---

## Server prerequisites

All commands below run **on `asymptora-prod-01`** via SSH/Tailscale, as a user in the `devops` group.

### 1. Update the system

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ca-certificates gnupg lsb-release
```

### 2. Install Docker Engine + Compose plugin

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"
newgrp docker
docker version && docker compose version
```

### 3. Configure UFW (firewall)

Only SSH, Grafana, and ntfy ports are open — and only over Tailscale.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0 to any port 22 proto tcp
sudo ufw allow in on tailscale0 to any port 3000 proto tcp
sudo ufw allow in on tailscale0 to any port 2586 proto tcp
sudo ufw enable
sudo ufw status verbose
```

---

## Step-by-step deployment

### Step 1 — Create the two Discord webhooks

The `#-infra-status` and `#-incidentes` channels each need their own webhook:

**Webhook 1 — `#-infra-status`** (periodic status every 6 hours)
1. Channel settings of `#-infra-status` → **Integrations** → **Webhooks** → **New Webhook**.
2. Name: `Heartbeat`.
3. **Copy Webhook URL** → save as `DISCORD_WEBHOOK_STATUS`.

**Webhook 2 — `#-incidentes`** (real alerts)
1. Channel settings of `#-incidentes` → **Integrations** → **Webhooks** → **New Webhook**.
2. Name: `Alertmanager`.
3. **Copy Webhook URL** → save as `DISCORD_WEBHOOK_INCIDENTS`.

Both URLs go into `.env` in step 4.

### Step 2 — Define the ntfy topic and install the mobile app

ntfy has no user/password for publishing by default: the **topic name is the secret**. It must be long and random.

```bash
openssl rand -hex 16 | sed 's/^/asymptora-/'
# example output: asymptora-7e3f1a9c8d5b4e2f0a6c9d8e7b1f2a3c
```

Save the output — it becomes `NTFY_TOPIC` in `.env`.

On the phone:
1. Install the **ntfy** app (Play Store / App Store).
2. Open → `+` icon → **Subscribe to topic**.
3. Change the default server to `http://asymptora-prod-01:2586` (requires Tailscale).
4. Paste the generated topic.
5. Enable notifications with **bypass Do Not Disturb** (Android) / **Critical** (iOS).

### Step 3 — Clone the repository on the server

```bash
sudo mkdir -p /opt/asymptora
sudo chown "$USER:$USER" /opt/asymptora
cd /opt/asymptora
git clone https://github.com/asymptora/observability-stack.git
cd observability-stack
```

### Step 4 — Configure `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Fill in the 5 fields: `GRAFANA_ADMIN_PASSWORD`, `DISCORD_WEBHOOK_STATUS`, `DISCORD_WEBHOOK_INCIDENTS`, `NTFY_TOPIC` (from step 2), `HOST_LABEL`. Save with `Ctrl+O`, `Enter`, `Ctrl+X`.

### Step 5 — Download dashboards from grafana.com

```bash
chmod +x scripts/fetch-dashboards.sh
./scripts/fetch-dashboards.sh
ls -lh grafana/dashboards/
```

Three `.json` files should appear (Node Exporter Full, Prometheus Stats, Alertmanager).

### Step 6 — Install the SSH metrics collector

```bash
sudo mkdir -p /var/lib/node_exporter/textfile
sudo cp scripts/ssh-metrics.sh /usr/local/bin/ssh-metrics.sh
sudo chmod +x /usr/local/bin/ssh-metrics.sh

sudo cp systemd/ssh-metrics.service /etc/systemd/system/
sudo cp systemd/ssh-metrics.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ssh-metrics.timer

# Validate
sudo systemctl status ssh-metrics.timer
sudo /usr/local/bin/ssh-metrics.sh
cat /var/lib/node_exporter/textfile/ssh.prom
```

The `cat` output should show three metrics: `ssh_active_sessions`, `ssh_failed_logins_total`, `ssh_accepted_logins_total`.

### Step 7 — Validate config syntax before bringing the stack up

```bash
docker run --rm -v "$PWD/prometheus":/etc/prometheus prom/prometheus:v2.55.1 \
  promtool check config /etc/prometheus/prometheus.yml

docker run --rm -v "$PWD/prometheus/rules":/rules prom/prometheus:v2.55.1 \
  promtool check rules /rules/alerts.yml
```

Both must end with `SUCCESS`. If anything fails, fix it before continuing — the stack will not start with invalid YAML.

### Step 8 — Bring the stack up

```bash
docker compose up -d
docker compose ps
```

All 5 containers must show `Status: Up`. If any is `Restarting`, check the logs:

```bash
docker compose logs -f alertmanager
docker compose logs -f prometheus
```

### Step 9 — Validate each component

```bash
# Prometheus healthy
curl -s http://localhost:9090/-/healthy
# Expected: Prometheus Server is Healthy.

# Alertmanager healthy
curl -s http://localhost:9093/-/healthy
# Expected: OK

# node_exporter exposing metrics (network_mode: host)
curl -s http://localhost:9100/metrics | head -20

# SSH metrics reaching Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=ssh_active_sessions' | jq

# Prometheus targets (all must be UP)
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'
```

### Step 10 — Access Grafana

From your notebook (on Tailscale):

```
http://asymptora-prod-01:3000
```

Login: `admin` / the password set in `.env`. Navigate to **Dashboards → Asymptora → Node Exporter Full**. You should see live CPU, RAM, disk, and network metrics.

### Step 11 — Test alerts (without waiting 5 minutes)

#### Test 1 — Heartbeat to `#-infra-status`

The first heartbeat fires on the next evaluation cycle (~30s after the stack is up). Within a few minutes, a green message should appear in `#-infra-status`. After that, one message every 6 hours.

#### Test 2 — Manual critical alert

```bash
curl -XPOST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[
  {
    "labels": {
      "alertname": "ManualTest",
      "severity": "critical",
      "instance": "asymptora-prod-01",
      "category": "test"
    },
    "annotations": {
      "summary": "Manual test alert",
      "description": "Validating routing to #-incidentes + ntfy."
    }
  }
]'
```

Should appear in `#-incidentes` **and** push to the phone within ~30 seconds.

#### Test 3 — Real SSH login

In another terminal, open a new SSH session to the server. Within 1 minute, `#-incidentes` receives the `SSHSessionOpened` alert.

#### Test 4 — Force SSH login failures

```bash
ssh nonexistent_user@asymptora-prod-01 # 6 times
```

After 5 failures in 5 minutes, `SSHFailedLoginsBurst` fires in `#-incidentes`.

### Step 12 — Investigate alerts (incident response workflow)

When an alert lands, this is the minimum sequence to execute **before** taking any action:

1. Read the whole alert (host, category, severity, description).
2. Open Grafana → host dashboard → last 1h.
3. SSH into the host and run the **first 60 seconds** sequence:

```bash
uptime ; dmesg -T | tail -20 ; vmstat 1 5 ; mpstat -P ALL 1 3
iostat -xz 1 3 ; free -h ; sar -n DEV 1 3 ; ss -s ; top -bn1 | head -20 ; df -h
```

4. Correlate Grafana ↔ terminal: does the dashboard agree with `vmstat`/`iostat`?
5. Document everything in a post-mortem (even for false alarms).

---

## Operations

### Reload configs without a restart

```bash
# After editing prometheus.yml or alerts.yml
curl -X POST http://localhost:9090/-/reload

# After editing alertmanager.tmpl.yml
docker compose restart alertmanager
```

### List active and silenced alerts

```bash
curl -s http://localhost:9093/api/v2/alerts | jq
```

### Minimal backup

```bash
docker compose down
sudo tar czf /var/backups/observability-$(date +%F).tar.gz \
  /var/lib/docker/volumes/observability_prometheus_data \
  /var/lib/docker/volumes/observability_grafana_data
docker compose up -d
```

### Update images

```bash
docker compose pull
docker compose up -d
```

---

## Repository layout

```
observability-stack/
├── .env.example
├── .gitignore
├── docker-compose.yml
├── README.md
├── alertmanager/
│   ├── alertmanager.tmpl.yml   # template (envsubst expands ${VAR})
│   └── entrypoint.sh           # runs envsubst and starts alertmanager
├── grafana/
│   ├── dashboards/             # JSONs downloaded by fetch-dashboards.sh
│   └── provisioning/
│       ├── dashboards/dashboards.yml
│       └── datasources/prometheus.yml
├── ntfy/
│   └── server.yml
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
│       └── alerts.yml          # 18 alert rules (17 incidents + 1 heartbeat)
├── scripts/
│   ├── fetch-dashboards.sh     # downloads dashboards from grafana.com
│   └── ssh-metrics.sh          # textfile collector for SSH
└── systemd/
    ├── ssh-metrics.service
    └── ssh-metrics.timer
```

---

## Architecture decisions

**Why `network_mode: host` on node_exporter.** It is the only way to collect real host network metrics — in bridge mode, it would only see the container's virtual interface.

**Why `envsubst` on Alertmanager.** Alertmanager does **not** expand `${VAR}` in every YAML field. The custom entrypoint renders the template before starting the process, ensuring `DISCORD_WEBHOOK_STATUS`, `DISCORD_WEBHOOK_INCIDENTS`, and `NTFY_TOPIC` are injected safely from the environment.

**Why two Discord channels.** `#-infra-status` answers "is it alive?", `#-incidentes` answers "do I need to act?". Mixing them trains people to ignore notifications and causes real alerts to be missed. This is a well-established anti-alert-fatigue pattern.

**Why ntfy *and* Discord for critical.** Discord is asynchronous and muted outside working hours. ntfy bypasses Do Not Disturb and ensures someone wakes up when `asymptora-prod-01` goes down at 3 AM.

**Why Prometheus on `127.0.0.1:9090`.** Prometheus has no native authentication. Binding to loopback forces access over Tailscale + SSH tunnel (`ssh -L 9090:localhost:9090`), keeping the UI private.

**What is out of scope for this module.** Loki/Promtail (centralized logs) and cAdvisor (container metrics) — these come in M8 once the real stack starts running services.

---

## Next steps (M8 on the roadmap)

- Add Loki + Promtail for centralized logs and LogQL-based alerts
- Add blackbox_exporter to probe external endpoints
- Add cAdvisor once real containers land on the server
- Define SLIs/SLOs based on the historical data collected here
- Document real incidents in `incident-log/` as post-mortems
- Replace the `vector(1)` heartbeat with a Python job that posts a real metrics summary (uptime, load, disk, memory) to `#-infra-status` via the Prometheus HTTP API — natural project for M1 (Python for DevOps)
