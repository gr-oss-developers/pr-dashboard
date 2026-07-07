#!/usr/bin/env bash
# One-shot launcher for the PR Dashboard.
# Checks prerequisites, (re)starts the server, waits until it's live, opens the browser.
#   ./start.sh           # default port 4321
#   PORT=8080 ./start.sh # custom port
set -euo pipefail

cd "$(dirname "$0")"
PORT="${PORT:-4321}"
URL="http://localhost:${PORT}"
PID_FILE=".server.pid"
LOG_FILE="server.log"

say() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# --- preflight ---
command -v node >/dev/null 2>&1 || die "Node.js is not installed. Install Node 18+ and retry."

if [ -n "${GITHUB_CLIENT_ID:-}" ] && [ -n "${GITHUB_CLIENT_SECRET:-}" ]; then
  # Hosted mode: users sign in with GitHub; no local gh auth needed.
  say "Hosted mode — GitHub sign-in enabled (OAuth app configured)."
else
  # Local mode: reuse the gh CLI token for a single user.
  command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is not installed. See https://cli.github.com/  (or set GITHUB_CLIENT_ID/SECRET for hosted sign-in mode)"
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login   (then re-run ./start.sh)"
  say "Local mode — authenticated as $(gh api user --jq .login 2>/dev/null || echo 'github user')"
fi

# --- stop any previous instance on this port (idempotent restart) ---
if lsof -ti:"$PORT" >/dev/null 2>&1; then
  say "Stopping existing server on port ${PORT}…"
  lsof -ti:"$PORT" | xargs kill 2>/dev/null || true
  sleep 0.5
fi

# --- launch ---
say "Starting server on port ${PORT}…"
PORT="$PORT" nohup node server.js >"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"

# --- wait until it responds ---
for i in $(seq 1 30); do
  if curl -s -o /dev/null "$URL"; then
    say "Dashboard is live at ${URL}"
    # open the default browser (macOS: open, Linux: xdg-open)
    if command -v open >/dev/null 2>&1; then open "$URL"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"; fi
    echo
    echo "  Logs:  tail -f $(pwd)/${LOG_FILE}"
    echo "  Stop:  ./stop.sh"
    exit 0
  fi
  sleep 0.3
done

die "Server did not respond within 9s. Check ${LOG_FILE}:
$(cat "$LOG_FILE" 2>/dev/null || true)"
