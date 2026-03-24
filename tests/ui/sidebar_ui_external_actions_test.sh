#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

export TMUX_SIDEBAR_STATE_DIR="$TEST_TMP/state"
mkdir -p "$TMUX_SIDEBAR_STATE_DIR"

output="$(TMUX_PANE=%99 python3 - <<'PY'
import importlib.util
import json
import os
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

state_dir = Path(os.environ["TMUX_SIDEBAR_STATE_DIR"])

module.curses.curs_set = lambda _: None
module.curses.mousemask = lambda _: (0, 0)
module.curses.COLS = 40
module.curses.LINES = 10

closed = {"count": 0}
getch_calls = {"count": 0}


def fake_load_tree():
    return [
        {"kind": "session", "text": "work"},
        {"kind": "window", "text": "editor"},
        {"kind": "pane", "pane_id": "%1", "text": "pane one"},
        {"kind": "pane", "pane_id": "%2", "text": "pane two"},
        {"kind": "pane", "pane_id": "%3", "text": "pane three"},
        {"kind": "pane", "pane_id": "%4", "text": "pane four"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda name: "%2" if name == "@tmux_sidebar_main_pane" else ""
module.close_sidebar = lambda: closed.__setitem__("count", closed["count"] + 1)
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None
module.focus_main_pane = lambda: None


class FakeScreen:
    def __init__(self, keys):
        self.keys = list(keys)
        self.lines = {}
        self.frames = []

    def keypad(self, enabled):
        pass

    def timeout(self, milliseconds):
        pass

    def erase(self):
        self.lines = {}

    def addnstr(self, y, x, text, limit, attr=0):
        self.lines[y] = text[:limit]

    def refresh(self):
        frame = [self.lines[index] for index in sorted(self.lines)]
        self.frames.append(frame)

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        getch_calls["count"] += 1
        action_file = state_dir / "sidebar-%99.actions"
        if getch_calls["count"] == 4:
            action_file.write_text("jump_back\n", encoding="utf-8")
            module._refresh_requested = True
        elif getch_calls["count"] == 5:
            action_file.write_text("jump_forward\n", encoding="utf-8")
            module._refresh_requested = True
        return self.keys.pop(0)


def selected_history(frames):
    history = []
    for frame in frames:
        selected = next((line.replace("▶ ", "", 1).strip() for line in frame if line.startswith("▶ ")), None)
        if selected is None:
            continue
        if not history or history[-1] != selected:
            history.append(selected)
    return history


screen = FakeScreen([ord("G"), ord("g"), ord("g"), -1, -1, ord("q")])
module.run_interactive(screen)

print(
    json.dumps(
        {
            "close_calls": closed["count"],
            "selected_history": selected_history(screen.frames),
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

assert_contains "$output" '"close_calls": 1'
assert_contains "$output" '"selected_history": ["pane two", "pane four", "pane one", "pane four", "pane one"]'
