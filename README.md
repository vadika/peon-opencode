# peon-opencode

Voice lines for OpenCode sessions on Linux, macOS, and WSL.

This project installs a hook script and plugin that react to OpenCode events, play matching sounds, update terminal title, and optionally send desktop notifications.

Inspired by https://peon-ping.vercel.app/.

## Install

### One-liner (curl | bash)

```bash
curl -fsSL https://raw.githubusercontent.com/vadika/peon-opencode/master/install.sh | bash
```

Optional installer overrides:

- `PEON_REPO` (default: `vadika/peon-opencode`)
- `PEON_REF` (default: `master`)
- `PEON_ARCHIVE_URL` (advanced override for the source tarball URL)

Example (install from a different branch):

```bash
curl -fsSL https://raw.githubusercontent.com/vadika/peon-opencode/master/install.sh | PEON_REF=feature/my-branch bash
```

### Local clone

```bash
bash install.sh
```

By default this installs to:

- hook dir: `~/.opencode/hooks/peon-ping`
- OpenCode config: `~/.config/opencode/opencode.json`
- plugin file: `~/.config/opencode/plugins/peon-opencode.js`

## Uninstall

From a local clone:

```bash
bash uninstall.sh
```

Or one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/vadika/peon-opencode/master/uninstall.sh | bash
```

## How it works

- `peon-opencode-plugin.js` listens to OpenCode events and forwards payloads to the hook.
- `peon-opencode.sh` handles platform-specific playback/notifications and CLI controls.
- `peon-opencode-core.py` handles event parsing, pack selection, and state updates.

The installer also registers `experimental.hook.session_completed` in OpenCode config for compatibility, but plugin mode is the recommended path for current OpenCode TUI usage.

## OpenCode events mapped

Plugin emits or forwards these events:

- `session.created`
- `session.completed`
- `session.idle`
- `session.error` (mapped to hook `error`)
- `permission.asked` (mapped to hook `permission_request`)
- `tool.execute.after` failures (mapped to hook `tool_error`)

Hook also accepts direct JSON events on stdin, including payload-style input.

Example:

```json
{"payload":{"type":"session.completed","properties":{"directory":"/path/to/project","sessionID":"abc"}}}
```

## CLI controls

```bash
~/.opencode/hooks/peon-ping/peon-opencode.sh --pause
~/.opencode/hooks/peon-ping/peon-opencode.sh --resume
~/.opencode/hooks/peon-ping/peon-opencode.sh --toggle
~/.opencode/hooks/peon-ping/peon-opencode.sh --status
~/.opencode/hooks/peon-ping/peon-opencode.sh --packs
~/.opencode/hooks/peon-ping/peon-opencode.sh --pack <name>
~/.opencode/hooks/peon-ping/peon-opencode.sh --pack
```

## Configuration

Edit `~/.opencode/hooks/peon-ping/config.json`:

```json
{
  "enabled": true,
  "volume": 0.5,
  "active_pack": "peon",
  "audio_player": "paplay",
  "pack_rotation": [],
  "annoyed_threshold": 3,
  "annoyed_window_seconds": 10,
  "categories": {
    "greeting": true,
    "acknowledge": true,
    "complete": true,
    "error": true,
    "permission": true,
    "resource_limit": true,
    "annoyed": true
  }
}
```

## Environment variables

Runtime:

- `PEON_DIR`: base directory (default `~/.opencode/hooks/peon-ping`)
- `PEON_CONFIG`: config path override
- `PEON_STATE`: state file path override
- `PEON_PACKS_DIR`: packs directory override
- `PEON_CORE_PY`: override path to `peon-opencode-core.py`
- `PEON_AUDIO_PLAYER`: force Linux backend (`paplay`, `ffplay`, `aplay`, `mpg123`, `ogg123`)
- `PEON_DEBUG=1`: enable debug logging
- `PEON_DEBUG_LOG`: debug log path

Installer/uninstaller:

- `PEON_DIR`
- `OPENCODE_CONFIG`
- `OPENCODE_CONFIG_DIR`

Plugin:

- `PEON_HOOK_CMD`: override hook command path
- `PEON_DEBUG=1`
- `PEON_DEBUG_LOG`

## Requirements

- `python3`
- Linux audio: one of `ffplay`, `paplay`, `aplay`, `mpg123`, `ogg123`
- Linux notifications: `notify-send` (optional)
- Linux focus detection: `xdotool` (optional, X11)

## License

MIT. Sound files are property of their respective publishers.
