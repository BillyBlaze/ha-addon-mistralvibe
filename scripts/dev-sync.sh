#!/usr/bin/env bash
# Sync the mistralvibe app to a Home Assistant OS host's local app repository
# via the Samba share (local_apps) — PC -> HA direction, no firewall changes,
# no SSH keys. Fast local dev loop: no GitHub, no branches, no registry.
#
# Usage:
#   scripts/dev-sync.sh            # reads ~/.ha-dev-sync.env (chmod 600)
#   HA_HOST=... SMB_USER=... SMB_PASS=... scripts/dev-sync.sh   # or env vars
#
# Never pass credentials as arguments or put them in this repo — command-line
# args land in shell history and the env file stays outside the repo.
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

ENV_FILE="${HOME}/.ha-dev-sync.env"
[ -f "${ENV_FILE}" ] && . "${ENV_FILE}"

HA_HOST="${HA_HOST:?set HA_HOST in ${ENV_FILE} or the environment}"
SMB_USER="${SMB_USER:?set SMB_USER in ${ENV_FILE} or the environment}"
SMB_PASS="${SMB_PASS:?set SMB_PASS in ${ENV_FILE} or the environment}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec uv run --quiet --with smbprotocol python3 \
    "${REPO_ROOT}/scripts/smb_sync.py" "${HA_HOST}" "${SMB_USER}" "${SMB_PASS}" \
    "${REPO_ROOT}/mistralvibe"
