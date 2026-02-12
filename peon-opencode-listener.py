#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import time
import urllib.request


def log(msg):
    print(f"[peon-opencode] {msg}", file=sys.stderr, flush=True)


def hook_command():
    cmd = os.environ.get("PEON_HOOK_CMD", "").strip()
    if cmd:
        return cmd
    peon_dir = os.environ.get(
        "PEON_DIR", os.path.expanduser("~/.opencode/hooks/peon-ping")
    )
    return os.path.join(peon_dir, "peon-opencode.sh")


def discover_port_from_ss():
    try:
        output = subprocess.check_output(
            ["ss", "-ltnp"], text=True, stderr=subprocess.DEVNULL
        )
    except Exception:
        return None
    for line in output.splitlines():
        if "opencode" not in line:
            continue
        match = re.search(r":(\d+)\s", line)
        if match:
            return int(match.group(1))
    return None


def discover_port_from_lsof():
    try:
        output = subprocess.check_output(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return None
    for line in output.splitlines():
        if "opencode" not in line:
            continue
        match = re.search(r"\:(\d+)->|\:(\d+)\s\(LISTEN\)", line)
        if match:
            port = match.group(1) or match.group(2)
            if port:
                return int(port)
    return None


def discover_server_url():
    env_url = os.environ.get("OPENCODE_SERVER_URL", "").strip()
    if env_url:
        return env_url.rstrip("/")
    env_port = os.environ.get("OPENCODE_SERVER_PORT", "").strip()
    if env_port.isdigit():
        return f"http://127.0.0.1:{env_port}"
    port = discover_port_from_ss() or discover_port_from_lsof()
    if port:
        return f"http://127.0.0.1:{port}"
    return None


def iter_sse(response):
    data_lines = []
    for raw in response:
        line = raw.decode("utf-8", errors="replace").rstrip("\n")
        if not line:
            if data_lines:
                yield "\n".join(data_lines)
                data_lines = []
            continue
        if line.startswith(":"):
            continue
        if line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
    if data_lines:
        yield "\n".join(data_lines)


def connect_event_stream(base_url):
    if base_url.endswith("/event") or base_url.endswith("/global/event"):
        url = base_url
    else:
        url = base_url + "/event"
    req = urllib.request.Request(url, headers={"Accept": "text/event-stream"})
    return urllib.request.urlopen(req, timeout=60)


def emit_hook(payload):
    cmd = hook_command()
    if not os.path.isfile(cmd):
        log(f"hook not found: {cmd}")
        return
    try:
        subprocess.run(
            [cmd],
            input=json.dumps(payload),
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except Exception as exc:
        log(f"hook failed: {exc}")


def handle_event(raw_event):
    if not isinstance(raw_event, dict):
        return
    directory = raw_event.get("directory") or raw_event.get("dir") or ""
    payload = (
        raw_event.get("payload")
        if isinstance(raw_event.get("payload"), dict)
        else raw_event
    )
    event_type = payload.get("type", "") if isinstance(payload, dict) else ""
    props = payload.get("properties", {}) if isinstance(payload, dict) else {}
    session_id = ""
    if isinstance(props, dict):
        session_id = props.get("sessionID") or props.get("session_id") or ""

    if event_type in ["session.created", "session_created"]:
        emit_hook(
            {"event": "session_start", "cwd": directory, "session_id": session_id}
        )
    elif event_type in ["session.completed", "session_completed"]:
        emit_hook(
            {"event": "session.completed", "cwd": directory, "session_id": session_id}
        )
    elif event_type in ["session.idle", "session_idle"]:
        emit_hook({"event": "session.idle", "cwd": directory, "session_id": session_id})
    elif event_type in ["permission.updated", "permission_updated"]:
        emit_hook(
            {"event": "permission_request", "cwd": directory, "session_id": session_id}
        )


def main():
    retry_delay = 2
    while True:
        base_url = discover_server_url()
        if not base_url:
            log(
                "no opencode server URL found; set OPENCODE_SERVER_URL or OPENCODE_SERVER_PORT"
            )
            time.sleep(5)
            continue
        try:
            log(f"connecting to {base_url}")
            with connect_event_stream(base_url) as response:
                for data in iter_sse(response):
                    try:
                        event = json.loads(data)
                    except Exception:
                        continue
                    handle_event(event)
        except Exception as exc:
            log(f"stream error: {exc}")
            time.sleep(retry_delay)


if __name__ == "__main__":
    main()
