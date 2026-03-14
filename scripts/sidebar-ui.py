#!/usr/bin/env python3
from __future__ import annotations

import argparse
import curses
import json
import os
import re
import subprocess
from collections import OrderedDict
from pathlib import Path


STATE_DIR = Path(os.environ.get("TMUX_SIDEBAR_STATE_DIR", str(Path.home() / ".tmux-sidebar/state")))
DEFAULT_SIDEBAR_WIDTH = 35
SEMVER_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
NON_AGENT_COMMANDS = {
    "",
    "ash",
    "bash",
    "fish",
    "htop",
    "ksh",
    "less",
    "nano",
    "nvim",
    "sh",
    "ssh",
    "tail",
    "tmux",
    "top",
    "vi",
    "vim",
    "yazi",
    "zsh",
}


def run_tmux(*args: str) -> str:
    return subprocess.check_output(["tmux", *args], text=True, stderr=subprocess.DEVNULL)


def badge_for_status(status: str) -> str:
    return {
        "needs-input": "[!]",
        "done": "[*]",
        "error": "[x]",
        "running": "[~]",
    }.get(status, "")


def tmux_option(option_name: str) -> str:
    try:
        return run_tmux("show-options", "-gv", option_name).strip()
    except subprocess.CalledProcessError:
        return ""


def configured_sidebar_width() -> int:
    for raw_width in (os.environ.get("TMUX_SIDEBAR_WIDTH", ""), tmux_option("@tmux_sidebar_width"), str(DEFAULT_SIDEBAR_WIDTH)):
        try:
            width = int(raw_width)
        except (TypeError, ValueError):
            continue
        if width > 0:
            return width
    return DEFAULT_SIDEBAR_WIDTH


def normalize_token(value: str) -> str:
    token = value.strip().lower()
    if "/" in token:
        token = token.rsplit("/", 1)[-1]
    return token


def looks_like_codex(value: str) -> bool:
    return normalize_token(value).startswith("codex")


def looks_like_claude(value: str) -> bool:
    token = normalize_token(value)
    return token == "claude" or token.startswith("claude-") or token.startswith("claude_")


def looks_like_semver(value: str) -> bool:
    return bool(SEMVER_PATTERN.match(normalize_token(value)))


def should_preserve_live_label(command: str, title: str) -> bool:
    command_token = normalize_token(command)
    title_token = normalize_token(title)
    return command_token in NON_AGENT_COMMANDS or title_token in NON_AGENT_COMMANDS


def pane_display_label(command: str, title: str, state: dict | None) -> str:
    if looks_like_codex(command) or looks_like_codex(title):
        return "codex"
    if looks_like_claude(command) or looks_like_claude(title):
        return "claude"

    app = str((state or {}).get("app", "")).strip().lower()
    if app == "claude" and not should_preserve_live_label(command, title):
        if looks_like_semver(command) or looks_like_semver(title):
            return "claude"

    return command


def sidebar_has_focus() -> bool:
    sidebar_pane = os.environ.get("TMUX_PANE", "")
    if not sidebar_pane:
        return False
    try:
        return run_tmux("display-message", "-p", "-t", sidebar_pane, "#{pane_active}").strip() == "1"
    except subprocess.CalledProcessError:
        return False


def load_tree() -> list[dict]:
    raw = run_tmux(
        "list-panes",
        "-a",
        "-F",
        "#{session_name}|#{window_id}|#{window_name}|#{pane_id}|#{pane_current_command}|#{pane_title}|#{pane_active}",
    )

    sessions: OrderedDict[str, dict] = OrderedDict()
    live_panes: set[str] = set()
    active_panes: set[str] = set()

    for line in raw.splitlines():
        if not line:
            continue
        session_name, window_id, window_name, pane_id, pane_label, pane_title, pane_active = line.split("|", 6)
        live_panes.add(pane_id)
        if pane_active == "1":
            active_panes.add(pane_id)
        session = sessions.setdefault(session_name, {"name": session_name, "windows": OrderedDict()})
        window = session["windows"].setdefault(
            window_id,
            {"id": window_id, "name": window_name, "panes": []},
        )
        window["panes"].append(
            {
                "id": pane_id,
                "label": pane_label,
                "title": pane_title,
                "session": session_name,
                "window": window_id,
                "active": pane_id in active_panes,
            }
        )

    for session in sessions.values():
        for window in session["windows"].values():
            has_non_sidebar = any(pane["title"] != "tmux-sidebar" for pane in window["panes"])
            if has_non_sidebar:
                window["panes"] = [pane for pane in window["panes"] if pane["title"] != "tmux-sidebar"]

    pane_states: dict[str, dict] = {}
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    for state_file in STATE_DIR.glob("pane-*.json"):
        pane_id = state_file.stem[len("pane-") :]
        if pane_id not in live_panes:
            try:
                state_file.unlink(missing_ok=True)
            except OSError:
                pass
            continue
        try:
            pane_states[pane_id] = json.loads(state_file.read_text())
        except Exception:
            continue

    rows: list[dict] = []
    session_items = list(sessions.values())
    for session_index, session in enumerate(session_items):
        session_last = session_index == len(session_items) - 1
        session_prefix = "   " if session_last else "│  "
        rows.append({"kind": "session", "text": f"{'└─' if session_last else '├─'} {session['name']}"})

        windows = list(session["windows"].values())
        for window_index, window in enumerate(windows):
            window_last = window_index == len(windows) - 1
            window_prefix = session_prefix + ("   " if window_last else "│  ")
            rows.append(
                {
                    "kind": "window",
                    "text": f"{session_prefix}{'└─' if window_last else '├─'} {window['name']}",
                }
            )
            for pane_index, pane in enumerate(window["panes"]):
                pane_last = pane_index == len(window["panes"]) - 1
                pane_state = pane_states.get(pane["id"], {})
                badge = badge_for_status(str(pane_state.get("status", "")))
                label = f"{pane['id']} {pane_display_label(pane['label'], pane['title'], pane_state)}"
                if badge:
                    label = f"{label} {badge}"
                rows.append(
                    {
                        "kind": "pane",
                        "pane_id": pane["id"],
                        "session": pane["session"],
                        "window": pane["window"],
                        "active": pane["active"],
                        "text": f"{window_prefix}{'└─' if pane_last else '├─'} {label}",
                    }
                )
    return rows


def truncate_line(line: str, width: int | None) -> str:
    if width is None:
        return line
    if width <= 0:
        return ""
    if len(line) <= width:
        return line
    if width == 1:
        return "…"
    return line[: width - 1] + "…"


def render_rows(rows: list[dict], selected_pane_id: str | None = None, max_width: int | None = None) -> list[str]:
    rendered: list[str] = []
    selected_row = next(
        (index for index, row in enumerate(rows) if row["kind"] == "pane" and row["pane_id"] == selected_pane_id),
        None,
    )
    for index, row in enumerate(rows):
        prefix = "▶ " if index == selected_row else "  "
        rendered.append(truncate_line(prefix + row["text"], max_width))
    return rendered


def dump_render() -> None:
    print("\n".join(render_rows(load_tree(), tmux_option("@tmux_sidebar_main_pane"), configured_sidebar_width() - 1)))


def focus_main_pane() -> None:
    subprocess.run(["bash", str(Path(__file__).with_name("focus-main-pane.sh"))], check=False)


def close_sidebar() -> None:
    subprocess.run(["bash", str(Path(__file__).with_name("toggle-sidebar.sh"))], check=False)


def interactive() -> None:
    def main(stdscr) -> None:
        curses.curs_set(0)
        stdscr.keypad(True)
        stdscr.timeout(250)
        selected_pane_id = ""

        while True:
            rows = load_tree()
            pane_rows = [row for row in rows if row["kind"] == "pane"]
            if not sidebar_has_focus():
                selected_pane_id = tmux_option("@tmux_sidebar_main_pane") or selected_pane_id
            if pane_rows and not any(row["pane_id"] == selected_pane_id for row in pane_rows):
                selected_pane_id = pane_rows[0]["pane_id"]
            if not pane_rows:
                selected_pane_id = ""

            stdscr.erase()
            for y, line in enumerate(render_rows(rows, selected_pane_id, max(0, curses.COLS - 1))):
                if y >= curses.LINES:
                    break
                stdscr.addnstr(y, 0, line, max(0, curses.COLS - 1))
            stdscr.refresh()

            key = stdscr.getch()
            if key == -1:
                continue
            if key in (ord("q"), 27):
                close_sidebar()
                break
            if key in (ord("j"), curses.KEY_DOWN) and pane_rows:
                current_index = next(
                    (index for index, row in enumerate(pane_rows) if row["pane_id"] == selected_pane_id),
                    0,
                )
                selected_pane_id = pane_rows[min(current_index + 1, len(pane_rows) - 1)]["pane_id"]
            elif key in (ord("k"), curses.KEY_UP) and pane_rows:
                current_index = next(
                    (index for index, row in enumerate(pane_rows) if row["pane_id"] == selected_pane_id),
                    0,
                )
                selected_pane_id = pane_rows[max(current_index - 1, 0)]["pane_id"]
            elif key == 12:
                focus_main_pane()
            elif key in (10, 13) and pane_rows:
                target = next((row for row in pane_rows if row["pane_id"] == selected_pane_id), pane_rows[0])
                subprocess.run(
                    [
                        "tmux",
                        "switch-client",
                        "-t",
                        target["session"],
                    ],
                    check=False,
                )
                subprocess.run(["tmux", "select-window", "-t", target["window"]], check=False)
                subprocess.run(["tmux", "select-pane", "-t", target["pane_id"]], check=False)

    curses.wrapper(main)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dump-render", action="store_true")
    args = parser.parse_args()

    if args.dump_render:
        dump_render()
    else:
        interactive()


if __name__ == "__main__":
    main()
