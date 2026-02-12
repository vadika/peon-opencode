#!/bin/bash
# peon-opencode uninstaller
set -euo pipefail

INSTALL_DIR="${PEON_DIR:-$HOME/.opencode/hooks/peon-ping}"
CONFIG_PATH="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

if [ -f "$CONFIG_PATH" ]; then
  python3 -c "
import json, os
config_path = os.path.expanduser('$CONFIG_PATH')
hook_cmd = os.path.expanduser('$INSTALL_DIR/peon-opencode.sh')

with open(config_path) as f:
    config = json.load(f)

experimental = config.get('experimental', {})
hooks = experimental.get('hook', {})
session_completed = hooks.get('session_completed', [])

filtered = [e for e in session_completed if e.get('command') != [hook_cmd]]
if filtered != session_completed:
    if filtered:
        hooks['session_completed'] = filtered
    else:
        hooks.pop('session_completed', None)
    if not hooks:
        experimental.pop('hook', None)
    if not experimental:
        config.pop('experimental', None)
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
        f.write('\n')
    print(f'Removed hook from: {config_path}')
else:
    print('No matching hook found in config')
  "
fi

if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  echo "Removed $INSTALL_DIR"
fi

if [ -f "$CONFIG_DIR/plugins/peon-opencode.js" ]; then
  rm -f "$CONFIG_DIR/plugins/peon-opencode.js"
  echo "Removed $CONFIG_DIR/plugins/peon-opencode.js"
fi

echo "Uninstall complete"
