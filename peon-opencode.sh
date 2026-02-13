#!/bin/bash
# peon-opencode: voice line hooks for opencode
set -uo pipefail

# --- Platform detection ---
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

PEON_DIR="${PEON_DIR:-$HOME/.opencode/hooks/peon-ping}"
CONFIG="${PEON_CONFIG:-$PEON_DIR/config.json}"
STATE="${PEON_STATE:-$PEON_DIR/.state.json}"
PACKS_DIR="${PEON_PACKS_DIR:-$PEON_DIR/packs}"
DEBUG_LOG="${PEON_DEBUG_LOG:-/tmp/peon-opencode-hook.log}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_PY="${PEON_CORE_PY:-$PEON_DIR/peon-opencode-core.py}"
if [ ! -f "$CORE_PY" ] && [ -f "$SCRIPT_DIR/peon-opencode-core.py" ]; then
  CORE_PY="$SCRIPT_DIR/peon-opencode-core.py"
fi
if [ ! -f "$CORE_PY" ]; then
  echo "peon-opencode: missing core helper at $CORE_PY" >&2
  exit 1
fi

debug() {
  if [ "${PEON_DEBUG:-0}" = "1" ]; then
    printf '[%s] %s\n' "$(date -Is)" "$1" >> "$DEBUG_LOG"
  fi
}

# --- Platform-aware audio playback ---
play_sound() {
  local file="$1" vol="$2"
  case "$PLATFORM" in
    mac)
      debug "play_sound mac: $file"
      nohup afplay -v "$vol" "$file" >/dev/null 2>&1 &
      ;;
    wsl)
      debug "play_sound wsl: $file"
      local wpath
      wpath=$(wslpath -w "$file")
      wpath="${wpath//\\//}"
      powershell.exe -NoProfile -NonInteractive -Command "
        Add-Type -AssemblyName PresentationCore
        \$p = New-Object System.Windows.Media.MediaPlayer
        \$p.Open([Uri]::new('file:///$wpath'))
        \$p.Volume = $vol
        Start-Sleep -Milliseconds 200
        \$p.Play()
        Start-Sleep -Seconds 3
        \$p.Close()
      " &>/dev/null &
      ;;
    linux)
      local backend="${PEON_AUDIO_PLAYER:-${AUDIO_PLAYER:-}}"
      if [ -n "$backend" ]; then
        case "$backend" in
          paplay)
            if command -v paplay >/dev/null 2>&1; then
              debug "play_sound linux: paplay $file"
              nohup paplay "$file" >/dev/null 2>&1 &
              return
            fi
            ;;
          ffplay)
            if command -v ffplay >/dev/null 2>&1; then
              debug "play_sound linux: ffplay $file"
              local vol_pct
              vol_pct=$(python3 -c "import sys; v=float('$vol'); v=max(0.0,min(1.0,v)); print(int(v*100))")
              nohup ffplay -nodisp -autoexit -loglevel error -volume "$vol_pct" "$file" >/dev/null 2>&1 &
              return
            fi
            ;;
          aplay)
            if command -v aplay >/dev/null 2>&1; then
              debug "play_sound linux: aplay $file"
              nohup aplay "$file" >/dev/null 2>&1 &
              return
            fi
            ;;
          mpg123)
            if command -v mpg123 >/dev/null 2>&1; then
              debug "play_sound linux: mpg123 $file"
              nohup mpg123 -q "$file" >/dev/null 2>&1 &
              return
            fi
            ;;
          ogg123)
            if command -v ogg123 >/dev/null 2>&1; then
              debug "play_sound linux: ogg123 $file"
              nohup ogg123 -q "$file" >/dev/null 2>&1 &
              return
            fi
            ;;
        esac
      fi

      if command -v paplay >/dev/null 2>&1; then
        debug "play_sound linux: paplay $file"
        nohup paplay "$file" >/dev/null 2>&1 &
      elif command -v ffplay >/dev/null 2>&1; then
        debug "play_sound linux: ffplay $file"
        local vol_pct
        vol_pct=$(python3 -c "import sys; v=float('$vol'); v=max(0.0,min(1.0,v)); print(int(v*100))")
        nohup ffplay -nodisp -autoexit -loglevel error -volume "$vol_pct" "$file" >/dev/null 2>&1 &
      elif command -v aplay >/dev/null 2>&1; then
        debug "play_sound linux: aplay $file"
        nohup aplay "$file" >/dev/null 2>&1 &
      elif command -v mpg123 >/dev/null 2>&1; then
        debug "play_sound linux: mpg123 $file"
        nohup mpg123 -q "$file" >/dev/null 2>&1 &
      elif command -v ogg123 >/dev/null 2>&1; then
        debug "play_sound linux: ogg123 $file"
        nohup ogg123 -q "$file" >/dev/null 2>&1 &
      fi
      ;;
  esac
}

# --- Platform-aware notification ---
# Args: msg, title, color (red/blue/yellow)
send_notification() {
  local msg="$1" title="$2" color="${3:-red}"
  case "$PLATFORM" in
    mac)
      nohup osascript - "$msg" "$title" >/dev/null 2>&1 <<'APPLESCRIPT' &
on run argv
  display notification (item 1 of argv) with title (item 2 of argv)
end run
APPLESCRIPT
      ;;
    wsl)
      local rgb_r=180 rgb_g=0 rgb_b=0
      case "$color" in
        blue)   rgb_r=30  rgb_g=80  rgb_b=180 ;;
        yellow) rgb_r=200 rgb_g=160 rgb_b=0   ;;
        red)    rgb_r=180 rgb_g=0   rgb_b=0   ;;
      esac
      (
        slot_dir="/tmp/peon-ping-popups"
        mkdir -p "$slot_dir"
        slot=0
        while ! mkdir "$slot_dir/slot-$slot" 2>/dev/null; do
          slot=$((slot + 1))
        done
        y_offset=$((40 + slot * 90))
        powershell.exe -NoProfile -NonInteractive -Command "
          Add-Type -AssemblyName System.Windows.Forms
          Add-Type -AssemblyName System.Drawing
          foreach (\$screen in [System.Windows.Forms.Screen]::AllScreens) {
            \$form = New-Object System.Windows.Forms.Form
            \$form.FormBorderStyle = 'None'
            \$form.BackColor = [System.Drawing.Color]::FromArgb($rgb_r, $rgb_g, $rgb_b)
            \$form.Size = New-Object System.Drawing.Size(500, 80)
            \$form.TopMost = \$true
            \$form.ShowInTaskbar = \$false
            \$form.StartPosition = 'Manual'
            \$form.Location = New-Object System.Drawing.Point(
              (\$screen.WorkingArea.X + (\$screen.WorkingArea.Width - 500) / 2),
              (\$screen.WorkingArea.Y + $y_offset)
            )
            \$label = New-Object System.Windows.Forms.Label
            \$label.Text = '$msg'
            \$label.ForeColor = [System.Drawing.Color]::White
            \$label.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
            \$label.TextAlign = 'MiddleCenter'
            \$label.Dock = 'Fill'
            \$form.Controls.Add(\$label)
            \$form.Show()
          }
          Start-Sleep -Seconds 4
          [System.Windows.Forms.Application]::Exit()
        " &>/dev/null
        rm -rf "$slot_dir/slot-$slot"
      ) &
      ;;
    linux)
      if command -v notify-send >/dev/null 2>&1; then
        local urgency="normal"
        case "$color" in
          red) urgency="critical" ;;
          yellow) urgency="normal" ;;
          blue) urgency="low" ;;
        esac
        nohup notify-send -u "$urgency" "$title" "$msg" >/dev/null 2>&1 &
      fi
      ;;
  esac
}

# --- Platform-aware terminal focus check ---
terminal_is_focused() {
  case "$PLATFORM" in
    mac)
      local frontmost
      frontmost=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
      case "$frontmost" in
        Terminal|iTerm2|Warp|Alacritty|kitty|WezTerm|Ghostty) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    wsl)
      return 1
      ;;
    linux)
      if [ -n "${DISPLAY:-}" ] && command -v xdotool >/dev/null 2>&1; then
        local wname
        wname=$(xdotool getwindowfocus getwindowname 2>/dev/null || true)
        case "$wname" in
          *Terminal*|*Konsole*|*Alacritty*|*kitty*|*WezTerm*|*GNOME*Terminal*|*XTerm*) return 0 ;;
          *) return 1 ;;
        esac
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# --- CLI subcommands ---
PAUSED_FILE="$PEON_DIR/.paused"
case "${1:-}" in
  --pause)   touch "$PAUSED_FILE"; echo "peon-opencode: sounds paused"; exit 0 ;;
  --resume)  rm -f "$PAUSED_FILE"; echo "peon-opencode: sounds resumed"; exit 0 ;;
  --toggle)
    if [ -f "$PAUSED_FILE" ]; then rm -f "$PAUSED_FILE"; echo "peon-opencode: sounds resumed"
    else touch "$PAUSED_FILE"; echo "peon-opencode: sounds paused"; fi
    exit 0 ;;
  --status)
    [ -f "$PAUSED_FILE" ] && echo "peon-opencode: paused" || echo "peon-opencode: active"
    exit 0 ;;
  --packs)
    python3 "$CORE_PY" list-packs --config "$CONFIG" --packs-dir "$PACKS_DIR"
    exit 0 ;;
  --pack)
    PACK_ARG="${2:-}"
    python3 "$CORE_PY" set-pack --config "$CONFIG" --packs-dir "$PACKS_DIR" --pack "$PACK_ARG" || exit 1
    exit 0 ;;
  --help|-h)
    cat <<'HELPEOF'
Usage: peon-opencode <command>

Commands:
  --pause        Mute sounds
  --resume       Unmute sounds
  --toggle       Toggle mute on/off
  --status       Check if paused or active
  --packs        List available sound packs
  --pack <name>  Switch to a specific pack
  --pack         Cycle to the next pack
  --help         Show this help
HELPEOF
    exit 0 ;;
  --*)
    echo "Unknown option: $1" >&2
    echo "Run 'peon-opencode --help' for usage." >&2; exit 1 ;;
esac

INPUT=$(cat)

PAUSED=false
[ -f "$PEON_DIR/.paused" ] && PAUSED=true

PAUSED_FLAG=""
[ "$PAUSED" = "true" ] && PAUSED_FLAG="--paused"
eval "$(python3 "$CORE_PY" process-event --config "$CONFIG" --state "$STATE" --packs-dir "$PACKS_DIR" $PAUSED_FLAG <<< "$INPUT")"

if [ -n "${PEON_ERROR:-}" ]; then
  debug "core error: $PEON_ERROR"
fi

[ "${PEON_EXIT:-true}" = "true" ] && exit 0

if [ "$EVENT" = "SessionStart" ] || [ "${EVENT,,}" = "session_start" ]; then
  if [ "$PAUSED" = "true" ]; then
    echo "peon-opencode: sounds paused - run 'peon-opencode --resume' to unpause" >&2
  fi
fi

debug "event=$EVENT category=$CATEGORY paused=$PAUSED sound=$SOUND_FILE notify=$NOTIFY"

TITLE="${MARKER}${PROJECT}: ${STATUS}"
if [ -n "$TITLE" ]; then
  printf '\033]0;%s\007' "$TITLE"
fi

if [ -n "$SOUND_FILE" ] && [ -f "$SOUND_FILE" ]; then
  play_sound "$SOUND_FILE" "$VOLUME"
elif [ -n "$SOUND_FILE" ]; then
  debug "sound missing: $SOUND_FILE"
fi

if [ -n "$NOTIFY" ] && [ "$PAUSED" != "true" ]; then
  if ! terminal_is_focused; then
    send_notification "$MSG" "$TITLE" "${NOTIFY_COLOR:-red}"
  fi
fi

exit 0
