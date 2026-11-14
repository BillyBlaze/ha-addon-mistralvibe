#!/usr/bin/env bash
# Sync the mistralvibe app to a Home Assistant OS host's local app repository
# via the Samba share (local_apps) — PC -> HA direction, no firewall changes,
# no SSH keys. Fast local dev loop: no GitHub, no branches, no registry.
#
# Usage:
#   scripts/dev-sync.sh <ha-host> <samba-user> <samba-password>
# Example:
#   scripts/dev-sync.sh <ha-host> <samba-user> <samba-password>
#   (never commit real hostnames, usernames or passwords — use placeholders)
#
# Prereq on the HA host: the official Samba share app installed and running,
# with a username/password set in its options.
#
# After syncing: in HA go to Settings -> Apps -> App Store -> menu (⋮) ->
# Reload. The app appears under "Local apps". Install it — the Supervisor
# builds the image from the local Dockerfile on the HA host (first build is
# slow, later builds are cached). Bump `version` in mistralvibe/config.yaml
# when you want the Update button on an installed copy.
set -euo pipefail

HA_HOST="${1:?usage: dev-sync.sh <ha-host> <samba-user> <samba-password>}"
SMB_USER="${2:?missing samba user}"
SMB_PASS="${3:?missing samba password}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec uv run --quiet --with smbprotocol python3 \
    "${REPO_ROOT}/scripts/smb_sync.py" "${HA_HOST}" "${SMB_USER}" "${SMB_PASS}" \
    "${REPO_ROOT}/mistralvibe"
