#!/usr/bin/env python3
from __future__ import annotations

import argparse
import atexit
import curses
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from sidebar_ui_lib.core import (
    DEFAULT_SCROLLOFF,
    DEFAULT_SHORTCUTS,
    ESC_DELAY_MS,
    EXTRA_MOUSE_MASK,
    INPUT_POLL_MS,
    MOUSE_SCROLL_DOWN,
    MOUSE_SCROLL_LINES,
    REFRESH_INTERVAL_SECONDS,
    SHORTCUTS_CACHE_TTL_SECONDS,
    STATE_DIR,
    close_sidebar,
    configured_scrolloff,
    configured_shortcuts,
    configured_sidebar_width,
    focus_main_pane,
    prompt_add_session,
    prompt_add_window,
    prompt_rename_session,
    prompt_rename_window,
    sidebar_has_focus,
    shortcut_key_code,
    tmux_option,
    toggle_hide_panes,
)
from sidebar_ui_lib.render import _run_context_menu, _write_row_map, init_sidebar_colors, render_screen
from sidebar_ui_lib.tree import (
    dump_render,
    ensure_visible,
    find_search_matches,
    find_selected_row_index,
    load_tree,
    next_search_match,
    pane_rows_for,
    reconcile_selected_pane,
    render_rows,
    truncate_line,
)


_refresh_requested = False
_cached_shortcuts: dict[str, str] | None = None
_cached_shortcuts_at: float = 0.0


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
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = pid_path.with_suffix(".tmp")
        tmp.write_text(str(os.getpid()))
        tmp.rename(pid_path)
    except OSError:
        # The sidebar still works without refresh signaling; treat the pid file as best-effort.
        return


def _remove_pid_file() -> None:
    pid_path = _pid_file_path()
    if pid_path is None:
        return
    try:
        pid_path.unlink(missing_ok=True)
    except OSError:
        pass


def toggle_hide_panes() -> None:
    current = tmux_option("@tmux_sidebar_hide_panes").lower() in ("on", "1", "true", "yes")
    new_value = "off" if current else "on"
    subprocess.run(["tmux", "set", "-g", "@tmux_sidebar_hide_panes", new_value], check=False)


def toggle_filter() -> None:
    current = tmux_option("@tmux_sidebar_filter_enabled").strip().lower()
    enabled = current not in ("off", "0", "false", "no")
    new_value = "off" if enabled else "on"
    subprocess.run(["tmux", "set", "-g", "@tmux_sidebar_filter_enabled", new_value], check=False)


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


def selected_pane_row(pane_rows: list[dict], selected_pane_id: str) -> dict | None:
    return next((row for row in pane_rows if row["pane_id"] == selected_pane_id), pane_rows[0] if pane_rows else None)


def seed_jump_list(jump_list: list[str], jump_index: int, selected_pane_id: str) -> tuple[list[str], int]:
    if jump_list or not selected_pane_id:
        return jump_list, jump_index
    return [selected_pane_id], 0


def record_jump_target(jump_list: list[str], jump_index: int, pane_id: str) -> tuple[list[str], int]:
    if not pane_id:
        return jump_list, jump_index
    if jump_index < len(jump_list) - 1:
        jump_list = jump_list[: jump_index + 1]
    if jump_list and jump_list[-1] == pane_id:
        return jump_list, len(jump_list) - 1
    jump_list = [*jump_list, pane_id]
    return jump_list, len(jump_list) - 1


def jump_list_target(jump_list: list[str], jump_index: int, direction: int) -> tuple[str | None, int]:
    next_index = jump_index + direction
    if next_index < 0 or next_index >= len(jump_list):
        return None, jump_index
    return jump_list[next_index], next_index


def process_keypress(
    key: int,
    selected_pane_id: str,
    pane_rows: list[dict],
    pending_key: str,
    shortcuts: dict[str, str],
) -> tuple[str, str, str | None, bool]:
    key_char = chr(key) if 0 <= key <= 255 and chr(key).isprintable() else ""
    control_action = next((name for name, shortcut in shortcuts.items() if shortcut_key_code(shortcut) == key), None)
    if control_action is not None:
        return "", selected_pane_id, control_action, False
    if key == ord("q"):
        return "", selected_pane_id, "close", False
    if key == ord("m"):
        return "", selected_pane_id, "context_menu", False
    shortcut_prefix = pending_key or (key_char and any(shortcut.startswith(key_char) for shortcut in shortcuts.values()))
    if key_char and shortcut_prefix:
        pending_key, action = advance_shortcut_state(pending_key, key_char, shortcuts)
        if action == "go_top" and pane_rows:
            next_selected = pane_rows[0]["pane_id"]
            return pending_key, next_selected, action, next_selected != selected_pane_id
        if action == "go_bottom" and pane_rows:
            next_selected = pane_rows[-1]["pane_id"]
            return pending_key, next_selected, action, next_selected != selected_pane_id
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
    try:
        curses.start_color()
        curses.use_default_colors()
        active_attr, session_attr, window_attr, pane_attr = init_sidebar_colors()
    except curses.error:
        active_attr, session_attr, window_attr, pane_attr = curses.A_BOLD, 0, 0, 0
    if hasattr(curses, "set_escdelay"):
        curses.set_escdelay(ESC_DELAY_MS)
    stdscr.keypad(True)
    stdscr.timeout(INPUT_POLL_MS)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | EXTRA_MOUSE_MASK)

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
    search_mode = False
    search_query = ""
    search_matches: set[int] = set()
    jump_list: list[str] = []
    jump_index = -1

    while True:
        now = time.monotonic()
        signaled = _refresh_requested
        if signaled:
            _refresh_requested = False
        if next_refresh_at == 0.0 or signaled or now >= next_refresh_at:
            prev_pane = selected_pane_id
            rows, pane_rows, shortcuts, selected_pane_id = load_view_state(selected_pane_id)
            has_focus = sidebar_has_focus()
            scrolloff = configured_scrolloff()
            next_refresh_at = now + REFRESH_INTERVAL_SECONDS
            if not has_focus:
                jump_list = []
                jump_index = -1
            else:
                jump_list, jump_index = seed_jump_list(jump_list, jump_index, selected_pane_id)
            if selected_pane_id != prev_pane:
                user_scrolled = False
            if search_query:
                search_matches = find_search_matches(rows, search_query)
            visible_lines = curses.LINES - (1 if search_mode or search_query else 0)
            if not user_scrolled:
                selected_index = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(selected_index, scroll_offset, visible_lines, scrolloff)
            max_offset = max(0, len(rows) - visible_lines)
            scroll_offset = max(0, min(scroll_offset, max_offset))
            needs_render = True

        if needs_render:
            render_screen(
                stdscr,
                rows,
                selected_pane_id,
                scroll_offset,
                search_query,
                search_matches,
                search_mode,
                active_attr,
                session_attr,
                window_attr,
                pane_attr,
            )
            _write_row_map(rows, scroll_offset)
            needs_render = False

        key = stdscr.getch()
        if key == -1:
            continue

        if key == curses.KEY_RESIZE:
            selected_index = find_selected_row_index(rows, selected_pane_id)
            visible_lines = curses.LINES - (1 if search_mode or search_query else 0)
            scroll_offset = ensure_visible(selected_index, scroll_offset, visible_lines, scrolloff)
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
                max_offset = max(0, len(rows) - (curses.LINES - (1 if search_mode or search_query else 0)))
                scroll_offset = min(max_offset, scroll_offset + MOUSE_SCROLL_LINES)
                user_scrolled = True
                needs_render = True
                continue
            if bstate & (curses.BUTTON3_PRESSED | curses.BUTTON3_CLICKED):
                _run_context_menu(my)
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

        if search_mode:
            if key == 27:
                search_mode = False
                search_query = ""
                search_matches = set()
                selected_index = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(selected_index, scroll_offset, curses.LINES, scrolloff)
            elif key in (10, 13):
                search_mode = False
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                if search_query:
                    search_query = search_query[:-1]
                search_matches = find_search_matches(rows, search_query)
                selected_index = find_selected_row_index(rows, selected_pane_id)
                if search_matches and (selected_index is None or selected_index not in search_matches):
                    selected_pane_id = next_search_match(rows, selected_pane_id, search_matches, 1)
                user_scrolled = False
                selected_index = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(selected_index, scroll_offset, curses.LINES - 1, scrolloff)
            elif 32 <= key <= 126:
                search_query += chr(key)
                search_matches = find_search_matches(rows, search_query)
                selected_index = find_selected_row_index(rows, selected_pane_id)
                if search_matches and (selected_index is None or selected_index not in search_matches):
                    selected_pane_id = next_search_match(rows, selected_pane_id, search_matches, 1)
                user_scrolled = False
                selected_index = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(selected_index, scroll_offset, curses.LINES - 1, scrolloff)
            needs_render = True
            continue

        if not pending_key and key == ord("p"):
            toggle_hide_panes()
            next_refresh_at = 0.0
            needs_render = True
            continue

        if not pending_key and key == ord("/"):
            search_mode = True
            search_query = ""
            search_matches = set()
            needs_render = True
            continue

        if not pending_key and search_query:
            if key == ord("n"):
                selected_pane_id = next_search_match(rows, selected_pane_id, search_matches, 1)
                user_scrolled = False
                selected_index = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(selected_index, scroll_offset, curses.LINES - 1, scrolloff)
                needs_render = True
                continue
            if key == ord("N"):
                selected_pane_id = next_search_match(rows, selected_pane_id, search_matches, -1)
                user_scrolled = False
                selected_index = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(selected_index, scroll_offset, curses.LINES - 1, scrolloff)
                needs_render = True
                continue
            if key == 27:
                search_query = ""
                search_matches = set()
                selected_index = find_selected_row_index(rows, selected_pane_id)
                scroll_offset = ensure_visible(selected_index, scroll_offset, curses.LINES, scrolloff)
                needs_render = True
                continue

        pending_key, selected_pane_id, action, selection_changed = process_keypress(
            key,
            selected_pane_id,
            pane_rows,
            pending_key,
            shortcuts,
        )
        if selection_changed:
            if action in ("go_top", "go_bottom"):
                jump_list, jump_index = record_jump_target(jump_list, jump_index, selected_pane_id)
            user_scrolled = False
            selected_index = find_selected_row_index(rows, selected_pane_id)
            visible_lines = curses.LINES - (1 if search_query else 0)
            scroll_offset = ensure_visible(selected_index, scroll_offset, visible_lines, scrolloff)
            needs_render = True
            continue

        target = selected_pane_row(pane_rows, selected_pane_id)
        if action == "add_window" and target is not None:
            prompt_add_window(target["pane_id"])
            next_refresh_at = 0.0
        elif action == "add_session" and target is not None:
            prompt_add_session(target["pane_id"])
            next_refresh_at = 0.0
        elif action == "rename_session" and target is not None:
            prompt_rename_session(target["pane_id"])
            next_refresh_at = 0.0
        elif action == "rename_window" and target is not None:
            prompt_rename_window(target["pane_id"])
            next_refresh_at = 0.0
        elif action == "close_pane" and target is not None:
            cur_idx = next((i for i, row in enumerate(pane_rows) if row["pane_id"] == target["pane_id"]), 0)
            if cur_idx + 1 < len(pane_rows):
                selected_pane_id = pane_rows[cur_idx + 1]["pane_id"]
            elif cur_idx > 0:
                selected_pane_id = pane_rows[cur_idx - 1]["pane_id"]
            if target["kind"] == "pane":
                subprocess.run(["tmux", "kill-pane", "-t", target["pane_id"]], check=False)
            elif target["kind"] == "window":
                session_windows = [row for row in rows if row["kind"] == "window" and row.get("session") == target["session"]]
                if len(session_windows) <= 1:
                    subprocess.run(["tmux", "kill-session", "-t", target["session"]], check=False)
                else:
                    subprocess.run(["tmux", "kill-window", "-t", target["window"]], check=False)
            next_refresh_at = 0.0
        elif action == "toggle_filter":
            toggle_filter()
            next_refresh_at = 0.0
            needs_render = True
        elif action == "close":
            close_sidebar()
            break
        elif action == "focus_main":
            focus_main_pane()
            next_refresh_at = 0.0
        elif action == "jump_back":
            next_selected, jump_index = jump_list_target(jump_list, jump_index, -1)
            if next_selected is not None:
                selected_pane_id = next_selected
                user_scrolled = False
                selected_index = find_selected_row_index(rows, selected_pane_id)
                visible_lines = curses.LINES - (1 if search_query else 0)
                scroll_offset = ensure_visible(selected_index, scroll_offset, visible_lines, scrolloff)
                needs_render = True
        elif action == "jump_forward":
            next_selected, jump_index = jump_list_target(jump_list, jump_index, 1)
            if next_selected is not None:
                selected_pane_id = next_selected
                user_scrolled = False
                selected_index = find_selected_row_index(rows, selected_pane_id)
                visible_lines = curses.LINES - (1 if search_query else 0)
                scroll_offset = ensure_visible(selected_index, scroll_offset, visible_lines, scrolloff)
                needs_render = True
        elif action == "select_pane" and target is not None:
            subprocess.run(["tmux", "switch-client", "-t", target["session"]], check=False)
            subprocess.run(["tmux", "select-window", "-t", target["window"]], check=False)
            if target["kind"] == "pane":
                subprocess.run(["tmux", "select-pane", "-t", target["pane_id"]], check=False)
            next_refresh_at = 0.0
        elif action == "context_menu":
            selected_index = find_selected_row_index(rows, selected_pane_id)
            if selected_index is not None:
                _run_context_menu(max(0, selected_index - scroll_offset))
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
