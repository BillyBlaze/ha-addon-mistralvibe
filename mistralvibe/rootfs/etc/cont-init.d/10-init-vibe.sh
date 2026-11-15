#!/usr/bin/with-contenv bashio
set -e

VIBE_HOME="/data/vibe"
ENV_FILE="${VIBE_HOME}/.env"
CONFIG_FILE="${VIBE_HOME}/config.toml"
TRUST_FILE="${VIBE_HOME}/trusted_folders.toml"
LOG_DIR="${VIBE_HOME}/logs/session"

mkdir -p "${VIBE_HOME}/agents" "${VIBE_HOME}/prompts" "${LOG_DIR}"

RESET_DATA="$(bashio::config 'reset_data')"
if [ "${RESET_DATA}" = "true" ]; then
    bashio::log.warning "Wiping ${VIBE_HOME} (reset_data=true)"
    rm -rf "${VIBE_HOME}"
    mkdir -p "${VIBE_HOME}/agents" "${VIBE_HOME}/prompts" "${LOG_DIR}"
fi


MISTRAL_API_KEY="$(bashio::config 'mistral_api_key')"
ACTIVE_MODEL="$(bashio::config 'active_model')"
DEFAULT_AGENT="$(bashio::config 'default_agent')"
AUTO_APPROVE="$(bashio::config 'auto_approve')"
AUTO_UPDATE_CLI="$(bashio::config 'auto_update_cli')"
ENABLE_TELEMETRY="$(bashio::config 'enable_telemetry')"

if [ -z "${MISTRAL_API_KEY}" ] || [ "${MISTRAL_API_KEY}" = "null" ]; then
    bashio::log.fatal "No 'mistral_api_key' configured."
    exit 1
fi

# Kick off both network lookups in parallel so a slow Mistral API does not
# add its full latency on top of the (fast, local) Supervisor call.
HA_VERSION_JSON="$(mktemp)"
MODELS_JSON_FILE="$(mktemp)"
trap 'rm -f "${HA_VERSION_JSON}" "${MODELS_JSON_FILE}"' EXIT
if [ -n "${SUPERVISOR_TOKEN}" ]; then
    curl -sf --connect-timeout 2 --max-time 5 \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        http://supervisor/core/api/config -o "${HA_VERSION_JSON}" &
else
    bashio::log.warning "SUPERVISOR_TOKEN not set, HA version unknown"
fi
# short timeouts: if the API is down we warn and register only active_model,
# we never want a slow API to stall startup. connect-timeout must exceed the
# real connect time to api.mistral.ai — measured ~6s from this host (slow
# IPv6/Cloudflare path), so 5s silently degraded the catalog to 1 model
curl -sf --connect-timeout 8 --max-time 15 \
    -H "Authorization: Bearer ${MISTRAL_API_KEY}" \
    "https://api.mistral.ai/v1/models" -o "${MODELS_JSON_FILE}" &

bashio::log.info "Writing dynamic ha.md system prompt"
wait
if [ -s "${HA_VERSION_JSON}" ]; then
    HA_VERSION=$(python3 -c "import sys,json; print(json.load(open(sys.argv[1])).get('version','unknown'))" "${HA_VERSION_JSON}" 2>/dev/null || echo "unknown")
else
    HA_VERSION="unknown"
fi

cat > "${VIBE_HOME}/prompts/ha.md" << HAMD
You are an AI assistant running inside a Home Assistant app (version ${HA_VERSION}).
You have direct access to the Home Assistant API via MCP tools prefixed with "ha_".
The Home Assistant configuration files are located in /config.
Read /config/VIBE.md at the start of each session for user-specific context.

## Path Mapping

| Path | Description | Access |
|------|-------------|--------|
| /config | HA configuration | read-write |
| /share | Shared folder | read-write |
| /media | Media files | read-write |
| /ssl | SSL certificates | read-only |
| /backup | Backups | read-only |
| /data/vibe | Vibe state dir | read-write |

## Reading Home Assistant Logs

Use ha_get_error_log(lines=50) to read logs. For filtering, pipe through bash:

\`\`\`bash
# Filter by keyword
ha core logs 2>&1 | grep -i keyword
# Errors only
ha core logs 2>&1 | grep -iE "(error|exception)"
\`\`\`

## STRICT RULES - follow these without exception

**Rule 1: NEVER call ha_get_error_log unless the user explicitly uses the words "error log", "logs" or "Fehler" in their message.**

**Rule 2: When you DO call ha_get_error_log, always pass lines=50. Never call it without a lines limit.**

**Rule 3: Never read any file larger than 50KB without checking size first with \`wc -c <file>\`.**

**Rule 4: Never list all entities at once. Always use a domain filter with ha_list_entities.**

**Rule 5: After every 5 tool calls, run /status and /compact if context usage is above 50%.**

## Available MCP tools
- ha_list_entities(domain, search, limit): list entities by domain
- ha_get_entity(entity_id): get state and attributes of a specific entity
- ha_call_service(domain, service, data): call any HA service (use this to control devices)
- ha_list_automations(search, limit): list automations
- ha_list_areas(): list all areas
- ha_get_config(): get HA core configuration
- ha_get_history(entity_id, hours): get state history for an entity
- ha_get_error_log(lines=50): get HA error log (ONLY when user explicitly asks)
- ha_restart(): restart Home Assistant (use with caution)
HAMD
if [ -d /config ] && [ ! -f "/config/VIBE.md" ]; then
    cp /usr/share/vibe-defaults/VIBE.md /config/VIBE.md
elif [ ! -d /config ]; then
    bashio::log.warning "/config is not mounted - skipping VIBE.md seed"
fi

# capture a previously generated token BEFORE .env is rewritten below, so an
# empty task_token option keeps the SAME token across restarts/updates (/data
# persists) instead of rotating it on every start — otherwise every automation
# posting to /task would break on each app restart
EXISTING_TASK_TOKEN="$(grep -E '^TASK_TOKEN=' "${ENV_FILE}" 2>/dev/null | head -1 | cut -d= -f2- || true)"

cat > "${ENV_FILE}" <<EOF
MISTRAL_API_KEY=${MISTRAL_API_KEY}
HA_URL=http://supervisor/core
HA_TOKEN=${SUPERVISOR_TOKEN}
EOF

# Bearer token required by the proxy's POST /task endpoint (headless tasks).
# Empty option = reuse the persisted generated token, or generate one on first
# boot — so /task is never open and automations don't break on restart. Set the
# option to choose your own stable token. Read it in the app terminal with:
# grep TASK_TOKEN /data/vibe/.env
TASK_TOKEN="$(bashio::config 'task_token')"
if [ -z "${TASK_TOKEN}" ] || [ "${TASK_TOKEN}" = "null" ]; then
    if [ -n "${EXISTING_TASK_TOKEN}" ]; then
        TASK_TOKEN="${EXISTING_TASK_TOKEN}"
    else
        TASK_TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
        bashio::log.info "task_token option empty — generated a random one (persisted in /data/vibe/.env; set the option to choose your own)"
    fi
fi
printf 'TASK_TOKEN=%s\n' "${TASK_TOKEN}" >> "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

if [ -z "${ACTIVE_MODEL}" ] || [ "${ACTIVE_MODEL}" = "null" ]; then
    bashio::log.fatal "No 'active_model' configured."
    exit 1
fi

bashio::log.info "Resolving model catalog via Mistral API..."

bashio::log.info "Writing Vibe config to ${CONFIG_FILE}"
# The model catalog is NOT hardcoded: every chat+function-calling model from
# the live api.mistral.ai/v1/models list is registered as a [[models]] entry
# (deduplicated per model card, alias = card name), so new Mistral models show
# up in Vibe's picker after a restart and retired ones disappear. thinking
# levels are left unset on purpose — the Vibe package's own known-models table
# decides them per model (and ships with auto_update_cli). When the API is
# unreachable we do NOT fall back to a cache (a stale catalog is worse than a
# short one): warn and register only the active model as-is.
python3 - "${CONFIG_FILE}" "${ACTIVE_MODEL}" "${MODELS_JSON_FILE}" "${SUPERVISOR_TOKEN:-}" <<'PY'
import sys, json, pathlib
config_path, active, models_json_path, ha_token = sys.argv[1:5]
tpl = pathlib.Path("/usr/share/vibe-defaults/config.toml.tpl").read_text()

entries = []  # (alias, api_id)
api_ok = False
p = pathlib.Path(models_json_path)
if p.exists() and p.stat().st_size > 0:
    try:
        data = json.load(open(models_json_path)).get("data", [])
        all_ids = {m["id"] for m in data}
        cards = {}
        for m in data:
            caps = m.get("capabilities") or {}
            if not (caps.get("completion_chat") and caps.get("function_calling")):
                continue
            card = m.get("name") or m["id"]
            mid = m["id"]
            # prefer the canonical id (id == card name) when the API lists it
            if card not in cards or mid == card:
                cards[card] = mid
        # alias = the card name when it is itself a valid id, else the id
        entries = sorted((card if card in all_ids else mid, mid) for card, mid in cards.items())
        api_ok = True
    except Exception:
        api_ok = False

def resolve(alias):
    for a, mid in entries:
        if alias in (a, mid):
            return mid
    matches = sorted(mid for _, mid in entries if mid.startswith(alias))
    return matches[-1] if matches else ""

if api_ok:
    rid = resolve(active)
    if not rid:
        print(f"Model '{active}' not found at api.mistral.ai. Check the current model ids at https://docs.mistral.ai/models and update the 'active_model' option.", file=sys.stderr)
        sys.exit(1)
    if rid != active:
        print(f"Resolved '{active}' to '{rid}'", file=sys.stderr)
    # the active model's alias must exist among the registered entries
    active_alias = next((a for a, mid in entries if mid == rid), rid)
    if not any(mid == rid for _, mid in entries):
        entries.insert(0, (active, rid))
        active_alias = active
else:
    entries = [(active, active)]
    rid = active
    active_alias = active
    print(f"WARNING: Could not reach api.mistral.ai/v1/models - registering only '{active}' as-is (no cached catalog)", file=sys.stderr)

blocks = []
for alias, mid in entries:
    blocks.append(f'[[models]]\nname = "{mid}"\nprovider = "mistral"\nalias = "{alias}"\n')

text = (tpl
        .replace("__ACTIVE_MODEL__", active_alias)
        .replace("__MODELS_BLOCK__", "\n".join(blocks))
        .replace("__HA_URL__", "http://supervisor/core")
        .replace("__HA_TOKEN__", ha_token))
pathlib.Path(config_path).write_text(text)
print(f"Active model: {active_alias} (api id: {rid}); registered {len(entries)} model(s) from {'live API' if api_ok else 'active_model only'}", file=sys.stderr)
PY
chmod 600 "${CONFIG_FILE}"

python3 - "$CONFIG_FILE" "$AUTO_UPDATE_CLI" "$ENABLE_TELEMETRY" <<'PY'
import sys, re, pathlib
path, auto_update, telemetry = sys.argv[1:]
text = pathlib.Path(path).read_text()

def upsert(key, value):
    global text
    pattern = re.compile(rf"^{key}\s*=.*$", re.MULTILINE)
    if pattern.search(text):
        text = pattern.sub(f"{key} = {value}", text)
    else:
        text += f"\n{key} = {value}\n"

# active_model is already rendered from the template (resolved alias) — don't
# overwrite it with the raw option here
upsert("enable_update_checks", "true" if auto_update == "true" else "false")
upsert("enable_telemetry", "true" if telemetry == "true" else "false")
pathlib.Path(path).write_text(text)
PY

cat > "${TRUST_FILE}" <<'EOF'
trusted_folders = [
  "/config",
  "/share",
  "/data/vibe",
]
EOF

echo "${AUTO_APPROVE}" > "${VIBE_HOME}/.auto_approve"
echo "${DEFAULT_AGENT}" > "${VIBE_HOME}/.default_agent"
echo "$(bashio::config 'working_directory')" > "${VIBE_HOME}/.workdir"

bashio::log.info "Mistral Vibe initialised – model: ${ACTIVE_MODEL}, agent: ${DEFAULT_AGENT}"
