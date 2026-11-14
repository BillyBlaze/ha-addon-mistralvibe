# Disclaimer

No warranties whatsoever that the code in this repository is doing anything meaningful, is free of harm or may cause serious damage.
It's your sole responsibility to check the code thoroughly before running/using it.

If it fries your Home Assistant setup, burns your servers, eats your cats or buys bitcoins with all your money - it's your own fault.

You have been warned!

# Mistral Vibe – Home Assistant App

Home Assistant app that runs **Mistral Vibe CLI** (Mistral AI's open-source
agentic coding assistant) directly inside Home Assistant. It is a drop-in
alternative to the [robsonfelix/claudecode](https://github.com/robsonfelix/robsonfelix-hass-addons)
app, with the same browser-based terminal experience and MCP-based access to
the full Home Assistant API – just running on Mistral models instead of
Anthropic's Claude.

## What's inside

| App | Description |
| --- | --- |
| **Mistral Vibe** (`./mistralvibe`) | Browser terminal running Mistral Vibe CLI with full Home Assistant integration via a custom MCP server. |

## History

This repository ([`BillyBlaze/ha-addon-mistralvibe`](https://github.com/BillyBlaze/ha-addon-mistralvibe))
is a clean continuation of the original
[`umrath/mistralvibe-hass-app`](https://github.com/umrath/mistralvibe-hass-app)
project, carried on for a while by the `BillyBlaze/mistralvibe-hass-app` fork.
Both are no longer maintained, so development continues here. All original
history is preserved in git.

## Why Mistral instead of Claude?

The original `claudecode` app is excellent but locks you into Anthropic's
ecosystem. Mistral's open-weight models (Apache 2.0 / modified MIT) are
substantially cheaper per token and can be run locally. This app keeps
the same UX while swapping the engine.

## Installation

In Home Assistant:

1. Go to **Settings → Apps → App Store**.
2. Open the menu (⋮) in the top right and select **Repositories**.
3. Add the URL of this repository.
4. Install the **Mistral Vibe** app, configure your Mistral API key, start it,
   and open the web UI.

## License

This repository is licensed under the Apache License 2.0 – the same license
that Mistral Vibe CLI uses. See `LICENSE` for details.
