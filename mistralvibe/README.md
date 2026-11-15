# Mistral Vibe — Home Assistant App

Run [Mistral Vibe CLI](https://github.com/mistralai/mistral-vibe) (Mistral AI's
open-source agentic coding agent, running on Mistral's current model catalog)
directly inside Home Assistant. Terminal in the sidebar, full HA API access
through [ha-mcp](https://github.com/homeassistant-ai/ha-mcp) (86 tools) — built-in on loopback by default, or your own external ha-mcp server via the `mcp_source` option (see DOCS.md); persistent state under `/data/vibe`.

## Quick start

1. Add this repository's URL (`https://github.com/BillyBlaze/ha-addon-mistralvibe`)
   via **Settings → Apps → Install app → ⋮ → Repositories** (on older HA
   versions: **Settings → Apps → Add-on Store → ⋮ → Repositories**).
2. Find **Mistral Vibe** under your repository in the store and click
   **Install app**, paste a Mistral API key into the **Configuration** tab
   (`mistral_api_key`), start the app.
3. Click **Mistral Vibe** in the HA sidebar — the web terminal opens straight
   into a Vibe session (`auto_launch` defaults to `new`; set it to `off` if you
   prefer a plain shell and type `vibe` yourself). Start asking things like
   *"What automations didn't run last night?"* or *"Add a sunset trigger to
   scene.evening_lights"*.

See [`DOCS.md`](./DOCS.md) for full configuration, architecture and security
details.

## Drop-in alternative to `claudecode`

This app is inspired by
[robsonfelix/claudecode](https://github.com/robsonfelix/robsonfelix-hass-addons),
adapted for Mistral Vibe instead of Claude Code. Same UX, same MCP-based HA
integration, different (open-weight) engine. Both apps can run side-by-side.

## Credits

Originally created by [umrath](https://github.com/umrath) as
[`umrath/mistralvibe-hass-app`](https://github.com/umrath/mistralvibe-hass-app),
which in turn drew from
[robsonfelix/claudecode](https://github.com/robsonfelix/robsonfelix-hass-addons).
This fork continues that work; see the repository README for the full history.

## License

Apache 2.0
