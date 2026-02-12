# peon-opencode

Voice line hooks for opencode with Linux, macOS, and WSL support.

This is a refactor of peon-ping to work in a generic hook runner. The hook script reads a JSON event from stdin and plays a matching voice line, sets a terminal title, and optionally sends a desktop notification.

## Install (local clone)

```bash
bash install.sh
```

This copies files into `~/.opencode/hooks/peon-ping` by default and updates `~/.config/opencode/opencode.json` to register the hook. Override with `PEON_DIR` and `OPENCODE_CONFIG` if your setup uses different locations.

To remove:

```bash
bash uninstall.sh
```

## Hook usage

The installer registers a hook under `experimental.hook.session_completed`. If you want to wire it manually, set:

```json
{
  "experimental": {
    "hook": {
      "session_completed": [
        {
          "command": ["~/.opencode/hooks/peon-ping/peon-opencode.sh"]
        }
      ]
    }
  }
}
```

The hook reads a JSON payload from stdin. It accepts either flat fields or opencode-style `payload` events:

```bash
~/.opencode/hooks/peon-ping/peon-opencode.sh
```

Example payloads:

```json
{"event":"session_start","cwd":"/path/to/project","session_id":"abc"}
```

```json
{"event":"task_complete","cwd":"/path/to/project","session_id":"abc"}
```

```json
{"payload":{"type":"session.completed","properties":{"directory":"/path/to/project","sessionID":"abc"}}}
```

Supported event aliases:

- session_start: `SessionStart`, `session_start`, `start`, `session`
- prompt_submit: `UserPromptSubmit`, `prompt_submit`, `prompt`, `user_prompt`
- task_complete: `Stop`, `task_complete`, `task_done`, `complete`, `finished`, `session.completed`
- permission_request: `PermissionRequest`, `permission_request`, `permission`, `needs_permission`
- notification: `Notification`, `notification` (use `notification_type` for `permission_prompt`, `idle_prompt`, `resource_limit`)
- error: `error`, `failure`, `tool_error`, `posttoolusefailure`, `task_error`

## CLI controls

```bash
peon-opencode.sh --pause
peon-opencode.sh --resume
peon-opencode.sh --toggle
peon-opencode.sh --status
peon-opencode.sh --packs
peon-opencode.sh --pack <name>
peon-opencode.sh --pack
```

## Configuration

Edit `~/.opencode/hooks/peon-ping/config.json`:

```json
{
  "enabled": true,
  "volume": 0.5,
  "active_pack": "peon",
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

## Environment overrides

- `PEON_DIR`: base install directory (default `~/.opencode/hooks/peon-ping`)
- `PEON_CONFIG`: config path override
- `PEON_STATE`: state path override
- `PEON_PACKS_DIR`: packs directory override

## Linux requirements

- `python3`
- Audio playback: one of `ffplay`, `paplay`, `aplay`, `mpg123`, `ogg123`
- Notifications: `notify-send` (optional)
- Focus detection: `xdotool` (optional)

## License

MIT. Sound files are property of their respective publishers.
