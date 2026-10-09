#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit_file="$unit_dir/medflow-dev.service"
mkdir -p "$unit_dir"
if [[ -f "$unit_file" ]] && ! head -n 1 "$unit_file" | rg -q '^# Managed by MedFlow$'; then
  echo 'Existe uma unidade medflow-dev não gerenciada por este projeto; preserve-a e revise manualmente.' >&2
  exit 1
fi
cat > "$unit_file" <<UNIT
# Managed by MedFlow
[Unit]
Description=MedFlow frontend e API PHP locais
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$project_dir
ExecStart=/usr/bin/bash "$project_dir/scripts/dev.sh"
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Restart=on-failure
RestartSec=5
KillMode=control-group
TimeoutStopSec=20

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now medflow-dev.service
systemctl --user --no-pager status medflow-dev.service
