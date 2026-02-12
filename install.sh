#!/bin/bash
# peon-opencode installer
set -euo pipefail

INSTALL_DIR="${PEON_DIR:-$HOME/.opencode/hooks/peon-ping}"
CONFIG_PATH="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi ;;
    *) echo "unknown" ;;
  esac
}
PLATFORM=$(detect_platform)

if [ "$PLATFORM" = "unknown" ]; then
  echo "Error: unsupported platform"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required"
  exit 1
fi

if [ "$PLATFORM" = "linux" ]; then
  if ! command -v ffplay >/dev/null 2>&1 && ! command -v paplay >/dev/null 2>&1 && \
     ! command -v aplay >/dev/null 2>&1 && ! command -v mpg123 >/dev/null 2>&1 && \
     ! command -v ogg123 >/dev/null 2>&1; then
    echo "Warning: no audio player found (ffplay, paplay, aplay, mpg123, ogg123)"
  fi
  if ! command -v notify-send >/dev/null 2>&1; then
    echo "Warning: notify-send not found; desktop notifications disabled"
  fi
fi

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ]; then
  CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  if [ -f "$CANDIDATE/peon-opencode.sh" ]; then
    SCRIPT_DIR="$CANDIDATE"
  fi
fi

if [ -z "$SCRIPT_DIR" ]; then
  echo "Error: installer must be run from a local clone"
  exit 1
fi

UPDATING=false
if [ -f "$INSTALL_DIR/peon-opencode.sh" ]; then
  UPDATING=true
fi

mkdir -p "$INSTALL_DIR"

cp "$SCRIPT_DIR/peon-opencode.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
mkdir -p "$CONFIG_DIR/plugins"
cp "$SCRIPT_DIR/peon-opencode-plugin.js" "$CONFIG_DIR/plugins/peon-opencode.js"

if [ ! -f "$INSTALL_DIR/config.json" ]; then
  cp "$SCRIPT_DIR/config.json" "$INSTALL_DIR/"
fi

mkdir -p "$INSTALL_DIR/packs"
cp -r "$SCRIPT_DIR/packs/"* "$INSTALL_DIR/packs/"

chmod +x "$INSTALL_DIR/peon-opencode.sh"

python3 -c "
import json, os
config_path = os.path.expanduser('$CONFIG_PATH')
hook_cmd = os.path.expanduser('$INSTALL_DIR/peon-opencode.sh')

if os.path.exists(config_path):
    with open(config_path) as f:
        try:
            config = json.load(f)
        except Exception:
            config = {}
else:
    schema_key = '\$schema'
    config = {schema_key: 'https://opencode.ai/config.json'}

experimental = config.setdefault('experimental', {})
hooks = experimental.setdefault('hook', {})
session_completed = hooks.setdefault('session_completed', [])

entry = {'command': [hook_cmd]}
if entry not in session_completed:
    session_completed.append(entry)

hooks['session_completed'] = session_completed
experimental['hook'] = hooks
config['experimental'] = experimental

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print(f'Updated opencode config: {config_path}')
"

if [ "$UPDATING" = false ]; then
  echo '{}' > "$INSTALL_DIR/.state.json"
fi

echo ""
if [ "$UPDATING" = true ]; then
  echo "=== Update complete ==="
else
  echo "=== Installation complete ==="
fi
echo ""
echo "Hook command: $INSTALL_DIR/peon-opencode.sh"
echo "Config file: $CONFIG_PATH"
echo "Plugin: $CONFIG_DIR/plugins/peon-opencode.js"
echo ""
echo "Example event payloads (stdin JSON):"
echo '  {"event":"session_start","cwd":"/path/to/project","session_id":"abc"}'
echo '  {"event":"prompt_submit","cwd":"/path/to/project","session_id":"abc"}'
echo '  {"event":"task_complete","cwd":"/path/to/project","session_id":"abc"}'
echo '  {"event":"permission_request","cwd":"/path/to/project","session_id":"abc"}'
echo ""
echo "Config: $INSTALL_DIR/config.json"
echo "State: $INSTALL_DIR/.state.json"
echo ""
echo "CLI controls:"
echo "  $INSTALL_DIR/peon-opencode.sh --toggle"
echo "  $INSTALL_DIR/peon-opencode.sh --status"
echo ""
echo "Plugin (recommended for opencode TUI):"
echo "  Restart opencode to load $CONFIG_DIR/plugins/peon-opencode.js"
