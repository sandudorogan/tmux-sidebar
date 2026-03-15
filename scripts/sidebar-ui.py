#!/usr/bin/env python3
from __future__ import annotations

import argparse
import atexit
import curses
import json
import os
import re
import signal
import shlex
import subprocess
import time
from collections import OrderedDict
from pathlib import Path


STATE_DIR = Path(os.environ.get(
    "TMUX_SIDEBAR_STATE_DIR",
    os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")) + "/tmux-sidebar",
))
DEFAULT_SIDEBAR_WIDTH = 25
DEFAULT_SHORTCUTS = {
    "add_window": "aw",
    "add_session": "as",
    "close_pane": "x",
}
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
SIDEBAR_TITLES = {"Sidebar", "tmux-sidebar"}
INPUT_POLL_MS = 25
REFRESH_INTERVAL_SECONDS = 2.0
SHORTCUTS_CACHE_TTL_SECONDS = 30.0
ESC_DELAY_MS = 25
if hasattr(curses, "BUTTON5_PRESSED"):
    MOUSE_SCROLL_DOWN = curses.BUTTON5_PRESSED
    _EXTRA_MOUSE_MASK = 0
else:
    _EXTRA_MOUSE_MASK = getattr(curses, "REPORT_MOUSE_POSITION", 0x08000000)
    MOUSE_SCROLL_DOWN = _EXTRA_MOUSE_MASK
MOUSE_SCROLL_LINES = 3
DEFAULT_SCROLLOFF = 8

_refresh_requested = False


def _handle_sigusr1(signum: int, frame: object) -> None:
    global _refresh_requested
    _refresh_requested = True


def _pid_file_path() -> Path | None:
    pane = os.environ.get("TMUX_PANE", "")
    if not pane:
        return None
    return STATE_DIR / f"sidebar-{pane}.pid"


def _write_pid_file() -> None:
    pid_path = _pid_file_path()
    if pid_path is None:
        return
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = pid_path.with_suffix(".tmp")
    tmp.write_text(str(os.getpid()))
    tmp.rename(pid_path)


def _remove_pid_file() -> None:
    pid_path = _pid_file_path()
    if pid_path is None:
        return
    try:
        pid_path.unlink(missing_ok=True)
    except OSError:
        pass


def run_tmux(*args: str) -> str:
    return subprocess.check_output(["tmux", *args], text=True, stderr=subprocess.DEVNULL)


def badge_for_status(status: str) -> str:
    return {
        "needs-input": "[?]",
        "done": "[!]",
        "error": "[x]",
        "running": "[~]",
    }.get(status, "")


def tmux_option(option_name: str) -> str:
    try:
        return run_tmux("show-options", "-gv", option_name).strip()
    except subprocess.CalledProcessError:
        return ""


def configured_scrolloff() -> int:
    raw = tmux_option("@tmux_sidebar_scrolloff")
    if raw:
        try:
            value = int(raw)
            if value >= 0:
                return value
        except (TypeError, ValueError):
            pass
    return DEFAULT_SCROLLOFF


def configured_sidebar_width() -> int:
    for raw_width in (os.environ.get("TMUX_SIDEBAR_WIDTH", ""), tmux_option("@tmux_sidebar_width"), str(DEFAULT_SIDEBAR_WIDTH)):
        try:
            width = int(raw_width)
        except (TypeError, ValueError):
            continue
        if width > 0:
            return width
    return DEFAULT_SIDEBAR_WIDTH


def configured_shortcuts() -> dict[str, str]:
    shortcuts: dict[str, str] = {}
    for action, default_shortcut in DEFAULT_SHORTCUTS.items():
        try:
            shortcut = run_tmux("show-options", "-gv", f"@tmux_sidebar_{action}_shortcut").strip()
        except subprocess.CalledProcessError:
            shortcuts[action] = default_shortcut
            continue
        if not shortcut:
            return dict(DEFAULT_SHORTCUTS)
        shortcuts[action] = shortcut
    shortcut_values = list(shortcuts.values())
    if any("q" in shortcut for shortcut in shortcut_values):
        return dict(DEFAULT_SHORTCUTS)
    if len(set(shortcut_values)) != len(shortcuts):
        return dict(DEFAULT_SHORTCUTS)
    if any(
        shortcut != other_shortcut and other_shortcut.startswith(shortcut)
        for shortcut in shortcut_values
        for other_shortcut in shortcut_values
    ):
        return dict(DEFAULT_SHORTCUTS)
    return shortcuts


def normalize_token(value: str) -> str:
    token = value.strip().lower()
    if "/" in token:
        token = token.rsplit("/", 1)[-1]
    return token


def looks_like_codex(value: str) -> bool:
    return normalize_token(value).startswith("codex")


def looks_like_claude(value: str) -> bool:
    token = normalize_token(value)
    if token == "claude" or token.startswith("claude-") or token.startswith("claude_"):
        return True
    return bool(re.search(r"\bclaude\b", value, re.IGNORECASE))


def looks_like_semver(value: str) -> bool:
    return bool(SEMVER_PATTERN.match(normalize_token(value)))


def should_preserve_live_label(command: str, title: str) -> bool:
    command_token = normalize_token(command)
    title_token = normalize_token(title)
    return command_token in NON_AGENT_COMMANDS or title_token in NON_AGENT_COMMANDS


def state_agent_app(command: str, title: str, state: dict | None) -> str:
    app = str((state or {}).get("app", "")).strip().lower()
    status = str((state or {}).get("status", "")).strip().lower()
    if app not in ("claude", "codex"):
        return ""
    if should_preserve_live_label(command, title):
        return ""
    if app == "claude" and (looks_like_semver(command) or looks_like_semver(title)):
        return "claude"
    if status and status != "idle":
        return app
    return ""


def claude_title_status(title: str) -> str:
    match = re.search(r":\s*([a-z_-]+)\s*$", title.strip().lower())
    if match:
        suffix = match.group(1)
        return {
            "done": "done",
            "error": "error",
            "needs-input": "needs-input",
            "running": "running",
        }.get(suffix, "")
    if re.match(r"^[\u2800-\u28FF]", title.strip()):
        return "running"
    return ""


def live_agent_app(command: str, title: str, state: dict | None) -> str:
    if looks_like_codex(command) or looks_like_codex(title):
        return "codex"
    if looks_like_claude(command) or looks_like_claude(title):
        return "claude"
    if looks_like_semver(command) and not should_preserve_live_label(command, title):
        return "claude"
    return state_agent_app(command, title, state)


def codex_title_status(title: str) -> str:
    match = re.search(r":\s*([a-z-]+)\s*$", title.strip().lower())
    if not match:
        return ""

    suffix = match.group(1)
    return {
        "approval": "needs-input",
        "complete": "done",
        "completed": "done",
        "done": "done",
        "error": "error",
        "failed": "error",
        "failure": "error",
        "finished": "done",
        "input": "needs-input",
        "waiting": "needs-input",
    }.get(suffix, "")


def effective_pane_status(command: str, title: str, state: dict | None) -> str:
    live_app = live_agent_app(command, title, state)
    if not live_app:
        return ""

    status = str((state or {}).get("status", "")).strip().lower()
    if live_app == "codex":
        if status == "idle":
            return ""
        if status in ("running", "needs-input", "error", "done"):
            return status
        title_status = codex_title_status(title)
        if title_status:
            return title_status
        return ""

    if status == "idle":
        return ""
    if status in ("running", "needs-input", "error", "done"):
        return status
    title_status = claude_title_status(title)
    if title_status:
        return title_status
    return ""


def pane_display_label(command: str, title: str, state: dict | None) -> str:
    live_app = live_agent_app(command, title, state)
    if live_app:
        return live_app

    return command


def window_display_name(window_name: str, panes: list[dict], pane_states: dict[str, dict]) -> str:
    if not looks_like_semver(window_name):
        return window_name

    for pane in sorted(panes, key=lambda p: not p["active"]):
        pane_state = pane_states.get(pane["id"], {})
        label = pane_display_label(pane["label"], pane["title"], pane_state)
        if label != pane["label"]:
            return label

    return window_name


def sidebar_has_focus() -> bool:
    sidebar_pane = os.environ.get("TMUX_PANE", "")
    if not sidebar_pane:
        return False
    try:
        return run_tmux("display-message", "-p", "-t", sidebar_pane, "#{pane_active}").strip() == "1"
    except subprocess.CalledProcessError:
        return False


def ordered_sessions(sessions: OrderedDict[str, dict]) -> list[dict]:
    configured_order = [name.strip() for name in tmux_option("@tmux_sidebar_session_order").split(",") if name.strip()]
    if not configured_order:
        return list(sessions.values())

    ordered: list[dict] = []
    seen: set[str] = set()
    for session_name in configured_order:
        session = sessions.get(session_name)
        if session is None or session_name in seen:
            continue
        ordered.append(session)
        seen.add(session_name)

    for session_name, session in sessions.items():
        if session_name in seen:
            continue
        ordered.append(session)
    return ordered


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

    filtered_sessions: OrderedDict[str, dict] = OrderedDict()
    for session_name, session in sessions.items():
        filtered_windows: OrderedDict[str, dict] = OrderedDict()
        for window_id, window in session["windows"].items():
            panes = [pane for pane in window["panes"] if pane["title"] not in SIDEBAR_TITLES]
            if not panes:
                continue
            filtered_windows[window_id] = {**window, "panes": panes}
        if filtered_windows:
            filtered_sessions[session_name] = {**session, "windows": filtered_windows}
    sessions = filtered_sessions

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
    session_items = ordered_sessions(sessions)
    for session_index, session in enumerate(session_items):
        session_last = session_index == len(session_items) - 1
        session_prefix = "   " if session_last else "│  "
        rows.append({"kind": "session", "session": session["name"], "text": f"{'└─' if session_last else '├─'} {session['name']}"})

        windows = list(session["windows"].values())
        for window_index, window in enumerate(windows):
            window_last = window_index == len(windows) - 1
            window_prefix = session_prefix + ("   " if window_last else "│  ")
            display_name = window_display_name(window["name"], window["panes"], pane_states)
            rows.append(
                {
                    "kind": "window",
                    "session": session["name"],
                    "window": window["id"],
                    "text": f"{session_prefix}{'└─' if window_last else '├─'} {display_name}",
                }
            )
            for pane_index, pane in enumerate(window["panes"]):
                pane_last = pane_index == len(window["panes"]) - 1
                pane_state = pane_states.get(pane["id"], {})
                badge = badge_for_status(effective_pane_status(pane["label"], pane["title"], pane_state))
                label = pane_display_label(pane["label"], pane["title"], pane_state)
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
    script_path = Path(__file__).with_name("close-sidebar.sh")
    pane_id = os.environ.get("TMUX_PANE", "")
    window_id = ""
    if pane_id:
        try:
            window_id = run_tmux("display-message", "-p", "-t", pane_id, "#{window_id}").strip()
        except subprocess.CalledProcessError:
            window_id = ""
    shell_command = " ".join(
        [
            "bash",
            shlex.quote(str(script_path)),
            shlex.quote(pane_id),
            shlex.quote(window_id),
        ]
    )
    subprocess.run(["tmux", "run-shell", "-b", shell_command], check=False)


def advance_shortcut_state(pending_key: str, key_char: str, shortcuts: dict[str, str]) -> tuple[str, str | None]:
    candidate = pending_key + key_char if pending_key else key_char
    action = next((name for name, shortcut in shortcuts.items() if shortcut == candidate), None)
    if action is not None:
        return "", action
    if any(shortcut.startswith(candidate) for shortcut in shortcuts.values()):
        return candidate, None
    if pending_key:
        action = next((name for name, shortcut in shortcuts.items() if shortcut == key_char), None)
        if action is not None:
            return "", action
        if any(shortcut.startswith(key_char) for shortcut in shortcuts.values()):
            return key_char, None
        return "", None
    return "", None


def prompt_for_name(prompt: str, script_name: str, arguments: list[str]) -> None:
    script_path = Path(__file__).with_name(script_name)
    shell_parts = ["bash", shlex.quote(str(script_path))]
    shell_parts.extend(shlex.quote(argument) for argument in arguments)
    shell_parts.extend(["--name", '"%%%"'])
    shell_command = " ".join(shell_parts)
    subprocess.run(
        [
            "tmux",
            "command-prompt",
            "-p",
            prompt,
            f"run-shell -b {shlex.quote(shell_command)}",
        ],
        check=False,
    )


def prompt_add_window(pane_id: str) -> None:
    try:
        metadata = run_tmux("display-message", "-p", "-t", pane_id, "#{session_name}|#{window_index}").strip()
    except subprocess.CalledProcessError:
        return
    if not metadata:
        return
    session_name, window_index = metadata.split("|", 1)
    if not session_name or not window_index:
        return
    prompt_for_name("window name:", "add-window.sh", ["--session", session_name, "--window-index", window_index])


def prompt_add_session(pane_id: str) -> None:
    try:
        session_name = run_tmux("display-message", "-p", "-t", pane_id, "#{session_name}").strip()
    except subprocess.CalledProcessError:
        return
    if not session_name:
        return
    prompt_for_name("session name:", "add-session.sh", ["--after-session", session_name])


def pane_rows_for(rows: list[dict]) -> list[dict]:
    return [row for row in rows if row["kind"] == "pane"]


def reconcile_selected_pane(selected_pane_id: str, pane_rows: list[dict]) -> str:
    if pane_rows and not any(row["pane_id"] == selected_pane_id for row in pane_rows):
        return pane_rows[0]["pane_id"]
    if not pane_rows:
        return ""
    return selected_pane_id


_cached_shortcuts: dict[str, str] | None = None
_cached_shortcuts_at: float = 0.0


def cached_configured_shortcuts() -> dict[str, str]:
    global _cached_shortcuts, _cached_shortcuts_at
    now = time.monotonic()
    if _cached_shortcuts is not None and now - _cached_shortcuts_at < SHORTCUTS_CACHE_TTL_SECONDS:
        return _cached_shortcuts
    _cached_shortcuts = configured_shortcuts()
    _cached_shortcuts_at = now
    return _cached_shortcuts


def load_view_state(selected_pane_id: str) -> tuple[list[dict], list[dict], dict[str, str], str]:
    rows = load_tree()
    pane_rows = pane_rows_for(rows)
    shortcuts = cached_configured_shortcuts()
    if not sidebar_has_focus():
        selected_pane_id = tmux_option("@tmux_sidebar_main_pane") or selected_pane_id
    return rows, pane_rows, shortcuts, reconcile_selected_pane(selected_pane_id, pane_rows)


def find_selected_row_index(rows: list[dict], selected_pane_id: str) -> int | None:
    return next(
        (i for i, row in enumerate(rows) if row["kind"] == "pane" and row.get("pane_id") == selected_pane_id),
        None,
    )


def ensure_visible(row_index: int | None, scroll_offset: int, visible_lines: int, scrolloff: int = 0) -> int:
    if row_index is None or visible_lines <= 0:
        return 0
    margin = min(scrolloff, max(0, (visible_lines - 1) // 2))
    if row_index < scroll_offset + margin:
        return max(0, row_index - margin)
    if row_index >= scroll_offset + visible_lines - margin:
        return row_index - visible_lines + 1 + margin
    return scroll_offset


def render_screen(stdscr, rows: list[dict], selected_pane_id: str, scroll_offset: int = 0) -> None:
    width = max(0, curses.COLS - 1)
    stdscr.erase()
    rendered = render_rows(rows, selected_pane_id, width)
    visible = rendered[scroll_offset:scroll_offset + curses.LINES]
    for y, line in enumerate(visible):
        if y >= curses.LINES:
            break
        stdscr.addnstr(y, 0, line, width)
    stdscr.refresh()


def selected_pane_row(pane_rows: list[dict], selected_pane_id: str) -> dict | None:
    return next((row for row in pane_rows if row["pane_id"] == selected_pane_id), pane_rows[0] if pane_rows else None)


def process_keypress(
    key: int,
    selected_pane_id: str,
    pane_rows: list[dict],
    pending_key: str,
    shortcuts: dict[str, str],
) -> tuple[str, str, str | None, bool]:
    key_char = chr(key) if 0 <= key <= 255 and chr(key).isprintable() else ""
    if key == ord("q"):
        return "", selected_pane_id, "close", False
    shortcut_prefix = pending_key or (key_char and any(shortcut.startswith(key_char) for shortcut in shortcuts.values()))
    if key_char and shortcut_prefix:
        pending_key, action = advance_shortcut_state(pending_key, key_char, shortcuts)
        return pending_key, selected_pane_id, action, False

    pending_key = ""
    if key == 27:
        return pending_key, selected_pane_id, "close", False
    if key in (ord("j"), curses.KEY_DOWN) and pane_rows:
        current_index = next(
            (index for index, row in enumerate(pane_rows) if row["pane_id"] == selected_pane_id),
            0,
        )
        next_selected = pane_rows[min(current_index + 1, len(pane_rows) - 1)]["pane_id"]
        return pending_key, next_selected, None, next_selected != selected_pane_id
    if key in (ord("k"), curses.KEY_UP) and pane_rows:
        current_index = next(
            (index for index, row in enumerate(pane_rows) if row["pane_id"] == selected_pane_id),
            0,
        )
        next_selected = pane_rows[max(current_index - 1, 0)]["pane_id"]
        return pending_key, next_selected, None, next_selected != selected_pane_id
    if key == 12:
        return pending_key, selected_pane_id, "focus_main", False
    if key in (10, 13) and pane_rows:
        return pending_key, selected_pane_id, "select_pane", False
    return pending_key, selected_pane_id, None, False


def run_interactive(stdscr) -> None:
    global _refresh_requested

    signal.signal(signal.SIGUSR1, _handle_sigusr1)
    _write_pid_file()
    atexit.register(_remove_pid_file)

    curses.curs_set(0)
    if hasattr(curses, "set_escdelay"):
        curses.set_escdelay(ESC_DELAY_MS)
    stdscr.keypad(True)
    stdscr.timeout(INPUT_POLL_MS)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | _EXTRA_MOUSE_MASK)

    selected_pane_id = tmux_option("@tmux_sidebar_main_pane")
    pending_key = ""
    rows: list[dict] = []
    pane_rows: list[dict] = []
    shortcuts = dict(DEFAULT_SHORTCUTS)
    scrolloff = DEFAULT_SCROLLOFF
    next_refresh_at = 0.0
    scroll_offset = 0
    user_scrolled = False
    needs_render = True

    while True:
        now = time.monotonic()
        signaled = _refresh_requested
        if signaled:
            _refresh_requested = False
        if next_refresh_at == 0.0 or signaled or now >= next_refresh_at:
            prev_pane = selected_pane_id
            rows, pane_rows, shortcuts, selected_pane_id = load_view_state(selected_pane_id)
            scrolloff = configured_scrolloff()
            next_refresh_at = now + REFRESH_INTERVAL_SECONDS
            if selected_pane_id != prev_pane:
                user_scrolled = False
            if not user_scrolled:
                sel_idx = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(sel_idx, scroll_offset, curses.LINES, scrolloff)
            max_offset = max(0, len(rows) - curses.LINES)
            scroll_offset = max(0, min(scroll_offset, max_offset))
            needs_render = True

        if needs_render:
            render_screen(stdscr, rows, selected_pane_id, scroll_offset)
            needs_render = False

        key = stdscr.getch()
        if key == -1:
            continue

        if key == curses.KEY_RESIZE:
            sel_idx = find_selected_row_index(rows, selected_pane_id)
            scroll_offset = ensure_visible(sel_idx, scroll_offset, curses.LINES, scrolloff)
            needs_render = True
            continue

        if key == curses.KEY_MOUSE:
            try:
                _, mx, my, _, bstate = curses.getmouse()
            except curses.error:
                continue
            if bstate & curses.BUTTON4_PRESSED:
                scroll_offset = max(0, scroll_offset - MOUSE_SCROLL_LINES)
                user_scrolled = True
                needs_render = True
                continue
            if bstate & MOUSE_SCROLL_DOWN:
                max_offset = max(0, len(rows) - curses.LINES)
                scroll_offset = min(max_offset, scroll_offset + MOUSE_SCROLL_LINES)
                user_scrolled = True
                needs_render = True
                continue
            if bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED):
                row_idx = my + scroll_offset
                if 0 <= row_idx < len(rows):
                    clicked = rows[row_idx]
                    if clicked["kind"] == "pane":
                        selected_pane_id = clicked["pane_id"]
                        needs_render = True
                        subprocess.run(["tmux", "switch-client", "-t", clicked["session"]], check=False)
                        subprocess.run(["tmux", "select-window", "-t", clicked["window"]], check=False)
                        subprocess.run(["tmux", "select-pane", "-t", clicked["pane_id"]], check=False)
                        next_refresh_at = 0.0
                    elif clicked["kind"] == "window":
                        subprocess.run(["tmux", "switch-client", "-t", clicked["session"]], check=False)
                        subprocess.run(["tmux", "select-window", "-t", clicked["window"]], check=False)
                        next_refresh_at = 0.0
                    elif clicked["kind"] == "session":
                        subprocess.run(["tmux", "switch-client", "-t", clicked["session"]], check=False)
                        next_refresh_at = 0.0
                continue

        pending_key, selected_pane_id, action, selection_changed = process_keypress(
            key,
            selected_pane_id,
            pane_rows,
            pending_key,
            shortcuts,
        )
        if selection_changed:
            user_scrolled = False
            sel_idx = find_selected_row_index(rows, selected_pane_id)
            scroll_offset = ensure_visible(sel_idx, scroll_offset, curses.LINES, scrolloff)
            needs_render = True
            continue

        target = selected_pane_row(pane_rows, selected_pane_id)
        if action == "add_window" and target is not None:
            prompt_add_window(target["pane_id"])
            next_refresh_at = 0.0
        elif action == "add_session" and target is not None:
            prompt_add_session(target["pane_id"])
            next_refresh_at = 0.0
        elif action == "close_pane" and target is not None:
            subprocess.run(["tmux", "kill-pane", "-t", target["pane_id"]], check=False)
            next_refresh_at = 0.0
        elif action == "close":
            close_sidebar()
            break
        elif action == "focus_main":
            focus_main_pane()
            next_refresh_at = 0.0
        elif action == "select_pane" and target is not None:
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
            next_refresh_at = 0.0


def interactive() -> None:
    curses.wrapper(run_interactive)


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
