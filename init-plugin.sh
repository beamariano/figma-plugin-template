#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prompt() {
  local label="$1" default="$2" value
  if [[ -n "$default" ]]; then
    read -rp "$label [$default]: " value
    echo "${value:-$default}"
  else
    read -rp "$label: " value
    echo "$value"
  fi
}

echo "=== Figma Plugin Setup ==="
echo

PLUGIN_NAME=$(prompt "Plugin name" "My Figma Plugin")
PLUGIN_ID=$(prompt "Plugin ID (from Figma → Plugins → Create new plugin)")
AUTHOR=$(prompt "Author")
LICENSE=$(prompt "License" "MIT")
DESCRIPTION=$(prompt "Description" "A Figma plugin")

echo
echo "Editor types (space-separated, options: figma figjam slides buzz)"
read -rp "Editor types [figma]: " EDITORS_RAW
EDITORS_RAW="${EDITORS_RAW:-figma}"

# Build JSON array for editorType
EDITOR_JSON=$(echo "$EDITORS_RAW" | tr ' ' '\n' | grep -v '^$' | \
  awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')

echo
echo "Network access — allowed domains (space-separated, or 'none')"
read -rp "Allowed domains [none]: " DOMAINS_RAW
DOMAINS_RAW="${DOMAINS_RAW:-none}"

DOMAINS_JSON=$(echo "$DOMAINS_RAW" | tr ' ' '\n' | grep -v '^$' | \
  awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}')

# ── package.json ─────────────────────────────────────────────────────────────
PACKAGE_JSON="$SCRIPT_DIR/package.json"

# Use python3 or node to do the JSON surgery cleanly
if command -v python3 &>/dev/null; then
  python3 - "$PACKAGE_JSON" "$PLUGIN_NAME" "$AUTHOR" "$LICENSE" "$DESCRIPTION" <<'PY'
import sys, json
path, name, author, license_, desc = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
data["name"] = name
data["author"] = author
data["license"] = license_
data["description"] = desc
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
elif command -v node &>/dev/null; then
  node -e "
    const fs = require('fs');
    const p = '$PACKAGE_JSON';
    const d = JSON.parse(fs.readFileSync(p,'utf8'));
    d.name = $(printf '%s' "$PLUGIN_NAME" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo "\"$PLUGIN_NAME\"");
    d.author = \"$AUTHOR\";
    d.license = \"$LICENSE\";
    d.description = \"$DESCRIPTION\";
    fs.writeFileSync(p, JSON.stringify(d, null, 2) + '\n');
  "
else
  echo "Warning: neither python3 nor node found; skipping package.json update."
fi

# ── manifest.json ─────────────────────────────────────────────────────────────
MANIFEST_JSON="$SCRIPT_DIR/manifest.json"

if command -v python3 &>/dev/null; then
  python3 - "$MANIFEST_JSON" "$PLUGIN_NAME" "$PLUGIN_ID" "$EDITORS_RAW" "$DOMAINS_RAW" <<'PY'
import sys, json
path, name, pid, editors_raw, domains_raw = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
data["name"] = name
data["id"] = pid
data["editorType"] = [e for e in editors_raw.split() if e]
domains = [d for d in domains_raw.split() if d]
data["networkAccess"] = {"allowedDomains": domains}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
else
  echo "Warning: python3 not found; skipping manifest.json update."
fi

echo
echo "Done! Updated:"
echo "  package.json  — name, author, license, description"
echo "  manifest.json — name, id, editorType, networkAccess"
