import os
import json
import httpx
from typing import Optional
from fastmcp import FastMCP

HA_URL = os.environ.get("HA_URL", "http://supervisor/core")
HA_TOKEN = os.environ.get("HA_TOKEN", "")

mcp = FastMCP("home-assistant")

def _headers() -> dict:
    return {
        "Authorization": f"Bearer {HA_TOKEN}",
        "Content-Type": "application/json",
    }

def _get(path: str) -> dict | list:
    with httpx.Client(timeout=10) as client:
        r = client.get(f"{HA_URL}/api{path}", headers=_headers())
        r.raise_for_status()
        return r.json()

def _post(path: str, data: dict) -> dict:
    with httpx.Client(timeout=10) as client:
        r = client.post(f"{HA_URL}/api{path}", headers=_headers(), json=data)
        r.raise_for_status()
        return r.json()

@mcp.tool
def ha_get_config() -> dict:
    """Get Home Assistant core configuration (version, location, units)."""
    return _get("/config")

@mcp.tool
def ha_list_entities(domain: Optional[str] = None, search: Optional[str] = None, limit: int = 50) -> list:
    """List entities, optionally filtered by domain (light, switch, sensor, etc.) or search term. Max 50 by default."""
    states = _get("/states")
    if domain:
        states = [s for s in states if s["entity_id"].startswith(f"{domain}.")]
    if search:
        search_lower = search.lower()
        states = [s for s in states if search_lower in s["entity_id"].lower()
                  or search_lower in str(s.get("attributes", {}).get("friendly_name", "")).lower()]
    states = states[:limit]
    return [{"entity_id": s["entity_id"],
             "state": s["state"],
             "friendly_name": s.get("attributes", {}).get("friendly_name", "")}
            for s in states]

@mcp.tool
def ha_get_entity(entity_id: str) -> dict:
    """Get the full state and attributes of a specific entity."""
    return _get(f"/states/{entity_id}")

@mcp.tool
def ha_call_service(domain: str, service: str, data: Optional[dict] = None) -> str:
    """Call a Home Assistant service. Examples: domain='light', service='turn_on', data={'entity_id': 'light.kitchen'}"""
    if not domain or not service:
        return "Error: 'domain' and 'service' are required, e.g. domain='light', service='turn_on'."
    try:
        _post(f"/services/{domain}/{service}", data or {})
    except httpx.HTTPStatusError as e:
        detail = e.response.text
        try:
            detail = e.response.json().get("message", detail)
        except Exception:
            pass
        return f"Error calling {domain}.{service}: HTTP {e.response.status_code} - {detail}"
    except httpx.HTTPError as e:
        return f"Error calling {domain}.{service}: {e}"
    return f"Service {domain}.{service} called successfully."

@mcp.tool
def ha_list_automations(search: Optional[str] = None, limit: int = 50) -> list:
    """List automations, optionally filtered by name. Max 50 by default."""
    states = _get("/states")
    automations = [s for s in states if s["entity_id"].startswith("automation.")]
    if search:
        search_lower = search.lower()
        automations = [a for a in automations
                       if search_lower in a["entity_id"].lower()
                       or search_lower in str(a.get("attributes", {}).get("friendly_name", "")).lower()]
    automations = automations[:limit]
    return [{"entity_id": a["entity_id"],
             "state": a["state"],
             "friendly_name": a.get("attributes", {}).get("friendly_name", "")}
            for a in automations]

@mcp.tool
def ha_list_areas() -> list:
    """List all areas defined in Home Assistant."""
    try:
        result = _post("/template", {"template": "{{ areas() | tojson }}"})
        if isinstance(result, str):
            return json.loads(result)
        return result
    except Exception:
        return []

@mcp.tool
def ha_get_error_log(lines: int = 50) -> str:
    """Get the last N lines of the Home Assistant log. Default 50, maximum 200 lines.

    On HA 2025.11+ the /api/error_log endpoint is gone and home-assistant.log is no
    longer written by default. The log file is read from /config when present (enable
    it with: ha core options --duplicate-log-file=true, then restart core).
    """
    lines = min(lines, 200)
    log_file = "/config/home-assistant.log"
    if os.path.exists(log_file):
        with open(log_file, "r", errors="replace") as f:
            return "\n".join(f.read().splitlines()[-lines:])
    try:
        with httpx.Client(timeout=15) as client:
            r = client.get(f"{HA_URL}/api/error_log", headers=_headers())
            r.raise_for_status()
            return "\n".join(r.text.splitlines()[-lines:])
    except httpx.HTTPError:
        return ("Could not retrieve the HA log: /api/error_log no longer exists on HA "
                "2025.11+ and /config/home-assistant.log is not present. Enable the log file "
                "with 'ha core options --duplicate-log-file=true' (then restart core), or use "
                "'ha core logs' in the terminal.")

@mcp.tool
def ha_get_history(entity_id: str, hours: int = 2) -> list:
    """Get state history for an entity for the last N hours. Default 2 hours, maximum 24."""
    hours = min(hours, 24)
    from datetime import datetime, timedelta, timezone
    start = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
    result = _get(f"/history/period/{start}?filter_entity_id={entity_id}&minimal_response=true")
    if result and isinstance(result, list) and result[0]:
        return result[0][-50:]
    return []

@mcp.tool
def ha_restart() -> str:
    """Restart Home Assistant. Use only when necessary."""
    with httpx.Client(timeout=10) as client:
        r = client.post(f"{HA_URL}/api/services/homeassistant/restart", headers=_headers(), json={})
        r.raise_for_status()
    return "Home Assistant restart initiated."


if __name__ == "__main__":
    mcp.run()
