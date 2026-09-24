#!/usr/bin/env bash
# Start the blog in production mode, reporting each lifecycle stage:
#   1 config/port checks   4 seed import        7 frontend (vite preview)
#   2 dependencies         5 backend (npm start / node server.js)
#   3 storage + database   6/8 health checks
#
# Usage:
#   scripts/prod.sh [--no-build] [--no-seed] [--reset-seed]
# Environment:
#   PORT=xxxx           backend port (default 3001)
#   FRONTEND_PORT=xxxx  preview port (default 5173)
#
# Stop with scripts/stop.sh (or Ctrl-C if launched in the foreground).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BUILD=1
SEED=1
SEED_RESET=0
for arg in "$@"; do
  case "$arg" in
    --no-build)    BUILD=0;;
    --no-seed)     SEED=0;;
    --reset-seed)  SEED_RESET=1;;
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

if [ "$BUILD" -eq 1 ]; then
  stage 5 "building frontend for production (vite build)"
  if (cd "$FRONTEND_DIR" && npm run build) >"$RUN_DIR/build.log" 2>&1; then
    ok "frontend built into $FRONTEND_DIR/dist (log: $RUN_DIR/build.log)"
  else
    cat "$RUN_DIR/build.log"
    die "build" "frontend production build failed"
  fi
else
  warn "skipping frontend build (--no-build); $FRONTEND_DIR/dist must already exist"
  [ -d "$FRONTEND_DIR/dist" ] || die "build" "$FRONTEND_DIR/dist not found; run without --no-build first"
fi

stage 6 "starting backend (production: node server.js)"
start_group "$BACKEND_PID" "$BACKEND_LOG" \
  bash -c "cd '$BACKEND_DIR' && PORT='$BACKEND_PORT' npm start"
ok "backend process group started (pid $(cat "$BACKEND_PID")), log: $BACKEND_LOG"

if ! wait_http "http://localhost:$BACKEND_PORT/api/tags" "backend" "backend" 30; then
  tail -n 20 "$BACKEND_LOG" 2>/dev/null || true
  kill_recorded_group "$BACKEND_PID" "backend" || true
  die "backend" "backend failed to start"
fi

stage 7 "starting frontend static server (vite preview)"
start_group "$FRONTEND_PID" "$FRONTEND_LOG" \
  bash -c "cd '$FRONTEND_DIR' && npm run preview -- --port '$FRONTEND_PORT' --strictPort"
ok "frontend process group started (pid $(cat "$FRONTEND_PID")), log: $FRONTEND_LOG"

if ! wait_http "http://localhost:$FRONTEND_PORT/" "frontend" "frontend" 30; then
  tail -n 20 "$FRONTEND_LOG" 2>/dev/null || true
  kill_recorded_group "$FRONTEND_PID" "frontend" || true
  kill_recorded_group "$BACKEND_PID"  "backend"  || true
  die "frontend" "frontend failed to start"
fi

stage 8 "startup complete"
cat <<EOF

============================================================
 Blog is running (production)
   frontend : http://localhost:$FRONTEND_PORT
   backend  : http://localhost:$BACKEND_PORT  (API: /api)
   logs     : $BACKEND_LOG
              $FRONTEND_LOG
 Stop with : scripts/stop.sh
============================================================
EOF

cleanup() {
  printf '\n[STAGE cleanup] stopping services\n'
  kill_recorded_group "$FRONTEND_PID" "frontend" || true
  kill_recorded_group "$BACKEND_PID"  "backend"  || true
  ok "cleanup complete, ports $BACKEND_PORT and $FRONTEND_PORT released"
  exit 0
}
trap cleanup INT TERM

backend_leader="$(cat "$BACKEND_PID")"
frontend_leader="$(cat "$FRONTEND_PID")"
while kill -0 -- "-$backend_leader" 2>/dev/null && kill -0 -- "-$frontend_leader" 2>/dev/null; do
  sleep 1
done

warn "a service exited unexpectedly; tearing down the rest"
tail -n 20 "$BACKEND_LOG"  2>/dev/null || true
tail -n 20 "$FRONTEND_LOG" 2>/dev/null || true
cleanup
