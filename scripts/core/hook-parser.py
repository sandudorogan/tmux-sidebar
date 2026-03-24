#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any


def load_payload(raw_payload: str) -> dict[str, Any]:
    payload = raw_payload.strip()
    if not payload:
        return {}
    try:
        loaded = json.loads(payload)
    except Exception:
        return {}
    return loaded if isinstance(loaded, dict) else {}


def parse_claude(payload: str) -> tuple[str, str]:
    data = load_payload(payload)
    event = str(data.get("hook_event_name") or os.environ.get("CLAUDE_HOOK_EVENT_NAME") or "").strip()
    notification_type = str(data.get("notification_type") or "").strip().lower()
    message = str(data.get("message") or data.get("notification_type") or "").strip()

    if event in ("SessionStart", "SessionEnd"):
        status = "idle"
    elif event == "UserPromptSubmit":
        status = "running"
    elif event == "Notification" and notification_type == "idle_prompt":
        status = "idle"
    elif event in ("Notification", "PermissionRequest"):
        status = "needs-input"
    elif event == "Stop":
        status = "done"
    elif event == "PostToolUseFailure":
        status = "error"
    else:
        status = "running"

    return status, message


def parse_codex(event: str, payload: str) -> tuple[str, str]:
    data = load_payload(payload)
    raw_event = str(
        event
        or data.get("hook_event_name")
        or data.get("event")
        or data.get("type")
        or ""
    ).strip().lower().replace("_", "-")
    notif_type = str(data.get("notification_type") or "").strip().lower()
    status_hint = str(data.get("status") or data.get("state") or "").strip().lower().replace("_", "-")
    message = str(data.get("summary") or data.get("transcript_summary") or data.get("message") or "").strip()

    done_events = {
        "agent-turn-complete",
        "complete",
        "completed",
        "done",
        "finish",
        "finished",
        "session-end",
        "stop",
        "stopped",
        "task-complete",
        "turn-complete",
    }
    done_statuses = {
        "complete",
        "completed",
        "done",
        "finished",
        "stopped",
    }
    idle_events = {
        "session-start",
    }
    running_events = {
        "agent-turn-start",
        "agent-turn-started",
        "start",
        "task-start",
        "task-started",
        "turn-start",
        "turn-started",
    }

    if raw_event in done_events or status_hint in done_statuses:
        status = "done"
    elif raw_event in idle_events:
        status = "idle"
    elif raw_event in running_events:
        status = "running"
    elif (
        raw_event.startswith("permission")
        or raw_event.startswith("approve")
        or raw_event in ("approval-requested", "approval-needed", "input-required")
        or notif_type == "permission_prompt"
    ):
        status = "needs-input"
    elif raw_event.startswith("error") or raw_event.startswith("fail"):
        status = "error"
    elif notif_type == "idle_prompt" or raw_event == "idle-prompt":
        status = "idle"
    elif status_hint == "running":
        status = "running"
    else:
        status = ""

    return status, message


def parse_opencode(event: str, payload: str) -> tuple[str, str]:
    data = load_payload(payload)
    raw_event = str(
        event
        or data.get("hook_event_name")
        or data.get("event")
        or data.get("type")
        or ""
    ).strip().lower().replace("_", "-")
    status_hint = str(data.get("status") or data.get("state") or "").strip().lower().replace("_", "-")
    message = str(data.get("summary") or data.get("transcript_summary") or data.get("message") or "").strip()

    if raw_event == "session.error" or status_hint in ("error", "failed"):
        status = "error"
    elif raw_event == "permission.asked":
        status = "needs-input"
    elif raw_event == "session.created" or status_hint in ("idle", "ready"):
        status = "idle"
    elif raw_event == "session.status" or status_hint == "running":
        status = "running"
    elif raw_event == "session.idle":
        status = "done"
    else:
        status = "needs-input" if status_hint else ""

    return status, message


def write_result(status: str, message: str) -> None:
    print(status)
    if message:
        print(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", choices=("claude", "codex", "opencode"))
    parser.add_argument("event", nargs="?", default="")
    args = parser.parse_args()

    payload = os.environ.get("HOOK_PAYLOAD", "")
    if args.app == "claude":
        status, message = parse_claude(payload)
    elif args.app == "codex":
        status, message = parse_codex(args.event, payload)
    else:
        status, message = parse_opencode(args.event, payload)
    write_result(status, message)


if __name__ == "__main__":
    main()
