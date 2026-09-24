#!/usr/bin/env bash
# Show lifecycle status: recorded pids, port ownership, and the last failed stage.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Blog lifecycle status"
echo "---------------------"
echo "backend  port: $BACKEND_PORT"
echo "frontend port: $FRONTEND_PORT"

for pair in "$RUN_DIR/backend.pid:backend" "$RUN_DIR/frontend.pid:frontend"; do
  pidfile="${pair%%:*}"
  label="${pair##*:}"
  if [ -f "$pidfile" ]; then
    leader="$(cat "$pidfile")"
    if kill -0 -- "-$leader" 2>/dev/null; then
      ok "$label: running (process group $leader)"
    else
      warn "$label: stale pidfile (group $leader is gone) - run scripts/stop.sh"
    fi
  else
    info "$label: stopped"
  fi
done

for pair in "$BACKEND_PORT:backend" "$FRONTEND_PORT:frontend"; do
  port="${pair%%:*}"
  label="${pair##*:}"
  if port_in_use "$port"; then
    info "$label port $port: LISTENING"
  else
    info "$label port $port: free"
  fi
done

if [ -f "$RUN_DIR/last-fail-stage" ]; then
  warn "last startup failure stage: $(cat "$RUN_DIR/last-fail-stage")"
fi
