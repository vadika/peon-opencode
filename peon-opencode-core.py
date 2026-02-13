#!/usr/bin/env python3
import argparse
import glob
import json
import os
import random
import re
import shlex
import sys
import time


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def shell_kv(name, value):
    print(f"{name}={shlex.quote(str(value))}")


def available_pack_names(packs_dir):
    return sorted(
        [
            os.path.basename(os.path.dirname(m))
            for m in glob.glob(os.path.join(packs_dir, "*/manifest.json"))
        ]
    )


def cmd_list_packs(args):
    cfg = load_json(args.config, {})
    active = cfg.get("active_pack", "peon")
    for manifest_path in sorted(glob.glob(os.path.join(args.packs_dir, "*/manifest.json"))):
        info = load_json(manifest_path, {})
        name = info.get("name", os.path.basename(os.path.dirname(manifest_path)))
        display = info.get("display_name", name)
        marker = " *" if name == active else ""
        print(f"  {name:24s} {display}{marker}")
    return 0


def cmd_set_pack(args):
    names = available_pack_names(args.packs_dir)
    if not names:
        print("Error: no packs found", file=sys.stderr)
        return 1

    cfg = load_json(args.config, {})
    current = cfg.get("active_pack", "peon")

    if args.pack:
        target = args.pack
        if target not in names:
            print(f'Error: pack "{target}" not found.', file=sys.stderr)
            print(f"Available packs: {', '.join(names)}", file=sys.stderr)
            return 1
    else:
        try:
            idx = names.index(current)
            target = names[(idx + 1) % len(names)]
        except ValueError:
            target = names[0]

    cfg["active_pack"] = target
    save_json(args.config, cfg)

    display = load_json(os.path.join(args.packs_dir, target, "manifest.json"), {}).get(
        "display_name", target
    )
    print(f"peon-opencode: switched to {target} ({display})")
    return 0


def parse_bool(value, default=True):
    if value is None:
        return default
    return str(value).lower() == "true"


def cmd_process_event(args):
    try:
        event_data = json.loads(sys.stdin.read() or "{}")
    except Exception as exc:
        shell_kv("PEON_EXIT", "true")
        shell_kv("PEON_ERROR", f"invalid event JSON: {exc}")
        return 0

    cfg = load_json(args.config, {})
    if not parse_bool(cfg.get("enabled", True), default=True):
        shell_kv("PEON_EXIT", "true")
        return 0

    volume = cfg.get("volume", 0.5)
    audio_player = cfg.get("audio_player", "")
    active_pack = cfg.get("active_pack", "peon")
    pack_rotation = cfg.get("pack_rotation", [])
    annoyed_threshold = int(cfg.get("annoyed_threshold", 3))
    annoyed_window = float(cfg.get("annoyed_window_seconds", 10))

    cats = cfg.get("categories", {})
    cat_enabled = {
        c: parse_bool(cats.get(c, True), default=True)
        for c in [
            "greeting",
            "acknowledge",
            "complete",
            "error",
            "permission",
            "resource_limit",
            "annoyed",
        ]
    }

    payload = event_data.get("payload", {}) if isinstance(event_data, dict) else {}
    properties = payload.get("properties", {}) if isinstance(payload, dict) else {}

    event = (
        event_data.get("event")
        or event_data.get("hook_event_name")
        or event_data.get("type")
        or payload.get("type")
        or ""
    )
    ntype = (
        event_data.get("notification_type")
        or event_data.get("notification")
        or properties.get("notification_type")
        or ""
    )
    cwd = (
        event_data.get("cwd")
        or event_data.get("workdir")
        or event_data.get("project_dir")
        or properties.get("directory")
        or event_data.get("directory")
        or ""
    )
    session_id = (
        event_data.get("session_id")
        or event_data.get("session")
        or event_data.get("run_id")
        or properties.get("sessionID")
        or properties.get("session_id")
        or ""
    )
    project = event_data.get("project") or properties.get("project") or ""

    state = load_json(args.state, {})
    state_dirty = False

    if not project:
        project = cwd.rsplit("/", 1)[-1] if cwd else "opencode"
    if not project:
        project = "opencode"
    project = re.sub(r"[^a-zA-Z0-9 ._-]", "", project)

    event_lower = str(event).lower()
    category = ""
    status = ""
    marker = ""
    notify = ""
    notify_color = ""
    msg = ""

    if event_lower in ["sessionstart", "session_start", "start", "session"]:
        category = "greeting"
        status = "ready"
    elif event_lower in [
        "userpromptsubmit",
        "prompt_submit",
        "prompt",
        "user_prompt",
        "prompted",
    ]:
        status = "working"
        if cat_enabled.get("annoyed", True):
            all_ts = state.get("prompt_timestamps", {})
            if isinstance(all_ts, list):
                all_ts = {}
            now = time.time()
            ts = [t for t in all_ts.get(session_id, []) if now - t < annoyed_window]
            ts.append(now)
            all_ts[session_id] = ts
            state["prompt_timestamps"] = all_ts
            state_dirty = True
            if len(ts) >= annoyed_threshold:
                category = "annoyed"
    elif event_lower in [
        "stop",
        "task_complete",
        "task_done",
        "complete",
        "finished",
        "session.completed",
        "session_completed",
    ]:
        category = "complete"
        status = "done"
        marker = "* "
        notify = "1"
        notify_color = "blue"
        msg = project + " - Task complete"
    elif event_lower in ["session.idle", "session_idle"]:
        category = "complete"
        status = "done"
        marker = "* "
        notify = "1"
        notify_color = "yellow"
        msg = project + " - Waiting for input"
    elif event_lower in ["permissionrequest", "permission_request", "permission", "needs_permission"]:
        category = "permission"
        status = "needs approval"
        marker = "* "
        notify = "1"
        notify_color = "red"
        msg = project + " - Permission needed"
    elif event_lower in ["notification", "notify"]:
        if ntype == "permission_prompt":
            category = "permission"
            status = "needs approval"
            marker = "* "
            notify = "1"
            notify_color = "red"
            msg = project + " - Permission needed"
        elif ntype == "idle_prompt":
            status = "done"
            marker = "* "
            notify = "1"
            notify_color = "yellow"
            msg = project + " - Waiting for input"
        elif ntype == "resource_limit":
            category = "resource_limit"
            status = "limited"
            marker = "* "
            notify = "1"
            notify_color = "yellow"
            msg = project + " - Resource limit"
        else:
            shell_kv("PEON_EXIT", "true")
            return 0
    elif event_lower in ["error", "failure", "tool_error", "posttoolusefailure", "task_error"]:
        category = "error"
        status = "error"
        marker = "* "
        notify = "1"
        notify_color = "red"
        msg = project + " - Error"
    else:
        shell_kv("PEON_EXIT", "true")
        return 0

    if pack_rotation:
        session_packs = state.get("session_packs", {})
        if session_id in session_packs and session_packs[session_id] in pack_rotation:
            active_pack = session_packs[session_id]
        else:
            active_pack = random.choice(pack_rotation)
            session_packs[session_id] = active_pack
            state["session_packs"] = session_packs
            state_dirty = True

    if category and not cat_enabled.get(category, True):
        category = ""

    sound_file = ""
    if category and not args.paused:
        pack_dir = os.path.join(args.packs_dir, active_pack)
        manifest = load_json(os.path.join(pack_dir, "manifest.json"), {})
        sounds = manifest.get("categories", {}).get(category, {}).get("sounds", [])
        if sounds:
            last_played = state.get("last_played", {})
            last_file = last_played.get(category, "")
            candidates = sounds if len(sounds) <= 1 else [s for s in sounds if s.get("file") != last_file]
            pick = random.choice(candidates)
            last_played[category] = pick.get("file", "")
            state["last_played"] = last_played
            state_dirty = True
            sound_file = os.path.join(pack_dir, "sounds", pick.get("file", ""))

    if state_dirty:
        os.makedirs(os.path.dirname(args.state) or ".", exist_ok=True)
        with open(args.state, "w") as f:
            json.dump(state, f)

    shell_kv("PEON_EXIT", "false")
    shell_kv("EVENT", event)
    shell_kv("VOLUME", volume)
    shell_kv("AUDIO_PLAYER", audio_player)
    shell_kv("PROJECT", project)
    shell_kv("STATUS", status)
    shell_kv("MARKER", marker)
    shell_kv("NOTIFY", notify)
    shell_kv("NOTIFY_COLOR", notify_color)
    shell_kv("MSG", msg)
    shell_kv("CATEGORY", category)
    shell_kv("SOUND_FILE", sound_file)
    return 0


def main():
    parser = argparse.ArgumentParser(prog="peon-opencode-core")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list-packs")
    p_list.add_argument("--config", required=True)
    p_list.add_argument("--packs-dir", required=True)
    p_list.set_defaults(func=cmd_list_packs)

    p_set = sub.add_parser("set-pack")
    p_set.add_argument("--config", required=True)
    p_set.add_argument("--packs-dir", required=True)
    p_set.add_argument("--pack", default="")
    p_set.set_defaults(func=cmd_set_pack)

    p_proc = sub.add_parser("process-event")
    p_proc.add_argument("--config", required=True)
    p_proc.add_argument("--state", required=True)
    p_proc.add_argument("--packs-dir", required=True)
    p_proc.add_argument("--paused", action="store_true")
    p_proc.set_defaults(func=cmd_process_event)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
