#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
if [[ ! -f backend/.env || ! -f frontend/js/config.js ]]; then
  echo 'Configure backend/.env e frontend/js/config.js antes de iniciar.' >&2
  exit 1
fi
mkdir -p backend/var
frontend_pid=''
backend_pid=''
cleanup() {
  if [[ -n "$frontend_pid" ]]; then kill "$frontend_pid" 2>/dev/null || true; fi
  if [[ -n "$backend_pid" ]]; then kill "$backend_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM
responds() {
  python3 - "$1" <<'CHECK'
import urllib.request,sys
try:
    with urllib.request.urlopen(sys.argv[1],timeout=2) as response:
        sys.exit(0 if response.status==200 else 1)
except Exception:
    sys.exit(1)
CHECK
}
if ! responds http://127.0.0.1:5173/js/bootstrap.js; then
  python3 -m http.server 5173 --bind 127.0.0.1 --directory frontend >backend/var/frontend.log 2>&1 &
  frontend_pid=$!
fi
if ! responds http://127.0.0.1:8080/api/health; then
  if command -v php >/dev/null; then
    (cd backend && exec php -S 127.0.0.1:8080 -t public public/index.php) >backend/var/api.log 2>&1 &
  elif command -v podman >/dev/null; then
    podman run --rm -p 127.0.0.1:8080:8080 -v "$project_dir:/app:ro,Z" -w /app/backend docker.io/library/php:8.3-cli php -S 0.0.0.0:8080 -t public public/index.php >backend/var/api.log 2>&1 &
  else
    echo 'Instale PHP 8.3 com cURL ou Podman para iniciar a API.' >&2
    exit 1
  fi
  backend_pid=$!
fi
for attempt in {1..20}; do
  if responds http://127.0.0.1:5173/js/bootstrap.js && responds http://127.0.0.1:8080/api/health; then
    echo 'MedFlow: http://127.0.0.1:5173'
    echo 'API: http://127.0.0.1:8080/api/health'
    echo 'Mantenha este terminal aberto. Ctrl+C encerra os servidores iniciados aqui.'
    if [[ -n "$frontend_pid" || -n "$backend_pid" ]]; then
      while true; do
        sleep 5
        if ! responds http://127.0.0.1:5173/js/bootstrap.js || ! responds http://127.0.0.1:8080/api/health; then
          echo 'Um servidor parou. Reinicie o comando ou consulte os logs.' >&2
          exit 1
        fi
      done
    fi
    exit 0
  fi
  sleep 1
done
echo 'Não foi possível iniciar. Confira backend/var/frontend.log e backend/var/api.log.' >&2
exit 1
