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
module.curses.mousemask = lambda _: (0, 0)
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

    def addnstr(self, y, x, text, limit, attr=0):
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

fake_tmux_no_sidebar
fake_tmux_register_pane "%1" "work" "@1" "editor" "pane one"
fake_tmux_register_pane "%2" "work" "@1" "editor" "pane two"
fake_tmux_register_main_pane "%1"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.curses.curs_set = lambda _: None
module.curses.mousemask = lambda _: (0, 0)
module.curses.COLS = 40
module.curses.LINES = 10

closed = {"count": 0}


def fake_load_tree():
    return [
        {"kind": "session", "text": "work"},
        {"kind": "window", "text": "editor"},
        {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "pane two"},
        {"kind": "pane", "pane_id": "%1", "session": "work", "window": "@1", "text": "pane one"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: {
    **dict(module.DEFAULT_SHORTCUTS),
    "close_pane": "dd",
}
module.sidebar_has_focus = lambda: True
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
        return self.keys.pop(0)


screen = FakeScreen([ord("d"), ord("d"), ord("q")])
module.run_interactive(screen)

print(
    json.dumps(
        {
            "close_calls": closed["count"],
            "frames": screen.frames,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

assert_contains "$output" '"close_calls": 1'
assert_contains "$output" '▶ pane one'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'kill-pane -t %1'
assert_file_not_contains "$TEST_TMUX_DATA_DIR/commands.log" 'kill-pane -t %2'

fake_tmux_no_sidebar
fake_tmux_set_tree <<'EOF'
work|@1|sidebar-only|%99|python3|Sidebar|0
EOF
fake_tmux_register_main_pane "%99"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows, pane_rows, shortcuts, selected_pane_id = module.load_view_state("%99")

print(
    json.dumps(
        {
            "pane_rows": pane_rows,
            "rows": rows,
            "selected_pane_id": selected_pane_id,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

assert_contains "$output" '"pane_rows": []'
assert_contains "$output" '"selected_pane_id": ""'
