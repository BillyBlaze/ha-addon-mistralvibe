# Development scripts

How to iterate on the `mistralvibe/` app against a live Home Assistant host,
and how the ttyd web-client patch works. All commands run from the repo root.

## Fast loop: Samba sync — `dev-sync.sh`

The recommended loop — no git push, no GitHub, no registry:

```bash
# one-time: create ~/.ha-dev-sync.env (chmod 600, never commit it)
#   HA_HOST=192.168.1.10   # your HA host's IP
#   SMB_USER=...
#   SMB_PASS=...
# requires the official Samba share app running on the HA host with a
# user configured, exposing the `local_apps` share

scripts/dev-sync.sh        # mirrors mistralvibe/ -> //HA_HOST/local_apps/mistralvibe
```

Then update the installed copy so the Supervisor re-runs from the synced
sources. On HA 2026.11+ the repository lives under **Settings → Apps →
Install app → ⋮ → Repositories** (older HA: **App Store → ⋮ →
Repositories**); installed apps are at `/config/apps/installed`. Bump
`version` in `mistralvibe/config.yaml`, then update via the app's **Update**
action or the HA MCP tools: `ha_manage_app(action="check_updates")` then
`ha_manage_app(action="update", slug="local_mistralvibe")`. Use
`action="rebuild"` only when the Dockerfile itself changed — rebuilds can
exceed a 60 s tool budget; just retry the call.

- `smb_sync.py` is the underlying sync used by `dev-sync.sh`: it mirrors the
  local `mistralvibe/` dir to `//<host>/local_apps/mistralvibe`, deleting
  remote files that no longer exist locally.
- Credentials live only in `~/.ha-dev-sync.env` (chmod 600) or the
  environment — never in the repo and never as command-line arguments
  (argv lands in shell history). `dev-sync.sh` reads the env file or
  `HA_HOST`/`SMB_USER`/`SMB_PASS` from the environment.
- To call `smb_sync.py` directly for a one-off:
  `uv run --with smbprotocol python3 scripts/smb_sync.py <host> <user> <password>`
  (password as argv only for throwaway use — prefer the env file).

## Alternative: serve the repo over HTTP — `dev-serve.sh`

Serves this git repo over dumb HTTP so the Supervisor can clone it as a
custom app repository:

```bash
scripts/dev-serve.sh [port]    # default 8000
# add http://<this-pc-ip>:<port> as an app repository in HA, install the local_ app
```

For iterations: commit, `git update-server-info` (or restart the script),
bump `version` in `mistralvibe/config.yaml`, then reload repositories + update
in HA. Slower than the Samba loop (full clone per update) — prefer
`dev-sync.sh`.

## Patching the ttyd web client — `mistralvibe/patch-ttyd-mobile.py` + `mistralvibe/ttyd-patch/`

The Dockerfile builds ttyd's web client from a pinned commit (OSC 52
clipboard fix) and then runs `patch-ttyd-mobile.py`, which injects
`mistralvibe/ttyd-patch/inject.css` into `<head>` and `inject.js` before
`</body>` of the built `index.html` (idempotent via a `ttyd-patch` marker).

**To change terminal-page behavior, edit the two files in
`mistralvibe/ttyd-patch/` — never the built HTML — then sync + rebuild.**
Currently they contain:

- `inject.css` — `100dvh` sizing; backgrounds (`html`/`body`/`#terminal-container`,
  `.xterm-viewport`, `.xterm-screen`) painted with the terminal theme color via
  `--ttyd-patch-term-bg` (`#111111` fallback) so the sub-cell remainder around the
  canvas is seamless; thin theme-colored scrollbar via standard
  `scrollbar-width`/`scrollbar-color`; `padding: 0` on the terminal for mobile UAs;
  `touch-action: pan-y` so swipes reach our handler.
- `inject.js` — touch-to-wheel translation for mobile (always `preventDefault` on
  drags, taps pass through); `viewport-fit=cover` meta patch; height/width calc that
  cuts `#terminal-container` to the visible area (top window's layout viewport via
  same-origin `window.top`, HA header excluded via `window.frameElement`, Android
  gesture-bar inset via `env(safe-area-inset-bottom)`, keyboard-open compensation for
  browsers whose `visualViewport` over-reports the keyboard); override of xterm's
  `viewport.scrollBarWidth` `|| 15` fallback on overlay-scrollbar platforms;
  DPR-change watcher; then re-dispatches `resize` so ttyd's fit addon refits xterm.

When testing in a browser, append a cache-buster (`?v=42`) — the ingress
proxy (`mistralvibe/rootfs/usr/share/vibe-proxy/proxy.py`) adds
`Cache-Control: no-store` to responses, but the URL version makes it obvious
which build you are looking at. The proxy also does UA-based routing: mobile
UAs get the ttyd instance on :7683 (tmux session `vibe-mobile`), everything
else :7682 (`vibe`).
