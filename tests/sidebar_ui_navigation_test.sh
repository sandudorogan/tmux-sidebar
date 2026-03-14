#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.curses.curs_set = lambda _: None
module.curses.COLS = 40
module.curses.LINES = 10

load_calls = {"count": 0}
closed = {"count": 0}


def fake_load_tree():
    load_calls["count"] += 1
    return [
        {"kind": "session", "text": "work"},
        {"kind": "window", "text": "editor"},
        {"kind": "pane", "pane_id": "%1", "text": "pane one"},
        {"kind": "pane", "pane_id": "%2", "text": "pane two"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
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

    def addnstr(self, y, x, text, limit):
        self.lines[y] = text[:limit]

    def refresh(self):
        frame = [self.lines[index] for index in sorted(self.lines)]
        self.frames.append(frame)

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


screen = FakeScreen([module.curses.KEY_DOWN, ord("q")])
module.run_interactive(screen)

print(
    json.dumps(
        {
            "close_calls": closed["count"],
            "frames": screen.frames,
            "load_calls": load_calls["count"],
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

assert_contains "$output" '"close_calls": 1'
assert_contains "$output" '"load_calls": 1'
assert_contains "$output" '▶ pane two'
