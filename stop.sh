#!/usr/bin/env bash
# Stop the PR Dashboard server.
set -euo pipefail
cd "$(dirname "$0")"
PORT="${PORT:-4321}"
PID_FILE=".server.pid"

stopped=0
if [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null; then stopped=1; fi
if lsof -ti:"$PORT" >/dev/null 2>&1; then lsof -ti:"$PORT" | xargs kill 2>/dev/null || true; stopped=1; fi
rm -f "$PID_FILE"

[ "$stopped" = 1 ] && echo "✓ Server stopped." || echo "Nothing was running on port ${PORT}."
