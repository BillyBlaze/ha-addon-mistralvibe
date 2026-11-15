#!/usr/bin/env python3
"""Sync the mistralvibe app folder to a HA host's local_apps Samba share.

Mirrors the local dir to //<host>/local_apps/mistralvibe, deleting remote
files that no longer exist locally. Used by scripts/dev-sync.sh — prefer
that wrapper.

Usage (credentials as arguments, for one-off use only — argv lands in
shell history; dev-sync.sh reads ~/.ha-dev-sync.env or env vars instead):

    uv run --with smbprotocol python3 scripts/smb_sync.py <host> <user> <password> [local_app_dir]

Requires the official Samba share app on the HA host exposing `local_apps`.
"""
import os
import sys
import smbclient
from smbprotocol.exceptions import SMBOSError

host, user, password = sys.argv[1], sys.argv[2], sys.argv[3]
local_dir = sys.argv[4] if len(sys.argv) > 4 else os.path.join(
    os.path.dirname(__file__), "..", "mistralvibe")
local_dir = os.path.abspath(local_dir)
remote_root = f"//{host}/local_apps/mistralvibe"

smbclient.register_session(host, username=user, password=password)


def remote_walk(path):
    try:
        for entry in smbclient.listdir(path):
            if entry in (".", ".."):
                continue
            full = f"{path}/{entry}"
            try:
                if smbclient.stat(full).st_file_attributes & 0x10:  # directory
                    yield from remote_walk(full)
                    smbclient.rmdir(full)
                else:
                    yield full
                    smbclient.remove(full)
            except SMBOSError:
                yield full
                smbclient.remove(full)
    except SMBOSError:
        return


# wipe remote copy, then upload fresh (dev loop: repo is small)
for _ in remote_walk(remote_root):
    pass
try:
    smbclient.rmdir(remote_root)
except SMBOSError:
    pass

count = 0
for root, dirs, files in os.walk(local_dir):
    rel = os.path.relpath(root, local_dir)
    rdir = remote_root if rel == "." else f"{remote_root}/{rel.replace(os.sep, '/')}"
    try:
        smbclient.mkdir(rdir)
    except SMBOSError:
        pass
    for f in files:
        if f.startswith(".git"):
            continue
        with open(os.path.join(root, f), "rb") as fh:
            smbclient.open_file(f"{rdir}/{f}", mode="wb").write(fh.read())
        count += 1

print(f"synced {count} files -> {remote_root}")
