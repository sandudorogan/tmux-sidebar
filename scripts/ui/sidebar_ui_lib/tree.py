from __future__ import annotations

import json
import subprocess
from collections import OrderedDict

from .core import STATE_DIR, SIDEBAR_TITLES, configured_sidebar_width, run_tmux, tmux_option
from .status import badge_for_status, effective_pane_status, normalize_token, pane_display_label, window_display_name


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


def configured_filter_tokens() -> list[str]:
    enabled_raw = tmux_option("@tmux_sidebar_filter_enabled").strip().lower()
    if enabled_raw in ("off", "0", "false", "no"):
        return []
    return [
        token
        for token in (normalize_token(value) for value in tmux_option("@tmux_sidebar_filter").split(","))
        if token
    ]


def pane_matches_filter(pane: dict, pane_state: dict, filter_tokens: list[str]) -> bool:
    if not filter_tokens:
        return True
    candidates = [
        normalize_token(pane["label"]),
        normalize_token(pane["title"]),
        normalize_token(str(pane_state.get("app", ""))),
        pane["label"].strip().lower(),
        pane["title"].strip().lower(),
    ]
    return any(token and any(token in candidate for candidate in candidates if candidate) for token in filter_tokens)


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

    filter_tokens = configured_filter_tokens()

    filtered_sessions: OrderedDict[str, dict] = OrderedDict()
    for session_name, session in sessions.items():
        filtered_windows: OrderedDict[str, dict] = OrderedDict()
        for window_id, window in session["windows"].items():
            panes = [
                pane
                for pane in window["panes"]
                if pane["title"] not in SIDEBAR_TITLES and pane_matches_filter(pane, pane_states.get(pane["id"], {}), filter_tokens)
            ]
            if not panes:
                continue
            filtered_windows[window_id] = {**window, "panes": panes}
        if filtered_windows:
            filtered_sessions[session_name] = {**session, "windows": filtered_windows}
    sessions = filtered_sessions

    hide_panes = tmux_option("@tmux_sidebar_hide_panes").lower() in ("on", "1", "true", "yes")

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
            visible_panes = window["panes"]
            if hide_panes:
                visible_panes = [
                    pane for pane in window["panes"]
                    if badge_for_status(effective_pane_status(
                        pane["id"], pane["label"], pane["title"], pane_states.get(pane["id"], {}),
                    ))
                ]
            window_row: dict = {
                "kind": "window",
                "session": session["name"],
                "window": window["id"],
                "text": f"{session_prefix}{'└─' if window_last else '├─'} {display_name}",
            }
            if hide_panes and not visible_panes:
                window_row["pane_id"] = window["id"]
            rows.append(window_row)
            for pane_index, pane in enumerate(visible_panes):
                pane_last = pane_index == len(visible_panes) - 1
                pane_state = pane_states.get(pane["id"], {})
                badge = badge_for_status(effective_pane_status(pane["id"], pane["label"], pane["title"], pane_state))
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
        (index for index, row in enumerate(rows) if row.get("pane_id") == selected_pane_id),
        None,
    )
    for index, row in enumerate(rows):
        prefix = "▶ " if index == selected_row else "  "
        rendered.append(truncate_line(prefix + row["text"], max_width))
    return rendered


def dump_render() -> None:
    print("\n".join(render_rows(load_tree(), tmux_option("@tmux_sidebar_main_pane"), configured_sidebar_width() - 1)))


def pane_rows_for(rows: list[dict]) -> list[dict]:
    return [row for row in rows if "pane_id" in row]


def reconcile_selected_pane(selected_pane_id: str, pane_rows: list[dict]) -> str:
    if not pane_rows:
        return ""
    if any(row["pane_id"] == selected_pane_id for row in pane_rows):
        return selected_pane_id
    if selected_pane_id.startswith("%"):
        try:
            window_id = run_tmux("display-message", "-p", "-t", selected_pane_id, "#{window_id}").strip()
        except subprocess.CalledProcessError:
            window_id = ""
        if window_id:
            window_row = next((row for row in pane_rows if row.get("window") == window_id), None)
            if window_row is not None:
                return window_row["pane_id"]
    return pane_rows[0]["pane_id"]


def find_search_matches(rows: list[dict], query: str) -> set[int]:
    if not query:
        return set()
    query_lower = query.lower()
    return {i for i, row in enumerate(rows) if query_lower in row["text"].lower()}


def next_search_match(rows: list[dict], selected_pane_id: str, search_matches: set[int], direction: int = 1) -> str:
    targets: list[tuple[int, str]] = []
    seen_pane_ids: set[str] = set()
    for i in sorted(search_matches):
        row = rows[i]
        if "pane_id" in row:
            pane_id = row["pane_id"]
            nav_idx = i
        else:
            pane_id = None
            nav_idx = None
            for j in range(i + 1, len(rows)):
                if "pane_id" in rows[j]:
                    pane_id = rows[j]["pane_id"]
                    nav_idx = j
                    break
        if pane_id and pane_id not in seen_pane_ids:
            targets.append((nav_idx, pane_id))
            seen_pane_ids.add(pane_id)
    if not targets:
        return selected_pane_id
    current_row_idx = next((i for i, row in enumerate(rows) if row.get("pane_id") == selected_pane_id), -1)
    if direction == 1:
        for nav_idx, pane_id in targets:
            if nav_idx > current_row_idx:
                return pane_id
        return targets[0][1]
    for nav_idx, pane_id in reversed(targets):
        if nav_idx < current_row_idx:
            return pane_id
    return targets[-1][1]


def find_selected_row_index(rows: list[dict], selected_pane_id: str) -> int | None:
    return next(
        (i for i, row in enumerate(rows) if row.get("pane_id") == selected_pane_id),
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
