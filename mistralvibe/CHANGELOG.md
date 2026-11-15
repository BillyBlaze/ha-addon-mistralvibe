# Changelog

## 1.0.0-beta2 — 2026-11-15

### Security
- `POST /task` (headless tasks) now requires `Authorization: Bearer <token>` and answers `403` otherwise; body capped at 1 MB, invalid JSON gets `400`. The token is the new `task_token` option — empty generates a random one at startup into `/data/vibe/.env` (read it in the app terminal: `grep TASK_TOKEN /data/vibe/.env`). Previously any container on the hassio network could enqueue a `vibe --auto-approve` run as root with `/config` RW.
- `run_id` of headless tasks is sanitized to `[A-Za-z0-9_-]` (max 64 chars) before it becomes a log filename — was a path-traversal write as root
- AppArmor profile trimmed: dropped `net_admin`/`net_raw` capabilities and the legacy `/homeassistant/` paths; networking limited to TCP/UDP/unix sockets
- Ingress proxy: the `Cache-Control: no-store` rewrite now buffers until the full response header block arrives — a partial first chunk no longer bypasses it; `assert` in the task handler replaced with a real `400` check

### Changed
- Dockerfile: `mistral-vibe==3.1.2`, `fastmcp==4.2.0`, `httpx==0.28.1` pinned so builds of the same tag are reproducible (runtime CLI updates still via `auto_update_cli`)
- `config.yaml`: removed keys the add-on linter rejects as default-valued (`apparmor`, `boot`, `full_access`, `host_dbus`, `host_network`, `host_pid`, `init`) — behavior unchanged, CI lint passes
- `HEALTHCHECK` now also probes the ttyd backends `:7682`/`:7683`, not just the proxy on `:7681`
- `ha_get_error_log` tails `/config/home-assistant.log` via seek (was: read the whole file into memory); `ha_get_entity`/`ha_get_history` URL-encode the entity id
- ttyd-patch console diagnostics (`ttyd-patch fit/boot/wheel`) now only print with `?ttydpatch=debug` in the URL

### Fixed
- Init script: models-catalog curl `--connect-timeout 5` raised to `8` (`--max-time 15`) — the real connect time to api.mistral.ai from a HA host is ~6 s, so boot-time fetches timed out and the dynamic catalog silently degraded to a single model
- Auto-generated `task_token` is now persisted in `/data/vibe/.env` and reused across restarts/updates — previously an empty option rotated the token on every start, which would have broken every `/task` automation on each app restart. Set the option for a stable, user-chosen token

### Docs
- `DOCS.md`: options table completed (`terminal_font_size`, `terminal_theme`, `reset_data`, `session_persistence`, `task_token`); architecture diagram shows proxy `:7681` → ttyd `:7682`/`:7683` plus the `/task` queue path; headless-task section documents the bearer token with a curl example; AppArmor security note corrected to match the profile
- `scripts/DOCS.md` + `dev-sync.sh` header: current HA 2026.11 store flow (Settings → Apps → Install app → ⋮ → Repositories; installed apps at `/config/apps/installed`, update via the app's Update action)
- Translations: `task_token` added (en/de); `default_task_model` description no longer references `hassio.addon_stdin`

## 1.0.0-beta1 — 2026-11-15

### Added
- Mobile terminal patch injected into the ttyd web client at image build time (`patch-ttyd-mobile.py` + `ttyd-patch/inject.css` / `inject.js`, edit the templates and rebuild):
  - touch-to-scroll on mobile: vertical swipes are translated into wheel events for xterm/tmux; taps still pass through so links stay clickable
  - virtual-keyboard handling: on `visualViewport` resize the terminal is cut to the visible height (top window viewport via same-origin `window.top`, HA header excluded via `window.frameElement`, Android gesture-bar inset via `env(safe-area-inset-bottom)` + `viewport-fit=cover`), then xterm is refit
  - page/terminal background follows the active terminal theme (`--ttyd-patch-term-bg` from `term.options.theme.background`, HA dark `#111111` as pre-JS fallback) so no white flash and no contrasting seam around the canvas
- Mobile terminal now runs under tmux with its own session name `vibe-mobile` (desktop keeps `vibe`, so the two never attach to each other)
- Ingress proxy adds `Cache-Control: no-store` to responses (fixes stale cached pages when testing) and routes by UA: `iPhone|iPad|Android|Mobile` → mobile ttyd :7683, otherwise desktop :7682
- Model catalog is now dynamic, not hardcoded: at startup every chat+function-calling model from the live `api.mistral.ai/v1/models` is registered as a `[[models]]` entry (deduplicated per model card), so Vibe's model picker mirrors the current Mistral catalog — e.g. `mistral-large-4` shows up with its low/medium/high thinking levels. `active_model` remains the only user-facing choice (default model, resolved live; stable `-latest` aliases don't go stale). Thinking levels are left to Vibe's own known-models table (kept current via `auto_update_cli`). If the API is unreachable, the app warns and registers only `active_model` as-is (no cache — a stale catalog is worse than a short one; models curl timeout 10s so a down API can't stall startup)
- Dev docs in `scripts/DOCS.md` (Samba dev loop, HTTP repo serving, ttyd patch workflow)

### Changed
- `config.yaml`: deprecated `map: config` entry replaced by the new-style `map: [{type: homeassistant_config, path: /config, read_only: false}]` — same mount point, no more Supervisor deprecation warning
- Init script: HA version and Mistral model list are fetched in parallel with timeouts; `/config` mount is guarded so a missing mount no longer aborts startup

### Fixed
- Ingress proxy no longer corrupts HTTP framing when rewriting responses (earlier body injection truncated pages and broke `Content-Length`; now headers only)
- ttyd web patch: the sub-character-cell remainder right of the last column / below the last row is painted with the terminal theme background instead of xterm's hardcoded black, so the grid edge is seamless (stretching the canvas instead renders an opaque black band — WebGL `alpha:false`)
- ttyd web patch: on overlay-scrollbar platforms (Android/iOS) xterm's `scrollBarWidth` `|| 15` fallback is overridden with the true measurement (0), so the fit addon no longer reserves a phantom 15px — previously a visible gap at the right end of the status bar
- ttyd web patch: the native scrollbar is painted with the theme color via standard `scrollbar-width: thin` + `scrollbar-color` (Chrome 121+/Brave ignore `::-webkit-scrollbar` pseudos, which rendered gray)
- ttyd web patch: with the virtual keyboard open the terminal is sized to `visualViewport.height` + half the browser chrome (Brave's visual viewport also subtracts its hidden bottom bar, which left a ~100px void above the keyboard), so the whole terminal including the status line stays above the keyboard

## 0.9.1 — 2026-11-14

### Changed
- `active_model` is now a free-text option (default `mistral-medium-latest`) instead of a fixed dropdown. The chosen model is validated against the live `api.mistral.ai/v1/models` list at startup; an id that no longer exists aborts the start with a clear log message
- Removed the hardcoded Devstral/Magistral model catalog from `config.toml` — only the selected model is registered now

### Fixed
- Stale model ids (`devstral-small-2`, `devstral-2`, `magistral-medium` and their fallbacks) that no longer exist at api.mistral.ai
- MCP server `ha_get_error_log`: reads `/config/home-assistant.log` directly (HA 2025.11+ removed the `/api/error_log` endpoint, which 404s), API kept as fallback for older HA
- MCP server `ha_call_service`: returns HA's error message on 400/500 instead of raising an opaque error
- AppArmor: `/opt/**` and `/usr/local/bin/**` are now writable so `auto_update_cli` runtime self-updates don't fail with EACCES

### Added
- CI: `lint.yml` (official add-on linter + hadolint) and `tests.yml` (smoke checks in `.github/scripts/smoke.sh`: shell syntax of all rootfs scripts, python syntax of MCP server/proxy, YAML + options/schema/translation coverage, config.toml template renders to valid TOML)
- Headless tasks from HA automations: `stdin: true` + `vibe-stdin-runner` service. Send JSON to `hassio.addon_stdin` (`{"prompt": "..."}`, `{"prompt_file": "..."}`, `{"abort": true}`) to run `vibe --prompt` one-shots; results fire as `mistralvibe_run_started/finished/rejected` events, transcripts in `/data/vibe/task-logs/`. New options: `default_task_model`, `task_max_runtime_minutes`
- Browser terminal now serves a custom ttyd web client (pinned ttyd commit, built with yarn/corepack) with OSC 52 clipboard support — copy/paste in the ingress terminal works now
- New options: `auto_launch` (`off`/`new`/`continue`, default `new`) and `working_directory` (default `/config`), honored by the launcher and the headless task runner

## 0.9.0 — 2026-11-07

### Changed
- **Base image migrated from Alpine/HA base to `debian:bookworm-slim`.**
  The mistral-vibe PyPI package ships Rust extensions and a rusty_v8 prebuilt
  binary that does not exist for musl (`librusty_v8_*_alpine-linux-musl.a.gz`
  returns HTTP 404 on every release), making the Alpine/HA-base build impossible.
  Debian/glibc installs prebuilt manylinux wheels via uv with no Rust toolchain
  and no V8 source build.
- Python runtime now provisioned via uv (managed Python 3.13, tool installs in
  `/opt`), replacing the base-image Python.
- s6-overlay v2.1.0.2 installed from upstream tarballs with a merged-usr-safe
  procedure: extraction to a staging directory, then copying into `/usr/bin`
  so Debian's `/bin → usr/bin` symlink is never clobbered.

### Added
- bashio v0.19.0 installed explicitly (preinstalled in HA base images, missing
  on Debian). Required by all rootfs service scripts.
- ttyd download now maps HA build arch to the correct upstream release asset
  (`amd64 → ttyd.x86_64`, `aarch64 → ttyd.aarch64`, `i386 → ttyd.i686`) and
  fails the build with a clear error on unsupported architectures.

### Fixed
- `/init` is actually present at container start (s6 tarball is now extracted
  into the image root, not a subdirectory).
- s6-overlay installation no longer breaks `/bin` on merged-usr systems
  (previously `/bin/bash` disappeared at build time, causing exit code 126 at
  container start).
- All 11 s6 helper scripts under `/usr/bin` (`printcontenv`, `with-contenv`,
  `justc-envdir`, `fix-attrs`, `logutil-*`, `with-retries`) are installed;
  previously lost to an over-broad tar exclude pattern, which aborted s6 init
  with `unable to spawn printcontenv`.
- AppArmor profile grants execute (`ixr`) on `/etc/s6/**`; previously only
  `/etc/cont-init.d/**`, `/etc/services.d/**` etc. were covered, so the kernel
  denied execution of the s6 init scripts at container start.

### Notes
- Verified working end-to-end on HA OS x86_64/amd64: image builds, container
  starts, ttyd terminal reachable via Ingress, MCP bridge authenticated via
  SUPERVISOR_TOKEN, Vibe CLI runs against a Vibe Pro API key.
- Maintainer label updated for the fork.

# Before

History inherited from the abandoned upstream repository (version numbers
there went up to 1.8.2).

## 1.8.2 — 2026-05-02

### Added
- Automatic mobile detection: iOS clients (iPhone/iPad) get tmux-free session for native touch scrolling
- TCP proxy on port 7681 routes to desktop (7682, with tmux) or mobile (7683, no tmux) ttyd

## 1.8.1 — 2026-05-02

### Changed
- m alias detaches tmux (mobile mode), v alias re-attaches to existing tmux session
- Switch freely between Vibe and bash with v and m

## 1.8.0 — 2026-05-02

### Added
- mobile command: detaches tmux for native iOS scrolling. Use 'v' to re-enter Vibe.

## 1.7.9 — 2026-05-02

### Fixed
- Increased xterm.js scrollSensitivity for better touch scrolling on iOS HA app

## 1.7.5 — 2026-04-30

### Fixed
- SUPERVISOR_TOKEN exported in bashrc so ha CLI authenticates automatically

## 1.7.4 — 2026-04-30

### Added
- ha CLI binary installed in Dockerfile (from github.com/home-assistant/cli)
- ha-logs and ha-errors aliases restored to use ha CLI

## 1.7.3 — 2026-04-30

### Changed
- CHANGELOG rewritten with full history

## 1.7.2 — 2026-04-30

### Fixed
- Documentation: replaced outdated hass-mcp references with custom MCP server
- Removed addon_config from filesystem layout (not mounted)

## 1.7.1 — 2026-04-30

### Added
- Extended security documentation: token handling, hassio_role, AppArmor, auto_approve risks

## 1.7.0 — 2026-04-30

### Fixed
- resolve_model() now falls back to hardcoded defaults if model resolution returns empty string

## 1.6.9 — 2026-04-30

### Fixed
- SUPERVISOR_TOKEN guard with 5s timeout before HA version query in init script

## 1.6.8 — 2026-04-30

### Fixed
- ha_list_areas tool name corrected in system prompt
- Dockerfile label type: addon → app
- ha-logs and ha-errors aliases now use direct Supervisor API instead of missing ha CLI

## 1.6.7 — 2026-04-30

### Added
- Shell aliases: v (vibe-launcher), ha-config, ha-logs, ha-errors

## 1.6.6 — 2026-04-30

### Added
- ha.md system prompt generated dynamically at startup including HA version and path mapping

## 1.6.5 — 2026-04-30

### Added
- Configurable terminal_font_size (10-24px) and terminal_theme (dark/light)

## 1.6.4 — 2026-04-30

### Added
- Documentation: Le Chat Pro included budget and pay-as-you-go API key setup

## 1.6.3 — 2026-04-30

### Added
- ingress_stream: true for better streaming performance
- ttyd: scrollback=20000, --ping-interval 30, --max-clients 5
- Docker HEALTHCHECK

## 1.6.2 — 2026-04-30

### Fixed
- HA_TOKEN restored in mcp_servers.env — Vibe does not inherit shell environment to MCP child processes

## 1.6.0 — 2026-04-30

### Changed
- Documentation: renamed add-on to app throughout

## 1.5.9 — 2026-04-30

### Removed
- ha_get_vibe_usage MCP tool — session logs contain no token data

## 1.5.8 — 2026-04-30

### Fixed
- Removed duplicate entries in de.yaml translations

## 1.5.5 — 2026-04-30

### Fixed
- ha.md and VIBE.md copied correctly on startup
- reset_data and session_persistence options restored in config.yaml
- Removed duplicate entries in en.yaml translations

## 1.5.1 — 2026-04-29

### Security
- HA_TOKEN removed from config.toml template — passed via inherited environment only

## 1.4.8 — 2026-04-29

### Fixed
- py3-pip added to apk packages (required for fastmcp/httpx)
- Removed invalid --mouse flag from ttyd

## 1.4.0 — 2026-04-29

### Changed
- Replaced hass-mcp with custom FastMCP server (server.py)
- ha_get_error_log limited to max 200 lines
- ha_list_entities, ha_list_automations limited to 50 results by default

## 1.0.0 — 2026-04-29

### Added
- Initial release
- Mistral Vibe CLI installed via uv tool install
- Custom MCP server for Home Assistant Core API access via Supervisor token
- Browser terminal (ttyd) via HA ingress
- App options: API key, active model, default agent, auto-approve, telemetry, CLI auto-update
- Persistent state under /data/vibe (config, history, session logs)
- AppArmor profile
- Multi-arch builds: amd64, aarch64
