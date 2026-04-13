#!/bin/bash
# ssh-metrics.sh
# Exports SSH metrics to the node_exporter textfile collector.
# Runs periodically via systemd timer and writes an atomic .prom file.
#
# Exposed metrics:
#   ssh_active_sessions          gauge   - active interactive sessions (who | wc -l)
#   ssh_failed_logins_total      gauge   - cumulative authentication failures in the current auth.log
#   ssh_accepted_logins_total    gauge   - cumulative accepted logins in the current auth.log
#
# Output path: /var/lib/node_exporter/textfile/ssh.prom
set -euo pipefail

TEXTFILE_DIR="/var/lib/node_exporter/textfile"
OUT="${TEXTFILE_DIR}/ssh.prom"
TMP="$(mktemp "${OUT}.XXXXXX")"

mkdir -p "$TEXTFILE_DIR"

ACTIVE=$(who | wc -l)

if [ -r /var/log/auth.log ]; then
  FAILED=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l)
  ACCEPTED=$(grep -E "Accepted (password|publickey)" /var/log/auth.log 2>/dev/null | wc -l)
else
  FAILED=$(journalctl -u ssh --since "today" 2>/dev/null | grep "Failed password" | wc -l)
  ACCEPTED=$(journalctl -u ssh --since "today" 2>/dev/null | grep -E "Accepted (password|publickey)" | wc -l)
fi

cat > "$TMP" <<EOF
# HELP ssh_active_sessions Active interactive SSH sessions on the host.
# TYPE ssh_active_sessions gauge
ssh_active_sessions ${ACTIVE}
# HELP ssh_failed_logins_total Failed SSH login attempts (current auth.log / today's journal).
# TYPE ssh_failed_logins_total gauge
ssh_failed_logins_total ${FAILED}
# HELP ssh_accepted_logins_total Accepted SSH logins (current auth.log / today's journal).
# TYPE ssh_accepted_logins_total gauge
ssh_accepted_logins_total ${ACCEPTED}
EOF

chmod 644 "$TMP"
mv "$TMP" "$OUT"
