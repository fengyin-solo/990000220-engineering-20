#!/usr/bin/env bash
# Start the blog in development mode, reporting each lifecycle stage:
#   1 config/port checks   4 seed import           7 frontend (vite 5173)
#   2 dependencies         5 backend (node --watch)
#   3 storage + database   6 health checks
#
# Usage:
#   scripts/dev.sh [--no-seed] [--reset-seed]
# Environment:
#   PORT=xxxx           backend port (default 3001)
#   FRONTEND_PORT=xxxx  vite port (default 5173)
#
# Stop with Ctrl-C or `scripts/stop.sh` from another terminal.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SEED=1
SEED_RESET=0
for arg in "$@"; do
  case "$arg" in
    --no-seed)    SEED=0;;
    --reset-seed) SEED_RESET=1;;
    *) echo "unknown argument: $arg" >&2; exit 2;;
  esac
done

BACKEND_PID="$RUN_DIR/backend.pid"
FRONTEND_PID="$RUN_DIR/frontend.pid"

stage 1 "configuration and port checks"
validate_port "backend"  "$BACKEND_PORT"
validate_port "frontend" "$FRONTEND_PORT"
ensure_run_dir
reap_stale_pidfile "$BACKEND_PID"
reap_stale_pidfile "$FRONTEND_PID"
require_port_free "$BACKEND_PORT"  "$BACKEND_PID" "backend"
require_port_free "$FRONTEND_PORT" "$FRONTEND_PID" "frontend"

stage 2 "dependencies"
check_node
check_backend_deps
check_frontend_deps

stage 3 "storage and database initialization"
check_storage
run_db_init

if [ "$SEED" -eq 1 ]; then
  stage 4 "seed import (idempotent)"
  if [ "$SEED_RESET" -eq 1 ]; then
    run_seed "--reset"
  else
    run_seed
  fi
fi

stage 5 "starting backend (development: node --watch)"
start_group "$BACKEND_PID" "$BACKEND_LOG" \
  bash -c "cd '$BACKEND_DIR' && PORT='$BACKEND_PORT' npm run dev"
ok "backend process group started (pid $(cat "$BACKEND_PID")), log: $BACKEND_LOG"

stage 6 "backend health check"
if ! wait_http "http://localhost:$BACKEND_PORT/api/tags" "backend" "backend" 30; then
  tail -n 20 "$BACKEND_LOG" 2>/dev/null || true
  kill_recorded_group "$BACKEND_PID" "backend" || true
  die "backend" "backend failed to start"
fi

stage 7 "starting frontend (development: vite)"
start_group "$FRONTEND_PID" "$FRONTEND_LOG" \
  bash -c "cd '$FRONTEND_DIR' && npm run dev -- --port '$FRONTEND_PORT' --strictPort"
ok "frontend process group started (pid $(cat "$FRONTEND_PID")), log: $FRONTEND_LOG"

if ! wait_http "http://localhost:$FRONTEND_PORT/" "frontend" "frontend" 30; then
  tail -n 20 "$FRONTEND_LOG" 2>/dev/null || true
  kill_recorded_group "$FRONTEND_PID" "frontend" || true
  kill_recorded_group "$BACKEND_PID" "backend" || true
  die "frontend" "frontend failed to start"
fi

cat <<EOF

============================================================
 Blog is running (development)
   frontend : http://localhost:$FRONTEND_PORT
   backend  : http://localhost:$BACKEND_PORT  (API: /api)
   logs     : $BACKEND_LOG
              $FRONTEND_LOG
 Stop with : scripts/stop.sh  (or press Ctrl-C here)
============================================================
EOF

# Foreground: clean up both process groups on Ctrl-C / termination.
cleanup() {
  printf '\n[STAGE cleanup] stopping services\n'
  kill_recorded_group "$FRONTEND_PID" "frontend" || true
  kill_recorded_group "$BACKEND_PID"  "backend"  || true
  ok "cleanup complete, ports $BACKEND_PORT and $FRONTEND_PORT released"
  exit 0
}
trap cleanup INT TERM

# Pause while services run; keep the script attached so Ctrl-C works.
backend_leader="$(cat "$BACKEND_PID")"
frontend_leader="$(cat "$FRONTEND_PID")"
while kill -0 -- "-$backend_leader" 2>/dev/null && kill -0 -- "-$frontend_leader" 2>/dev/null; do
  sleep 1
done

warn "a service exited unexpectedly; tearing down the rest"
tail -n 20 "$BACKEND_LOG"  2>/dev/null || true
tail -n 20 "$FRONTEND_LOG" 2>/dev/null || true
cleanup
