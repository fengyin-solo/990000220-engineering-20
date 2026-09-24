#!/usr/bin/env bash
# Shared helpers for blog lifecycle scripts (dev.sh / prod.sh / stop.sh / status.sh).
# Every lifecycle stage prints an explicit [OK] / [FAIL:<stage>] result and the
# scripts exit non-zero at the first failing stage.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
RUN_DIR="$ROOT_DIR/.run"
BACKEND_LOG="$RUN_DIR/backend.log"
FRONTEND_LOG="$RUN_DIR/frontend.log"

BACKEND_PORT="${PORT:-3001}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"

# --- output ---------------------------------------------------------------

stage() { printf '\n[STAGE %s] %s\n' "$1" "$2"; }
ok()     { printf '[OK] %s\n' "$1"; }
info()   { printf '[..] %s\n' "$1"; }
warn()   { printf '[WARN] %s\n' "$1"; }
fail()   { printf '[FAIL:%s] %s\n' "$1" "$2"; }

die() {
  local stage_name="$1"; shift
  fail "$stage_name" "$*"
  mkdir -p "$RUN_DIR"
  printf '%s\n' "$stage_name" > "$RUN_DIR/last-fail-stage"
  exit 1
}

# --- runtime artifacts -----------------------------------------------------

ensure_run_dir() {
  mkdir -p "$RUN_DIR" || die "cleanup" "cannot create runtime directory $RUN_DIR"
}

# Kill a recorded process group and remove its pidfile/log links.
# $1: pidfile, $2: human label
kill_recorded_group() {
  local pidfile="$1" label="$2"
  [ -f "$pidfile" ] || return 1
  local leader
  leader="$(cat "$pidfile" 2>/dev/null || true)"
  if [ -n "$leader" ] && kill -0 -- "-$leader" 2>/dev/null; then
    info "stopping $label (process group $leader)"
    kill -TERM -- "-$leader" 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 -- "-$leader" 2>/dev/null || break
      sleep 0.2
    done
    if kill -0 -- "-$leader" 2>/dev/null; then
      warn "$label did not stop gracefully, sending SIGKILL"
      kill -KILL -- "-$leader" 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile"
  return 0
}

# Remove a stale pidfile only if its process group is gone.
# $1: pidfile
reap_stale_pidfile() {
  local pidfile="$1"
  [ -f "$pidfile" ] || return 0
  local leader
  leader="$(cat "$pidfile" 2>/dev/null || true)"
  if [ -z "$leader" ] || ! kill -0 -- "-$leader" 2>/dev/null; then
    warn "removing stale pidfile: $pidfile"
    rm -f "$pidfile"
  fi
}

# Start a command in its own process group, recording the group leader pid.
# $1: pidfile  $2: logfile  $3...: command
start_group() {
  local pidfile="$1" logfile="$2"; shift 2
  setsid "$@" </dev/null >"$logfile" 2>&1 &
  local leader=$!
  echo "$leader" > "$pidfile"
}

# --- checks ---------------------------------------------------------------

validate_port() {
  local name="$1" value="$2"
  case "$value" in
    ''|*[!0-9]*) die "config" "$name port '$value' must be an integer (1-65535)";;
  esac
  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    die "config" "$name port must be between 1 and 65535, got $value"
  fi
}

# Returns 0 if the TCP port is currently accepting connections.
port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$"
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -Pn >/dev/null 2>&1
    return
  fi
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1
    return
  fi
  node -e 'const net=require("net");const s=net.connect(process.argv[1]);s.on("connect",()=>{s.end();process.exit(0)});s.on("error",()=>process.exit(1));s.setTimeout(500,()=>process.exit(1))' "$port"
}

# $1: port, $2: pidfile (service that should own the port), $3: service label
require_port_free() {
  local port="$1" pidfile="$2" label="$3"
  if port_in_use "$port"; then
    if [ -f "$pidfile" ]; then
      local leader
      leader="$(cat "$pidfile" 2>/dev/null || true)"
      if [ -n "$leader" ] && kill -0 -- "-$leader" 2>/dev/null; then
        die "port-check" "$label is already running on port $port (pidfile $pidfile). Run scripts/stop.sh first"
      fi
      warn "port $port in use with a stale pidfile; cleaning the stale entry"
      kill_recorded_group "$pidfile" "stale $label" || true
      sleep 0.5
      if port_in_use "$port"; then
        die "port-check" "port $port is in use by a process not managed by these scripts; free it and retry"
      fi
    else
      die "port-check" "port $port is already in use by another process; stop it, use scripts/stop.sh, or set PORT / FRONTEND_PORT"
    fi
  fi
  ok "port $port is free"
}

check_node() {
  command -v node >/dev/null 2>&1 || die "dependencies" "node is not installed or not on PATH (Node.js 18+ required)"
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$major" -lt 18 ]; then
    die "dependencies" "Node.js 18+ required, found $(node -v)"
  fi
  ok "node $(node -v)"
}

check_backend_deps() {
  (cd "$BACKEND_DIR" && node -e '
    for (const m of ["express","cors","jsonwebtoken"]) {
      try { require.resolve(m); }
      catch { console.error("missing backend package: " + m); process.exit(1); }
    }
    // better-sqlite3 is a native addon: actually load it to catch a binary
    // built for another platform (invalid ELF header / ABI mismatch).
    try { require("better-sqlite3"); }
    catch (err) {
      console.error("better-sqlite3 native addon cannot load: " + err.message + " (try: npm rebuild better-sqlite3)");
      process.exit(1);
    }
  ') || die "dependencies" "backend dependencies incomplete or native addon unusable; run: npm install / npm rebuild better-sqlite3 (in $BACKEND_DIR)"
  ok "backend dependencies present"
}

check_frontend_deps() {
  [ -x "$FRONTEND_DIR/node_modules/.bin/vite" ] || die "dependencies" "frontend dependencies incomplete; run: npm install (in $FRONTEND_DIR)"
  (cd "$FRONTEND_DIR" && node -e '
    const modules = ["vue","vite","@vitejs/plugin-vue","pinia","vue-router","element-plus","axios","marked"];
    for (const m of modules) {
      try { require.resolve(m); }
      catch { console.error("missing frontend package: " + m); process.exit(1); }
    }
    // Vite also needs platform-native binaries (rollup/esbuild optional deps);
    // a node_modules copied from another OS fails here rather than at startup.
    try { require("rollup"); require("esbuild"); }
    catch (err) { console.error("frontend native toolchain unavailable: " + err.message); process.exit(1); }
  ') || die "dependencies" "frontend dependencies incomplete or installed for another platform; run: npm install (in $FRONTEND_DIR)"
  ok "frontend dependencies present"
}

check_storage() {
  node -e '
    try {
      const { ensureStorage } = require(process.argv[1]);
      const dir = ensureStorage();
      console.log(dir);
    } catch (err) {
      console.error(err.message);
      process.exit(1);
    }
  ' "$BACKEND_DIR/db/init.js" >/dev/null || die "storage" "storage directory $BACKEND_DIR/data is missing or not writable"
  ok "storage directory writable ($BACKEND_DIR/data)"
}

run_db_init() {
  (cd "$BACKEND_DIR" && node db/init.js) >/dev/null || die "database" "database initialization failed; see messages above"
  ok "database schema initialized ($BACKEND_DIR/data/blog.db)"
}

# Idempotent seed. Pass --reset to wipe articles first.
run_seed() {
  local extra="${1:-}"
  local output
  if ! output="$(cd "$BACKEND_DIR" && node db/seed.js $extra)"; then
    printf '%s\n' "$output"
    die "seed" "seed import failed; existing articles were preserved"
  fi
  ok "$(printf '%s' "$output" | tail -n 1 | sed 's/^\[seed\] //')"
}

# Poll an HTTP endpoint until it answers, or fail the given stage.
# $1: url  $2: stage  $3: label  $4: timeout seconds
wait_http() {
  local url="$1" stage_name="$2" label="$3" timeout="${4:-30}"
  for _ in $(seq 1 "$((timeout * 2))"); do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      ok "$label is responding at $url"
      return 0
    fi
    sleep 0.5
  done
  fail "$stage_name" "$label did not become ready within ${timeout}s (see $RUN_DIR)"
  return 1
}
