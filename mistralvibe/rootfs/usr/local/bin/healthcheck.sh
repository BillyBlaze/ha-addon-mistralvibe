#!/usr/bin/env bash
# Probe the proxy, both ttyd backends, and — only in builtin MCP mode — the
# local ha-mcp server. A dead component behind a healthy proxy must fail.
set -u
curl -sf -A vibe-healthcheck http://localhost:7681/ || exit 1
curl -sf -A vibe-healthcheck http://localhost:7682/ || exit 1
curl -sf -A vibe-healthcheck http://localhost:7683/ || exit 1
MCP_SOURCE="$(jq -r '.mcp_source // "builtin"' /data/options.json 2>/dev/null || echo builtin)"
if [ "${MCP_SOURCE}" = "builtin" ]; then
    curl -sf -A vibe-healthcheck http://localhost:9584/healthz || exit 1
fi
exit 0
