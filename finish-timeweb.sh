#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$EUID" -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
app_root=/opt/auto-photo-ingest
browser_path="$(find "$app_root/browsers" -type f -name chrome-headless-shell -perm /111 -print -quit)"
[[ -n "$browser_path" && -x "$browser_path" ]] || { echo "Chromium executable not found" >&2; exit 1; }
profile=/etc/apparmor.d/auto-photo-playwright-chromium
cat > "$profile" <<EOF
abi <abi/4.0>,
include <tunables/global>

profile auto-photo-playwright-chromium $browser_path flags=(unconfined) {
  userns,
}
EOF
apparmor_parser -r "$profile"
runuser -u auto-photo-ingest -- env PLAYWRIGHT_BROWSERS_PATH="$app_root/browsers" \
  "$app_root/venv/bin/auto-photo-worker" --check-browser
install -d -m 0750 -o root -g auto-photo-ingest /etc/auto-photo-ingest
install -d -m 0750 -o auto-photo-ingest -g auto-photo-ingest /var/backups/auto-photo-ingest
if [[ ! -e /etc/auto-photo-ingest/materials.csv ]]; then
  printf 'url,name\n' > /etc/auto-photo-ingest/materials.csv
  chown root:auto-photo-ingest /etc/auto-photo-ingest/materials.csv
  chmod 0640 /etc/auto-photo-ingest/materials.csv
fi
cat > /etc/systemd/system/auto-photo-ingest.service <<'EOF'
[Unit]
Description=Auto Photo Ingest worker
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=auto-photo-ingest
Group=auto-photo-ingest
WorkingDirectory=/var/lib/auto-photo-ingest
Environment=PLAYWRIGHT_BROWSERS_PATH=/opt/auto-photo-ingest/browsers
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/auto-photo-ingest/venv/bin/auto-photo-worker
UMask=0077
TimeoutStartSec=45min
KillMode=control-group
MemoryMax=3G
CPUQuota=150%
TasksMax=512
Nice=10
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/auto-photo-ingest /var/backups/auto-photo-ingest
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
EOF
cat > /etc/systemd/system/auto-photo-ingest.timer <<'EOF'
[Unit]
Description=Check new photo materials every five minutes

[Timer]
OnBootSec=2min
OnUnitInactiveSec=5min
RandomizedDelaySec=30s
Unit=auto-photo-ingest.service

[Install]
WantedBy=timers.target
EOF
chmod 0644 /etc/systemd/system/auto-photo-ingest.service /etc/systemd/system/auto-photo-ingest.timer
systemctl daemon-reload
systemctl start auto-photo-ingest.service
systemctl enable --now auto-photo-ingest.timer
systemctl is-active --quiet auto-photo-ingest.timer
sed -i '/codex-auto-service-bootstrap-2026-09-22$/d' /root/.ssh/authorized_keys 2>/dev/null || true
rm -f /root/bootstrap-timeweb.sh /root/finish-timeweb.sh
printf 'INSTALLATION=OK\nTIMER='
systemctl is-active auto-photo-ingest.timer
printf 'HEALTH=\n'
cat /var/lib/auto-photo-ingest/health.json
