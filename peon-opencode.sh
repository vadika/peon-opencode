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
    python3 -c "
import json, os, glob
config_path = '$CONFIG'
try:
    active = json.load(open(config_path)).get('active_pack', 'peon')
except:
    active = 'peon'
packs_dir = '$PACKS_DIR'
for m in sorted(glob.glob(os.path.join(packs_dir, '*/manifest.json'))):
    info = json.load(open(m))
    name = info.get('name', os.path.basename(os.path.dirname(m)))
    display = info.get('display_name', name)
    marker = ' *' if name == active else ''
    print(f'  {name:24s} {display}{marker}')
"
    exit 0 ;;
  --pack)
    PACK_ARG="${2:-}"
    if [ -z "$PACK_ARG" ]; then
      python3 -c "
import json, os, glob
config_path = '$CONFIG'
try:
    cfg = json.load(open(config_path))
except:
    cfg = {}
active = cfg.get('active_pack', 'peon')
packs_dir = '$PACKS_DIR'
names = sorted([
    os.path.basename(os.path.dirname(m))
    for m in glob.glob(os.path.join(packs_dir, '*/manifest.json'))
])
if not names:
    print('Error: no packs found', flush=True)
    raise SystemExit(1)
try:
    idx = names.index(active)
    next_pack = names[(idx + 1) % len(names)]
except ValueError:
    next_pack = names[0]
cfg['active_pack'] = next_pack
json.dump(cfg, open(config_path, 'w'), indent=2)
mpath = os.path.join(packs_dir, next_pack, 'manifest.json')
display = json.load(open(mpath)).get('display_name', next_pack)
print(f'peon-opencode: switched to {next_pack} ({display})')
"
    else
      python3 -c "
import json, os, glob, sys
config_path = '$CONFIG'
pack_arg = '$PACK_ARG'
packs_dir = '$PACKS_DIR'
names = sorted([
    os.path.basename(os.path.dirname(m))
    for m in glob.glob(os.path.join(packs_dir, '*/manifest.json'))
])
if pack_arg not in names:
    print(f'Error: pack \"{pack_arg}\" not found.', file=sys.stderr)
    print(f'Available packs: {", ".join(names)}', file=sys.stderr)
    sys.exit(1)
try:
    cfg = json.load(open(config_path))
except:
    cfg = {}
cfg['active_pack'] = pack_arg
json.dump(cfg, open(config_path, 'w'), indent=2)
mpath = os.path.join(packs_dir, pack_arg, 'manifest.json')
display = json.load(open(mpath)).get('display_name', pack_arg)
print(f'peon-opencode: switched to {pack_arg} ({display})')
" || exit 1
    fi
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

eval "$(python3 -c "
import sys, json, os, re, random, time, shlex
q = shlex.quote

config_path = '$CONFIG'
state_file = '$STATE'
packs_dir = '$PACKS_DIR'
paused = '$PAUSED' == 'true'
state_dirty = False

try:
    cfg = json.load(open(config_path))
except:
    cfg = {}

if str(cfg.get('enabled', True)).lower() == 'false':
    print('PEON_EXIT=true')
    sys.exit(0)

volume = cfg.get('volume', 0.5)
audio_player = cfg.get('audio_player', '')
active_pack = cfg.get('active_pack', 'peon')
pack_rotation = cfg.get('pack_rotation', [])
annoyed_threshold = int(cfg.get('annoyed_threshold', 3))
annoyed_window = float(cfg.get('annoyed_window_seconds', 10))
cats = cfg.get('categories', {})
cat_enabled = {}
for c in ['greeting','acknowledge','complete','error','permission','resource_limit','annoyed']:
    cat_enabled[c] = str(cats.get(c, True)).lower() == 'true'

event_data = json.load(sys.stdin)
payload = event_data.get('payload', {}) if isinstance(event_data, dict) else {}
properties = payload.get('properties', {}) if isinstance(payload, dict) else {}
event = event_data.get('event') or event_data.get('hook_event_name') or event_data.get('type') or payload.get('type') or ''
ntype = event_data.get('notification_type') or event_data.get('notification') or properties.get('notification_type') or ''
cwd = event_data.get('cwd') or event_data.get('workdir') or event_data.get('project_dir') or properties.get('directory') or event_data.get('directory') or ''
session_id = event_data.get('session_id') or event_data.get('session') or event_data.get('run_id') or properties.get('sessionID') or properties.get('session_id') or ''
project = event_data.get('project') or properties.get('project') or ''

try:
    state = json.load(open(state_file))
except:
    state = {}

if not project:
    project = cwd.rsplit('/', 1)[-1] if cwd else 'opencode'
if not project:
    project = 'opencode'
project = re.sub(r'[^a-zA-Z0-9 ._-]', '', project)

event_lower = str(event).lower()
category = ''
status = ''
marker = ''
notify = ''
notify_color = ''
msg = ''

if event_lower in ['sessionstart','session_start','start','session']:
    category = 'greeting'
    status = 'ready'
elif event_lower in ['userpromptsubmit','prompt_submit','prompt','user_prompt','prompted']:
    status = 'working'
    if cat_enabled.get('annoyed', True):
        all_ts = state.get('prompt_timestamps', {})
        if isinstance(all_ts, list):
            all_ts = {}
        now = time.time()
        ts = [t for t in all_ts.get(session_id, []) if now - t < annoyed_window]
        ts.append(now)
        all_ts[session_id] = ts
        state['prompt_timestamps'] = all_ts
        state_dirty = True
        if len(ts) >= annoyed_threshold:
            category = 'annoyed'
elif event_lower in ['stop','task_complete','task_done','complete','finished','session.completed','session_completed']:
    category = 'complete'
    status = 'done'
    marker = '* '
    notify = '1'
    notify_color = 'blue'
    msg = project + ' - Task complete'
elif event_lower in ['session.idle','session_idle']:
    category = 'complete'
    status = 'done'
    marker = '* '
    notify = '1'
    notify_color = 'yellow'
    msg = project + ' - Waiting for input'
elif event_lower in ['permissionrequest','permission_request','permission','needs_permission']:
    category = 'permission'
    status = 'needs approval'
    marker = '* '
    notify = '1'
    notify_color = 'red'
    msg = project + ' - Permission needed'
elif event_lower in ['notification','notify']:
    if ntype == 'permission_prompt':
        category = 'permission'
        status = 'needs approval'
        marker = '* '
        notify = '1'
        notify_color = 'red'
        msg = project + ' - Permission needed'
    elif ntype == 'idle_prompt':
        status = 'done'
        marker = '* '
        notify = '1'
        notify_color = 'yellow'
        msg = project + ' - Waiting for input'
    elif ntype == 'resource_limit':
        category = 'resource_limit'
        status = 'limited'
        marker = '* '
        notify = '1'
        notify_color = 'yellow'
        msg = project + ' - Resource limit'
    else:
        print('PEON_EXIT=true')
        sys.exit(0)
elif event_lower in ['error','failure','tool_error','posttoolusefailure','task_error']:
    category = 'error'
    status = 'error'
    marker = '* '
    notify = '1'
    notify_color = 'red'
    msg = project + ' - Error'
else:
    print('PEON_EXIT=true')
    sys.exit(0)

if pack_rotation:
    session_packs = state.get('session_packs', {})
    if session_id in session_packs and session_packs[session_id] in pack_rotation:
        active_pack = session_packs[session_id]
    else:
        active_pack = random.choice(pack_rotation)
        session_packs[session_id] = active_pack
        state['session_packs'] = session_packs
        state_dirty = True

if category and not cat_enabled.get(category, True):
    category = ''

sound_file = ''
if category and not paused:
    pack_dir = os.path.join(packs_dir, active_pack)
    try:
        manifest = json.load(open(os.path.join(pack_dir, 'manifest.json')))
        sounds = manifest.get('categories', {}).get(category, {}).get('sounds', [])
        if sounds:
            last_played = state.get('last_played', {})
            last_file = last_played.get(category, '')
            candidates = sounds if len(sounds) <= 1 else [s for s in sounds if s['file'] != last_file]
            pick = random.choice(candidates)
            last_played[category] = pick['file']
            state['last_played'] = last_played
            state_dirty = True
            sound_file = os.path.join(pack_dir, 'sounds', pick['file'])
    except:
        pass

if state_dirty:
    os.makedirs(os.path.dirname(state_file) or '.', exist_ok=True)
    json.dump(state, open(state_file, 'w'))

print('PEON_EXIT=false')
print('EVENT=' + q(event))
print('VOLUME=' + q(str(volume)))
print('AUDIO_PLAYER=' + q(str(audio_player)))
print('PROJECT=' + q(project))
print('STATUS=' + q(status))
print('MARKER=' + q(marker))
print('NOTIFY=' + q(notify))
print('NOTIFY_COLOR=' + q(notify_color))
print('MSG=' + q(msg))
print('CATEGORY=' + q(category))
print('SOUND_FILE=' + q(sound_file))
" <<< "$INPUT" 2>/dev/null)"

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

wait
exit 0
