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

# --- ensure_visible with scrolloff ---
# No scrolloff: basic edge-only behavior
assert module.ensure_visible(2, 5, 10, 0) == 2, "no scrolloff: scroll up to row"
assert module.ensure_visible(15, 5, 10, 0) == 6, "no scrolloff: scroll down to row"
assert module.ensure_visible(7, 5, 10, 0) == 5, "no scrolloff: row in view, no scroll"

# With scrolloff=2
assert module.ensure_visible(2, 5, 10, 2) == 0, "scrolloff=2: scroll up with margin"
assert module.ensure_visible(6, 5, 10, 2) == 4, "scrolloff=2: row within top margin triggers scroll"
assert module.ensure_visible(13, 5, 10, 2) == 6, "scrolloff=2: row within bottom margin triggers scroll"
assert module.ensure_visible(9, 5, 10, 2) == 5, "scrolloff=2: row in middle, no scroll"

# With scrolloff=8 (default)
assert module.ensure_visible(10, 0, 20, 8) == 0, "scrolloff=8: row in comfort zone, no scroll"
assert module.ensure_visible(13, 0, 20, 8) == 2, "scrolloff=8: row near bottom triggers scroll"
assert module.ensure_visible(5, 10, 20, 8) == 0, "scrolloff=8: scroll up near top"

# None row_index returns 0
assert module.ensure_visible(None, 5, 10) == 0, "None row should return 0"

# Small viewport (visible_lines=3, scrolloff=2): margin clamped to 1
assert module.ensure_visible(0, 2, 3, 2) == 0, "small viewport: scroll to top"

# Tiny viewport (visible_lines=1): margin is 0
assert module.ensure_visible(3, 5, 1, 8) == 3, "tiny viewport: scroll to row"

print(json.dumps({"ensure_visible": "ok"}))
PY
)"

assert_contains "$output" '"ensure_visible": "ok"'

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
module.curses.LINES = 4

module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
module.close_sidebar = lambda: None
module.focus_main_pane = lambda: None
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None


def fake_load_tree():
    return [
        {"kind": "session", "text": "work"},
        {"kind": "window", "text": "editor"},
        {"kind": "pane", "pane_id": "%1", "text": "pane one"},
        {"kind": "pane", "pane_id": "%2", "text": "pane two"},
        {"kind": "pane", "pane_id": "%3", "text": "pane three"},
        {"kind": "pane", "pane_id": "%4", "text": "pane four"},
        {"kind": "pane", "pane_id": "%5", "text": "pane five"},
        {"kind": "pane", "pane_id": "%6", "text": "pane six"},
    ]


module.load_tree = fake_load_tree


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
        frame = [self.lines.get(index, "") for index in range(module.curses.LINES)]
        self.frames.append(frame)

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


# Scroll down to bottom, then back up to top
DOWN = module.curses.KEY_DOWN
UP = module.curses.KEY_UP
keys = [DOWN] * 5 + [UP] * 5 + [ord("q")]
screen = FakeScreen(keys)
module.run_interactive(screen)

last_frame = screen.frames[-1]

# After going all the way down and back up, the first pane should be visible
print(
    json.dumps(
        {
            "frames_count": len(screen.frames),
            "last_frame": last_frame,
            "first_frame": screen.frames[0],
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

assert_contains "$output" 'pane one'
first_frame="$(printf '%s' "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['first_frame']))")"
last_frame="$(printf '%s' "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['last_frame']))")"

assert_contains "$last_frame" 'pane one'

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
module.curses.LINES = 4

module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda _: ""
module.close_sidebar = lambda: None
module.focus_main_pane = lambda: None
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None


def fake_load_tree():
    return [
        {"kind": "session", "text": "work"},
        {"kind": "window", "text": "editor"},
        {"kind": "pane", "pane_id": "%1", "text": "pane one"},
        {"kind": "pane", "pane_id": "%2", "text": "pane two"},
        {"kind": "pane", "pane_id": "%3", "text": "pane three"},
        {"kind": "pane", "pane_id": "%4", "text": "pane four"},
        {"kind": "pane", "pane_id": "%5", "text": "pane five"},
        {"kind": "pane", "pane_id": "%6", "text": "pane six"},
    ]


module.load_tree = fake_load_tree

MOUSE = module.curses.KEY_MOUSE
SCROLL_DOWN = module.MOUSE_SCROLL_DOWN

mouse_queue = []


def fake_getmouse():
    if mouse_queue:
        return mouse_queue.pop(0)
    return (0, 0, 0, 0, 0)


module.curses.getmouse = fake_getmouse


class FakeScreen:
    def __init__(self, keys):
        self.keys = list(keys)
        self.lines = {}
        self.frames = []
        self.force_refresh_before = set()

    def keypad(self, enabled):
        pass

    def timeout(self, milliseconds):
        pass

    def erase(self):
        self.lines = {}

    def addnstr(self, y, x, text, limit, attr=0):
        self.lines[y] = text[:limit]

    def refresh(self):
        frame = [self.lines.get(index, "") for index in range(module.curses.LINES)]
        self.frames.append(frame)

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        key_index = len(self.frames)
        if key_index in self.force_refresh_before:
            module._refresh_requested = True
        return self.keys.pop(0)


# Mouse scroll down, then trigger a SIGUSR1-like refresh, then quit.
# The viewport should stay scrolled (refresh must not snap back to cursor).
mouse_queue.extend([(0, 0, 0, 0, SCROLL_DOWN)] * 2)

keys = [MOUSE, MOUSE, ord("q")]
screen = FakeScreen(keys)
screen.force_refresh_before = {2}
module.run_interactive(screen)

# Cursor indicator should never appear on any pane other than pane one
cursor_moved = any(
    any("▶" in line and "pane one" not in line for line in frame)
    for frame in screen.frames
)

# After scrolling, viewport should have moved past the session header
last_frame = screen.frames[-1]
viewport_scrolled = "work" not in last_frame[0] if last_frame else False

print(
    json.dumps(
        {
            "cursor_did_not_move": not cursor_moved,
            "viewport_scrolled": viewport_scrolled,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

assert_contains "$output" '"cursor_did_not_move": true'
assert_contains "$output" '"viewport_scrolled": true'
