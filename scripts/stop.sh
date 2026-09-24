#!/usr/bin/env bash
# Stop blog services recorded in .run/ and release the ports.
#   scripts/stop.sh           graceful stop (TERM, then KILL after 6s)
#   scripts/stop.sh --purge   also remove logs and all .run artifacts
#
# Only processes started by dev.sh / prod.sh (recorded pidfiles) are managed;
# a port held by an unrelated process is reported, never force-killed.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

BACKEND_PID="$RUN_DIR/backend.pid"
FRONTEND_PID="$RUN_DIR/frontend.pid"
stopped=0

stage 1 "stopping recorded services"

for pair in "$FRONTEND_PID:frontend" "$BACKEND_PID:backend"; do
  pidfile="${pair%%:*}"
  label="${pair##*:}"
  if [ ! -f "$pidfile" ]; then
    info "$label: no pidfile (not managed / already stopped)"
    continue
  fi
  if kill_recorded_group "$pidfile" "$label"; then
    ok "$label stopped and pidfile removed"
    stopped=1
  fi
done

[ "$stopped" -eq 0 ] && info "no managed services were running"

stage 2 "verifying ports are released"
for pair in "$FRONTEND_PORT:frontend" "$BACKEND_PORT:backend"; do
  port="${pair%%:*}"
  label="${pair##*:}"
  if port_in_use "$port"; then
    warn "$label port $port is still listening; it belongs to a process not started by these scripts"
  else
    ok "$label port $port is free"
  fi
done

stage 3 "cleanup"
rm -f "$RUN_DIR/last-fail-stage"
if [ "$PURGE" -eq 1 ]; then
  rm -rf "$RUN_DIR"
  ok "removed runtime artifacts in $RUN_DIR"
else
  ok "cleanup rules applied; logs kept in $RUN_DIR for inspection (--purge removes them)"
fi
