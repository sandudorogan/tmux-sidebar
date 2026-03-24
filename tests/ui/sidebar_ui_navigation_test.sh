#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
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

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
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
        {"kind": "pane", "pane_id": "%1", "text": "pane one"},
        {"kind": "pane", "pane_id": "%2", "text": "pane two"},
        {"kind": "pane", "pane_id": "%3", "text": "pane three"},
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


screen = FakeScreen([ord("G"), ord("g"), ord("g"), ord("q")])
module.run_interactive(screen)

bottom_selected = any(
    any("▶ pane three" in line for line in frame)
    for frame in screen.frames
)
top_selected_after_gg = any("▶ pane one" in line for line in screen.frames[-1])

print(
    json.dumps(
        {
            "bottom_selected": bottom_selected,
            "close_calls": closed["count"],
            "top_selected_after_gg": top_selected_after_gg,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

assert_contains "$output" '"bottom_selected": true'
assert_contains "$output" '"close_calls": 1'
assert_contains "$output" '"top_selected_after_gg": true'

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
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


screen = FakeScreen([ord("G"), ord("g"), ord("g"), 15, 15, 9, 9, ord("q")])
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
assert_contains "$output" '"selected_history": ["pane two", "pane four", "pane one", "pane four", "pane two", "pane four", "pane one"]'

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.curses.curs_set = lambda _: None
module.curses.mousemask = lambda _: (0, 0)
module.curses.COLS = 40
module.curses.LINES = 10

closed = {"count": 0}
focus_state = {"value": True}
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
module.sidebar_has_focus = lambda: focus_state["value"]
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
        if getch_calls["count"] == 2:
            focus_state["value"] = False
            module._refresh_requested = True
        elif getch_calls["count"] == 3:
            focus_state["value"] = True
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


screen = FakeScreen([ord("G"), -1, 15, ord("q")])
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
assert_contains "$output" '"selected_history": ["pane two", "pane four", "pane two"]'

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

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
        if getch_calls["count"] == 5:
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


screen = FakeScreen([ord("G"), ord("g"), ord("g"), 15, -1, 9, ord("q")])
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

fake_tmux_no_sidebar
fake_tmux_register_pane "%1" "work" "@1" "editor" "pane one"
fake_tmux_register_pane "%2" "work" "@1" "editor" "pane two"
fake_tmux_register_main_pane "%1"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
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

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
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
