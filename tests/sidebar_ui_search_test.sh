#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

# Test 1: / enters search mode, typing highlights matches, Enter confirms, n/N navigate
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
        {"kind": "pane", "pane_id": "%1", "session": "work", "window": "@1", "text": "vim"},
        {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "zsh"},
        {"kind": "pane", "pane_id": "%3", "session": "work", "window": "@1", "text": "vim-two"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
module.close_sidebar = lambda: closed.__setitem__("count", closed["count"] + 1)
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None
module.focus_main_pane = lambda: None

# Search for "vim", confirm, then n to next match, then q
keys = [
    ord("/"), ord("v"), ord("i"), ord("m"),  # type /vim
    10,          # Enter to confirm
    ord("n"),    # next match
    ord("q"),    # quit
]


class FakeScreen:
    def __init__(self, keys):
        self.keys = list(keys)
        self.lines = {}
        self.attrs = {}
        self.frames = []
        self.frame_attrs = []

    def keypad(self, enabled):
        pass

    def timeout(self, milliseconds):
        pass

    def erase(self):
        self.lines = {}
        self.attrs = {}

    def addnstr(self, y, x, text, limit, attr=0):
        self.lines[y] = text[:limit]
        self.attrs[y] = attr

    def refresh(self):
        frame = [self.lines.get(i, "") for i in range(max(self.lines.keys()) + 1 if self.lines else 0)]
        attrs = dict(self.attrs)
        self.frames.append(frame)
        self.frame_attrs.append(attrs)

    def move(self, y, x):
        pass

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


screen = FakeScreen(keys)
module.run_interactive(screen)

# Find the frame after Enter (search confirmed) and after n (next match)
# After confirming search, the selected pane should be %1 (first "vim" match)
# After pressing n, the selected pane should be %3 (second "vim" match)
result = {
    "close_calls": closed["count"],
    "frame_count": len(screen.frames),
}

# Check the last frame before quit - should show vim-two selected (after n)
last_frame = screen.frames[-1] if screen.frames else []
result["last_frame"] = last_frame

print(json.dumps(result, ensure_ascii=False, sort_keys=True))
PY
)"

assert_contains "$output" '"close_calls": 1'
assert_contains "$output" '▶ vim-two'

# Test 2: Esc during search input cancels search
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
        {"kind": "pane", "pane_id": "%1", "session": "work", "window": "@1", "text": "vim"},
        {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "zsh"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
module.close_sidebar = lambda: closed.__setitem__("count", closed["count"] + 1)
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None
module.focus_main_pane = lambda: None

# Type /zs then Esc to cancel, then Esc again to close
keys = [
    ord("/"), ord("z"), ord("s"),
    27,      # Esc cancels search
    27,      # Esc closes sidebar
]


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
        frame = [self.lines.get(i, "") for i in range(max(self.lines.keys()) + 1 if self.lines else 0)]
        self.frames.append(frame)

    def move(self, y, x):
        pass

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


screen = FakeScreen(keys)
module.run_interactive(screen)

# After Esc cancel, search bar should be gone. Second Esc closes.
result = {"close_calls": closed["count"]}
print(json.dumps(result))
PY
)"

assert_contains "$output" '"close_calls": 1'

# Test 3: Esc after confirmed search clears search, second Esc closes
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
        {"kind": "pane", "pane_id": "%1", "session": "work", "window": "@1", "text": "vim"},
        {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "zsh"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
module.close_sidebar = lambda: closed.__setitem__("count", closed["count"] + 1)
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None
module.focus_main_pane = lambda: None

# /vim Enter (confirm), Esc (clear search), Esc (close)
keys = [
    ord("/"), ord("v"), ord("i"), ord("m"),
    10,      # confirm
    27,      # clear search
    27,      # close sidebar
]


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
        frame = [self.lines.get(i, "") for i in range(max(self.lines.keys()) + 1 if self.lines else 0)]
        self.frames.append(frame)

    def move(self, y, x):
        pass

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


screen = FakeScreen(keys)
module.run_interactive(screen)

result = {"close_calls": closed["count"]}
print(json.dumps(result))
PY
)"

assert_contains "$output" '"close_calls": 1'

# Test 4: find_search_matches and next_search_match unit tests
output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = [
    {"kind": "session", "text": "work"},
    {"kind": "window", "text": "editor"},
    {"kind": "pane", "pane_id": "%1", "text": "vim"},
    {"kind": "pane", "pane_id": "%2", "text": "zsh"},
    {"kind": "pane", "pane_id": "%3", "text": "vim-two"},
]

# find_search_matches
matches = module.find_search_matches(rows, "vim")
assert matches == {2, 4}, f"expected {{2, 4}}, got {matches}"

matches_empty = module.find_search_matches(rows, "")
assert matches_empty == set(), f"expected empty set, got {matches_empty}"

matches_case = module.find_search_matches(rows, "VIM")
assert matches_case == {2, 4}, f"case insensitive failed: {matches_case}"

matches_none = module.find_search_matches(rows, "nonexistent")
assert matches_none == set(), f"expected empty set, got {matches_none}"

# next_search_match forward
matches = {2, 4}
result = module.next_search_match(rows, "%1", matches, 1)
assert result == "%3", f"expected %3 (next after %1 at row 2), got {result}"

result = module.next_search_match(rows, "%3", matches, 1)
assert result == "%1", f"expected %1 (wrap), got {result}"

# next_search_match backward
result = module.next_search_match(rows, "%3", matches, -1)
assert result == "%1", f"expected %1 (prev), got {result}"

result = module.next_search_match(rows, "%1", matches, -1)
assert result == "%3", f"expected %3 (wrap back), got {result}"

# no selectable matches
session_only = {0}
result = module.next_search_match(rows, "%1", session_only, 1)
assert result == "%1", f"expected %1 (unchanged), got {result}"

print(json.dumps({"status": "ok"}))
PY
)"

assert_contains "$output" '"status": "ok"'

# Test 5: N navigates backward
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
        {"kind": "pane", "pane_id": "%1", "session": "work", "window": "@1", "text": "vim"},
        {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "zsh"},
        {"kind": "pane", "pane_id": "%3", "session": "work", "window": "@1", "text": "vim-two"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
module.close_sidebar = lambda: closed.__setitem__("count", closed["count"] + 1)
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None
module.focus_main_pane = lambda: None

# /vim Enter, N (previous = wraps to last match = vim-two), q
keys = [
    ord("/"), ord("v"), ord("i"), ord("m"),
    10,          # confirm
    ord("N"),    # previous match (wraps to last = vim-two since we're on first)
    ord("q"),
]


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
        frame = [self.lines.get(i, "") for i in range(max(self.lines.keys()) + 1 if self.lines else 0)]
        self.frames.append(frame)

    def move(self, y, x):
        pass

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


screen = FakeScreen(keys)
module.run_interactive(screen)

last_frame = screen.frames[-1] if screen.frames else []
result = {"last_frame": last_frame, "close_calls": closed["count"]}
print(json.dumps(result, ensure_ascii=False))
PY
)"

assert_contains "$output" '"close_calls": 1'
assert_contains "$output" '▶ vim-two'

# Test 6: Backspace during search input removes last character
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
        {"kind": "pane", "pane_id": "%1", "session": "work", "window": "@1", "text": "vim"},
        {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "zsh"},
    ]


module.load_tree = fake_load_tree
module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
module.close_sidebar = lambda: closed.__setitem__("count", closed["count"] + 1)
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None
module.focus_main_pane = lambda: None

# /zsx backspace backspace (now /z), Enter to confirm, then q
keys = [
    ord("/"), ord("z"), ord("s"), ord("x"),
    127,     # backspace (removes x -> "zs")
    127,     # backspace (removes s -> "z")
    10,      # confirm search for "z"
    ord("q"),
]


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
        frame = [self.lines.get(i, "") for i in range(max(self.lines.keys()) + 1 if self.lines else 0)]
        self.frames.append(frame)

    def move(self, y, x):
        pass

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


screen = FakeScreen(keys)
module.run_interactive(screen)

last_frame = screen.frames[-1] if screen.frames else []
result = {"last_frame": last_frame, "close_calls": closed["count"]}
print(json.dumps(result, ensure_ascii=False))
PY
)"

assert_contains "$output" '"close_calls": 1'
# "zsh" matches "z", so it should be selected
assert_contains "$output" '▶ zsh'
