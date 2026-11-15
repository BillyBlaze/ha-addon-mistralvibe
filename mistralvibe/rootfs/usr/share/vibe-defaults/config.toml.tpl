active_model = "__ACTIVE_MODEL__"
vim_keybindings = false
auto_compact_threshold = 100000
include_project_context = true
enable_update_checks = true
enable_telemetry = false
api_timeout = 720.0
disable_welcome_banner_animation = true
system_prompt_id = "ha"

[project_context]
default_commit_count = 5

[session_logging]
save_dir = "/data/vibe/logs/session"
enabled = true

[tools]
enabled_tools = []
disabled_tools = []

[[providers]]
name = "mistral"
api_base = "https://api.mistral.ai/v1"
api_key_env_var = "MISTRAL_API_KEY"
backend = "mistral"

__MODELS_BLOCK__

# The MCP server is chosen at startup from the mcp_source option:
#   builtin  -> local ha-mcp-web on 127.0.0.1:9584 (loopback only; gets the
#               Supervisor token via its own env, no credential in this file)
#   external -> the URL from external_mcp_url (e.g. the HA-MCP HACS integration)
[[mcp_servers]]
name = "hass"
transport = "streamable-http"
url = "__MCP_URL__"
__MCP_AUTH_BLOCK__
