#!/usr/bin/env bash
# Serve this repository over dumb-HTTP git so the Home Assistant Supervisor can
# clone it as a custom app repository — the HA-MCP-driven dev loop:
#
#   1. Start this on the dev PC:        scripts/dev-serve.sh [port]   (default 8000)
#   2. In HA-MCP call the app tool with action=add_repository,
#      repository=http://<this-pc-ip>:8000
#   3. action=install with the local_ slug, then action=start.
#   4. Iterate: edit, commit, re-run `git update-server-info` (or just restart
#      this script), bump `version` in mistralvibe/config.yaml, then
#      action=reload repositories + action=update in HA-MCP.
#
# Dumb HTTP works because the Supervisor clones with git and we publish
# info/refs via `git update-server-info`. Needs the repo to have at least one
# commit on the current branch.
set -euo pipefail

PORT="${1:-8000}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

git update-server-info
IP="$(hostname -I | awk '{print $1}')"
echo "Serving ${REPO_ROOT} at http://${IP}:${PORT}/ (Ctrl+C to stop)"
echo "Add this as an app repository in HA-MCP: http://${IP}:${PORT}"
exec python3 -m http.server "${PORT}"
