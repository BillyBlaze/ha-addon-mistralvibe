#!/usr/bin/env bash
# Smoke checks for the mistralvibe add-on. Run from the repo root:
#   bash .github/scripts/smoke.sh
# Exits non-zero on the first failing group; prints one OK line per group.
set -euo pipefail

ADDON="mistralvibe"
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Shell syntax: every shell script in the image
mapfile -t SH_SCRIPTS < <(find "${ADDON}/rootfs" -type f \( -name "*.sh" -o -path "*cont-init.d*" -o -path "*services.d*" \) -print)
[ "${#SH_SCRIPTS[@]}" -gt 0 ] || fail "no shell scripts found"
for f in "${SH_SCRIPTS[@]}"; do
    bash -n "$f" || fail "bash -n: $f"
done
echo "OK: shell syntax (${#SH_SCRIPTS[@]} scripts)"

# 2. Python syntax: ingress proxy
for f in "${ADDON}/rootfs/usr/share/vibe-proxy/proxy.py"; do
    python3 -m py_compile "$f" || fail "py_compile: $f"
done
echo "OK: python syntax"

# 3. YAML validity + options/schema/translation key coverage
python3 - "$ADDON" <<'PY'
import sys, pathlib, yaml

addon = pathlib.Path(sys.argv[1])
cfg = yaml.safe_load((addon / "config.yaml").read_text())
en = yaml.safe_load((addon / "translations/en.yaml").read_text())

options = set(cfg.get("options", {}))
schema = set(cfg.get("schema", {}))
translated = set(en.get("configuration", {}))

missing_schema = options - schema
missing_translation = options - translated
assert not missing_schema, f"options without schema entry: {sorted(missing_schema)}"
assert not missing_translation, f"options without en.yaml translation: {sorted(missing_translation)}"
print(f"OK: yaml valid, {len(options)} options all have schema + en translation")
PY

# 4. config.toml template renders to valid TOML with placeholders substituted
python3 - "$ADDON" <<'PY'
import sys, pathlib, tomllib

tpl = pathlib.Path(sys.argv[1]) / "rootfs/usr/share/vibe-defaults/config.toml.tpl"
text = tpl.read_text()
for ph in ("__ACTIVE_MODEL__", "__MCP_URL__"):
    assert ph in text, f"placeholder {ph} missing from template"
    text = text.replace(ph, "x" if ph == "__ACTIVE_MODEL__" else "http://127.0.0.1:9584/mcp")
# the init script substitutes __MODELS_BLOCK__ with real [[models]] tables
assert "__MODELS_BLOCK__" in text, "placeholder __MODELS_BLOCK__ missing from template"
text = text.replace("__MODELS_BLOCK__", '[[models]]\nname = "x"\nprovider = "x"\nalias = "x"')
# __MCP_AUTH_BLOCK__ is either empty or a [mcp_servers.auth] static block —
# both must render to valid TOML
assert "__MCP_AUTH_BLOCK__" in text, "placeholder __MCP_AUTH_BLOCK__ missing from template"
auth_block = ('[mcp_servers.auth]\ntype = "static"\napi_key_env = "EXTERNAL_MCP_TOKEN"\n'
              'api_key_header = "Authorization"\napi_key_format = "Bearer {token}"')
for auth in ("", auth_block):
    cfg = tomllib.loads(text.replace("__MCP_AUTH_BLOCK__", auth))
    assert cfg["models"][0]["alias"] == "x" == cfg["active_model"]
    assert cfg["mcp_servers"][0]["url"] == "http://127.0.0.1:9584/mcp"
# no credential placeholders may remain — tokens go to .env / service env only
for stale in ("__HA_URL__", "__HA_TOKEN__", "HA_TOKEN", "HOMEASSISTANT_TOKEN", "EXTERNAL_MCP_TOKEN = "):
    assert stale not in text, f"stale credential placeholder {stale} in template"
print("OK: config.toml template renders to valid TOML (with and without auth block)")
PY

echo "ALL SMOKE CHECKS PASSED"
