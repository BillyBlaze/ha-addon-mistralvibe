#!/usr/bin/env bash
# Sync the mistralvibe app to a Home Assistant OS host's local app repository
# (/local_apps, shown by the SSH/Samba app) for a fast local dev loop — no
# GitHub, no branches, no registry.
#
# Usage:
#   scripts/dev-sync.sh <ha-host> [ssh-port] [ssh-user]
# Example:
#   scripts/dev-sync.sh 192.168.1.50 22222 root
#
# Prereq on the HA host: the official Terminal & SSH app (or Samba app)
# installed and running. Auth = the credentials configured in that app.
#
# After syncing: in HA go to Settings -> Apps -> App Store -> menu (⋮) ->
# Reload. The app appears under "Local apps". Install it — the Supervisor
# builds the image from the local Dockerfile on the HA host (first build is
# slow, later builds are cached). Bump `version` in mistralvibe/config.yaml
# when you want the Update button to pick up changes on an installed copy.
set -euo pipefail

HA_HOST="${1:?usage: dev-sync.sh <ha-host> [ssh-port] [ssh-user]}"
SSH_PORT="${2:-22222}"
SSH_USER="${3:-root}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${REPO_ROOT}/mistralvibe"
REMOTE_DIR="/local_apps/mistralvibe"

[ -d "${APP_DIR}" ] || { echo "app dir not found: ${APP_DIR}" >&2; exit 1; }

rsync -az --delete \
    -e "ssh -p ${SSH_PORT} -o StrictHostKeyChecking=accept-new" \
    "${APP_DIR}/" "${SSH_USER}@${HA_HOST}:${REMOTE_DIR}/"

echo "Synced ${APP_DIR}/ -> ${SSH_USER}@${HA_HOST}:${REMOTE_DIR}/"
echo "Next: HA -> Settings -> Apps -> App Store -> (⋮) -> Reload -> 'Local apps' -> install/update."
