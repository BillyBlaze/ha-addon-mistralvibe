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
curl -sf --connect-timeout 5 --max-time 30 \
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

cat > "${ENV_FILE}" <<EOF
MISTRAL_API_KEY=${MISTRAL_API_KEY}
HA_URL=http://supervisor/core
HA_TOKEN=${SUPERVISOR_TOKEN}
EOF
chmod 600 "${ENV_FILE}"

if [ -z "${ACTIVE_MODEL}" ] || [ "${ACTIVE_MODEL}" = "null" ]; then
    bashio::log.fatal "No 'active_model' configured."
    exit 1
fi

bashio::log.info "Resolving model '${ACTIVE_MODEL}' via Mistral API..."
MODEL_CACHE="${VIBE_HOME}/.model_cache"
if [ -s "${MODELS_JSON_FILE}" ]; then
    MODELS_JSON="$(cat "${MODELS_JSON_FILE}")"
else
    MODELS_JSON=""
fi

MODEL_NAME="$(echo "${MODELS_JSON}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
wanted = sys.argv[1]
ids = [m['id'] for m in data.get('data', [])]
if wanted in ids:
    print(wanted)
else:
    matches = sorted(i for i in ids if i.startswith(wanted))
    print(matches[-1] if matches else '')
" "${ACTIVE_MODEL}" 2>/dev/null || true)"

if [ -n "${MODELS_JSON}" ]; then
    if [ -z "${MODEL_NAME}" ]; then
        bashio::log.fatal "Model '${ACTIVE_MODEL}' not found at api.mistral.ai. Check the current model ids at https://docs.mistral.ai/models and update the 'active_model' option."
        exit 1
    fi
    if [ "${MODEL_NAME}" != "${ACTIVE_MODEL}" ]; then
        bashio::log.info "Resolved '${ACTIVE_MODEL}' to '${MODEL_NAME}'"
    fi
    printf '%s %s\n' "${ACTIVE_MODEL}" "${MODEL_NAME}" > "${MODEL_CACHE}"
else
    # API unreachable or timed out: fall back to the last successful
    # resolution so a slow Mistral API never stalls startup. (Guard the
    # pipeline: bashio enables pipefail, and grep exits 2 when the cache
    # file does not exist yet, which would abort the script under set -e.)
    CACHED=""
    if [ -f "${MODEL_CACHE}" ]; then
        CACHED="$(grep -F "${ACTIVE_MODEL} " "${MODEL_CACHE}" | tail -1 | cut -d' ' -f2- || true)"
    fi
    if [ -n "${CACHED}" ]; then
        bashio::log.warning "Could not reach api.mistral.ai/v1/models - using cached resolution '${ACTIVE_MODEL}' -> '${CACHED}'"
        MODEL_NAME="${CACHED}"
    else
        bashio::log.warning "Could not reach api.mistral.ai/v1/models - using '${ACTIVE_MODEL}' as-is"
        MODEL_NAME="${ACTIVE_MODEL}"
    fi
fi

bashio::log.info "Active model: ${ACTIVE_MODEL} (api id: ${MODEL_NAME})"

bashio::log.info "Writing Vibe config to ${CONFIG_FILE}"
sed \
    -e "s|__MODEL_NAME__|${MODEL_NAME}|g" \
    -e "s|__ACTIVE_MODEL__|${ACTIVE_MODEL}|g" \
    -e "s|__HA_URL__|http://supervisor/core|g" \
    -e "s|__HA_TOKEN__|${SUPERVISOR_TOKEN}|g" \
    /usr/share/vibe-defaults/config.toml.tpl > "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"

python3 - "$CONFIG_FILE" "$ACTIVE_MODEL" "$AUTO_UPDATE_CLI" "$ENABLE_TELEMETRY" <<'PY'
import sys, re, pathlib
path, model, auto_update, telemetry = sys.argv[1:]
text = pathlib.Path(path).read_text()

def upsert(key, value):
    global text
    pattern = re.compile(rf"^{key}\s*=.*$", re.MULTILINE)
    if pattern.search(text):
        text = pattern.sub(f"{key} = {value}", text)
    else:
        text += f"\n{key} = {value}\n"

upsert("active_model", f'"{model}"')
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
