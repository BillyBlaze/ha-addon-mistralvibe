# Mistral Vibe — Home Assistant App

Run **Mistral Vibe CLI** (Mistral AI's open-source agentic coding agent powered
by Mistral's models) directly inside Home Assistant. Talk to your smart home in
natural language through a browser terminal that has full access to entities,
services, automations and YAML configs via a custom MCP server.

## What you get

- A web terminal in the HA sidebar (no SSH, no separate IDE)
- Multi-file editing across `/config`, `/share` and `/media`
- Live entity & service inspection via the Supervisor API
- Persistent sessions, command history and conversation logs in `/data/vibe`
- Open-source, Apache 2.0 licensed CLI on top of Mistral's current model catalog
- A read-only "plan" mode for exploration without any writes

## API key & billing

Mistral Vibe supports two billing models:

### Le Chat Pro (recommended for heavy use)

Le Chat Pro includes a monthly Vibe budget that can also be used with the CLI — and therefore with this app.

1. Subscribe at https://chat.mistral.ai
2. Create an API key under **Studio → Codestral → API keys**
3. Enter this key as `mistral_api_key` in the app configuration

When the monthly budget is exhausted, Vibe is by default disabled until the next billing period. In the Mistral admin panel you can optionally enable pay-as-you-go so it continues seamlessly.

> **Note:** Le Chat Pro via partner offers (Google, Apple, Free Mobile, Orange) does not support pay-as-you-go after the budget is exhausted.

### Pay-as-you-go (Experiment / Scale plan)

For occasional use or to try things out:

1. Create an account at https://console.mistral.ai
2. Create an API key under **Studio → Organization → API keys**
3. Enter the key as `mistral_api_key`

Billed per token. Current prices at https://mistral.ai/pricing (e.g. Mistral Small 4 from $0.10/1M input tokens).

## First-time setup

1. Create a Mistral API key (see **API key & billing** above).
2. Open this app, switch to the **Configuration** tab and paste your key
   into `mistral_api_key`. Save.
3. Start the app. Open the **Web UI** (or the sidebar entry).
4. The terminal opens directly in `/config` with Vibe ready to go. Try:
   - `List all my automations`
   - `Why did motion_sensor_hallway not trigger last night?`
   - `Create an automation to turn off all lights when nobody is home`

No long-lived HA token is required — the app uses the Supervisor token
internally to authenticate the custom MCP server against Home Assistant Core.

## Configuration options

| Option | Default | Description |
| --- | --- | --- |
| `mistral_api_key` | *(required)* | Your Mistral API key. Stored in `/data/vibe/.env`, never sent anywhere except `api.mistral.ai`. |
| `active_model` | `mistral-medium-latest` | Any Mistral model id (e.g. `mistral-medium-latest`, `mistral-large-4`, `mistral-small-latest`) from https://docs.mistral.ai/models. Validated against the live API at startup — an id that no longer exists aborts the start with a clear log message. Switch on the fly inside Vibe with `/config`. |
| `default_agent` | `default` | `default` asks before every tool call. `plan` is a fully read-only agent — Vibe can look around but cannot edit, run shells or call services. |
| `auto_approve` | `false` | When `true`, Vibe skips the confirmation prompt before running tools. **Convenient but dangerous.** Leave off unless you really know what you're doing. |
| `auto_update_cli` | `true` | Lets Vibe self-update on launch when a newer release is on PyPI. Disable to pin the version that ships with the app. |
| `enable_telemetry` | `false` | Forwarded to Vibe as the `enable_telemetry` config flag. Off by default. |
| `log_level` | `info` | Controls the verbosity of the underlying `ttyd` server (`trace`, `debug`, `info`, `notice`, `warning`, `error`, `fatal`). |
| `terminal_font_size` | `14` | Font size of the web terminal in pixels (10-24). |
| `terminal_theme` | `dark` | Color theme of the web terminal: `dark` or `light`. |
| `reset_data` | `false` | When `true`, `/data/vibe` is wiped on the next start (config, history, session logs). Set back to `false` afterwards. |
| `session_persistence` | `true` | Keep the terminal session alive in tmux when the browser tab closes. |
| `auto_launch` | `new` | What happens when the web terminal opens: `new` starts a fresh Vibe session, `continue` resumes the last one, `off` opens a plain shell. |
| `working_directory` | `/config` | Directory Vibe starts in and headless tasks run from. Must be a mapped folder (`/config`, `/share`, `/media`). |
| `default_task_model` | *(empty)* | Model for headless tasks sent to `POST /task`. Empty = the app's `active_model`. |
| `task_max_runtime_minutes` | `30` | Max runtime of a headless task (1-240 min) before it is killed. |
| `task_token` | *(empty = random, persisted)* | Bearer token required for `POST /task`. Empty generates a random one on first boot into `/data/vibe/.env` and reuses it across restarts/updates (read it in the app terminal: `grep TASK_TOKEN /data/vibe/.env`). Set your own for a stable, automation-friendly value. |
| `mcp_source` | `builtin` | Where Vibe gets its HA tools: `builtin` runs a local ha-mcp server inside this app (loopback only); `external` connects to your own ha-mcp server — see below. |
| `external_mcp_url` | *(empty)* | Streamable-HTTP MCP endpoint of the external ha-mcp server (required when `mcp_source: external`), e.g. the HA-MCP HACS integration's private URL. |
| `external_mcp_token` | *(empty)* | Optional bearer token for the external MCP server (`Authorization: Bearer …`). Leave empty for secret-path URLs. Stored in `/data/vibe/.env`, never in `config.toml`. |

Every option above maps 1:1 to a key the init script writes into
`/data/vibe/config.toml` or `/data/vibe/.env` — so you can also edit them
directly in a Vibe session if you want full control.

## File-system layout inside the app

| Path | Purpose |
| --- | --- |
| `/config` | Your Home Assistant configuration (mounted RW). Vibe's working dir. |
| `/share` | Shared data (mounted RW). |
| `/media` | Media folder (mounted RW). |
| `/ssl` | TLS certificates (mounted RO). |
| `/data/vibe` | Vibe state: `config.toml`, `.env`, `agents/`, `prompts/`, `logs/session/`, command history. Persists across restarts and updates. |

## Architecture

```
 ┌───────────────────┐ HTTP    ┌────────────────────────┐
 │  HA Frontend      │────────▶│  Supervisor Ingress    │
 │  (sidebar panel)  │◀────────│  (/api/hassio_ingress) │
 └───────────────────┘         └──────────┬─────────────┘
                                          │
                                          ▼
                              ┌──────────────────────────┐
                              │  proxy :7681             │
                              │  ├─ ttyd :7682 (desktop) │
                              │  └─ ttyd :7683 (mobile)  │
                              │     └─ tmux → bash       │
                              │        └─ vibe-launcher  │
                              │           └─ mistral-vibe│
                              └──────────┬───────────────┘
                                         │ streamable-http (127.0.0.1:9584)
                                         ▼
                              ┌──────────────────────────┐
                              │  ha-mcp-web :9584        │  ──REST──▶  HA Core
                              │  (ha-mcp, loopback only) │   /api/states
                              └──────────────────────────┘   /api/services
```

The proxy on :7681 routes by User-Agent (mobile → :7683, everything else →
:7682), strips cache headers, and exposes `POST /task` (bearer-token protected),
which appends to `/data/vibe/task-queue.jsonl` — tailed by `vibe-stdin-runner`
into a `vibe --auto-approve --prompt ...` run.

`vibe-launcher` is the entry-point that loads the API key from `.env`,
applies the `auto_approve` / `default_agent` flags from app options and
execs the CLI. The HA bridge is [ha-mcp](https://github.com/homeassistant-ai/ha-mcp).
In the default `builtin` mode, `ha-mcp-web` runs as a loopback-only service
inside this container on `127.0.0.1:9584`; Vibe connects via
`[[mcp_servers]] transport = "streamable-http"` in `config.toml`. The service
gets `HOMEASSISTANT_URL` / `HOMEASSISTANT_TOKEN` (the Supervisor token) from
`/data/vibe/.env` — no credential is stored in `config.toml`.

## External MCP mode

Set `mcp_source: external` and `external_mcp_url` to use your own ha-mcp server
instead — typically the **HA-MCP HACS integration**, which adds a settings GUI,
read-only mode and per-tool selection. Get the URL from the integration's
**Configure** screen (its private URL, e.g. `http://<ha-ip>:9584/private_…` (the secret path itself is the MCP endpoint — do not append `/mcp`),
with *Network access: Local network* enabled in the integration). The in-container
ha-mcp service is not started in this mode. If the external server requires a
bearer token instead of a secret path, set `external_mcp_token` — it is sent as
`Authorization: Bearer …` via `api_key_env` and stored only in `/data/vibe/.env`.
Note: the URL itself (which may embed a secret path) is written to
`/data/vibe/config.toml` (chmod 600, inside the app container only).

## Headless tasks from automations

An automation can run a one-shot Vibe task without opening the terminal — POST
a JSON object to the app's task endpoint (the app's ingress port 7681, reachable
from HA core via its add-on DNS name, e.g. `http://local-mistralvibe.local.hass.io:7681/task`).
The endpoint requires the bearer token from the `task_token` option — if the
option is empty, a random token is generated on first boot and persisted in
`/data/vibe/.env`, so it stays stable across restarts and updates (read it in
the app terminal with `grep TASK_TOKEN /data/vibe/.env`; it only changes if you
wipe `/data/vibe` via `reset_data`). Requests without a valid token get `403`:

```bash
curl -X POST "http://local-mistralvibe.local.hass.io:7681/task" \
  -H "Authorization: Bearer $TASK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Summarize all automations that changed in the last 24 hours", "run_id": "daily-summary"}'
```

Task payloads:

```json
{"prompt": "Summarize all automations that changed in the last 24 hours", "run_id": "daily-summary"}
{"prompt_file": "/share/vibe-task.md"}
{"abort": true}
```

Note: `hassio.addon_stdin` is not used — under this app's s6 init the container's
PID 1 stdin is `/dev/null`, so that service's delivery has nowhere to land. The
HTTP endpoint writes the task into a queue file the runner tails.

- `prompt` / `prompt_file` — the task (one of them required). `model` overrides
  the model per task; default is `default_task_model` (empty = the app's
  `active_model`).
- Tasks run serialized — a task arriving while one is active is rejected.
- `{"abort": true}` kills the running task.
- Runtime is capped by `task_max_runtime_minutes` (default 30, max 240).
- Transcripts are written to `/data/vibe/task-logs/<run_id>.log`.
- Outcomes fire as HA events: `mistralvibe_runner_ready`, `mistralvibe_run_started`,
  `mistralvibe_run_finished` (carries `run_id`, `aborted`, `exit_code`, `log`),
  `mistralvibe_run_rejected`. React to them in automations, e.g. trigger on
  `mistralvibe_run_finished`.

Tasks run with `--auto-approve` — they can call HA services. Only send prompts
you trust, and prefer `default_agent: plan`-style read-only prompts for
unattended runs.

## Switching models on the fly

Inside a Vibe session, type `/config`. The model selected in the app options
is pre-registered in `/data/vibe/config.toml`; to switch between several
models without restarting, add more `[[models]]` blocks to that file (see
below) and pick one with `/config`.

You can also add custom providers (Ollama, vLLM, on-prem Mistral) by editing
the `[[providers]]` and `[[models]]` blocks in that file. Local inference is
fully supported.

## Security notes

- **Mistral API key** — stored in `/data/vibe/.env` (chmod 600, root-readable only).
- **HA Supervisor token** — stored in `/data/vibe/.env` (chmod 600) and passed only to the loopback ha-mcp process environment (`HOMEASSISTANT_TOKEN`). It is not written to `config.toml` or anywhere on the network-reachable config.
- **`hassio_role: manager`** — the app has the same Supervisor access as the official Studio Code Server app. This is required so the MCP server can manage entities, services and automations.
- **`ha_call_service`** — the MCP server can call any HA service, including destructive ones like `homeassistant.stop`. For read-only inspection, use `default_agent: plan`.
- **`ha_restart`** — can restart HA without confirmation when `auto_approve: true` is set. By default `auto_approve: false`.
- **AppArmor** — enabled. The profile grants only the capabilities s6/ttyd need (no `net_admin`/`net_raw`), limits networking to TCP/UDP/unix sockets, and allows writes only under `/data`, `/config`, `/share`, `/media`, `/root`, `/tmp`, `/usr/local` and `/opt` (the latter two so Vibe CLI self-updates work); everything else is read-only or denied.
- **Headless task endpoint** — `POST /task` on the ingress port requires `Authorization: Bearer <task_token>` (403 otherwise) and caps the body at 1 MB. Without this, any other add-on on the hassio network could enqueue a task that runs `vibe --auto-approve` as root with `/config` mounted read-write.
- **External MCP mode** — in `mcp_source: external` the app forwards all HA tool calls to your external ha-mcp server; anyone who can reach *that* server's URL can drive HA through it. Use the integration's local-network/private URL (not a public remote URL) and keep its access restricted.
- **`auto_approve: false`** — the default. Vibe asks before every tool call. Only enable it if you know what you are doing.

## Differences vs. the Claude Code app

| Aspect | `claudecode` (robsonfelix) | `mistralvibe` (this) |
| --- | --- | --- |
| Engine | Claude Code (Anthropic, closed) | Mistral Vibe CLI (Apache 2.0, open) |
| Default model | Claude Sonnet | Mistral Medium (latest) |
| Auth | Anthropic OAuth (long URL flow) | Mistral API key in app options |
| Local inference | No | Yes (via Ollama / vLLM / on-prem) |
| HA bridge | hass-mcp via stdio | [ha-mcp](https://github.com/homeassistant-ai/ha-mcp) (86 tools) via loopback HTTP |
| Web UI | ttyd terminal in ingress | ttyd terminal in ingress |
| State dir | `/data/claude` | `/data/vibe` |

The two apps can be installed side-by-side — they use different slugs and
different state directories.

## Troubleshooting

- **"No mistral_api_key configured" on start** — open the app's
  Configuration tab, paste a key, save, then restart.
- **Terminal opens but `vibe` says it can't reach `api.mistral.ai`** — check
  the host's outbound network. The app does not require any port forwards;
  it only needs HTTPS egress.
- **`hass` MCP tools fail with 401** — the `SUPERVISOR_TOKEN` is rotated
  whenever the app restarts. A simple app restart fixes it.
- **Want to start clean** — stop the app, delete `/data/vibe`, start again.
  Your app options will rebuild the config; only command history and
  session logs are lost.

## Credits

- [Mistral AI](https://mistral.ai) — Mistral models and Mistral Vibe CLI
- [tsl0922/ttyd](https://github.com/tsl0922/ttyd) — browser terminal
- [robsonfelix/robsonfelix-hass-addons](https://github.com/robsonfelix/robsonfelix-hass-addons) — the Claude Code app this is structurally based on
