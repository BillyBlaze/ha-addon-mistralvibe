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

# ha-mcp (homeassistant-ai/ha-mcp) runs as a local loopback-only service in
# this container (services.d/ha-mcp, 127.0.0.1:9584) and gets the Supervisor
# token via its own env — no credential is stored in this file.
[[mcp_servers]]
name = "hass"
transport = "streamable-http"
url = "http://127.0.0.1:9584/mcp"
