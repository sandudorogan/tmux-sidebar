#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

# Set up a tree with multiple panes, one of which has an agent badge via state file
fake_tmux_no_sidebar
fake_tmux_set_tree <<'EOF'
work|@1|editor|%1|nvim|nvim|1
work|@1|editor|%2|claude|claude: running|0
work|@2|logs|%3|tail|tail|0
EOF

export TMUX_SIDEBAR_STATE_DIR="$TEST_TMP/state"
mkdir -p "$TMUX_SIDEBAR_STATE_DIR"

# Enable hide_panes
printf 'on\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_hide_panes.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = module.load_tree()
kinds = [row["kind"] for row in rows]
pane_ids = [row.get("pane_id", "") for row in rows if row["kind"] == "pane"]
texts = [row["text"] for row in rows]

print(
    json.dumps(
        {
            "kinds": kinds,
            "pane_ids": pane_ids,
            "row_count": len(rows),
            "texts": texts,
        },
        ensure_ascii=False,
        sort_keys=True,
    )
)
PY
)"

# Only pane %2 (claude with running status) should appear; %1 and %3 have no badge
assert_contains "$output" '"%2"'
assert_not_contains "$output" '"%1"'
assert_not_contains "$output" '"%3"'

# Sessions and windows should still appear
assert_contains "$output" '"session"'
assert_contains "$output" '"window"'

# The visible pane should show a badge
assert_contains "$output" '⏳'

# Now test with hide_panes off — all panes should appear
printf 'off\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_hide_panes.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = module.load_tree()
pane_ids = [row.get("pane_id", "") for row in rows if row["kind"] == "pane"]

print(json.dumps({"pane_ids": pane_ids}, ensure_ascii=False, sort_keys=True))
PY
)"

assert_contains "$output" '"%1"'
assert_contains "$output" '"%2"'
assert_contains "$output" '"%3"'

# Test connector: when only one pane is visible, it should use └─ (last item connector)
printf 'on\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_hide_panes.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = module.load_tree()
pane_texts = [row["text"] for row in rows if row["kind"] == "pane"]

print(json.dumps({"pane_texts": pane_texts}, ensure_ascii=False, sort_keys=True))
PY
)"

# Single visible pane should have └─ connector (last item)
assert_contains "$output" '└─'

# Test reconciliation: when the selected pane is hidden, cursor falls back to its window row
fake_tmux_no_sidebar
fake_tmux_register_pane "%3" "work" "@2" "logs" "tail"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

nav_rows = [
    {"kind": "window", "session": "work", "window": "@1", "pane_id": "@1"},
    {"kind": "window", "session": "work", "window": "@2", "pane_id": "@2"},
]

# %3 is in window @2 but hidden — reconcile should pick @2
result = module.reconcile_selected_pane("%3", nav_rows)
print(json.dumps({"selected": result}))
PY
)"

assert_contains "$output" '"selected": "@2"'

# Test window navigation: cursor should move between windows and visible panes
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

module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda opt: "on" if opt == "@tmux_sidebar_hide_panes" else ""
module.close_sidebar = lambda: None
module.focus_main_pane = lambda: None
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None


def fake_load_tree():
    return [
        {"kind": "session", "text": "work", "session": "work"},
        {
            "kind": "window",
            "text": "editor",
            "session": "work",
            "window": "@1",
            "pane_id": "@1",
        },
        {
            "kind": "window",
            "text": "logs",
            "session": "work",
            "window": "@2",
            "pane_id": "@2",
        },
        {
            "kind": "pane",
            "pane_id": "%5",
            "session": "work",
            "window": "@3",
            "text": "claude [~]",
            "active": False,
        },
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


DOWN = module.curses.KEY_DOWN
UP = module.curses.KEY_UP
# Navigate: down to @2, down to %5, up back to @2, quit
keys = [DOWN, DOWN, UP, ord("q")]
screen = FakeScreen(keys)
module.run_interactive(screen)

# frames[0]: initial render, cursor on @1
# frames[1]: after first down, cursor on @2
# frames[2]: after second down, cursor on %5
# frames[3]: after up, cursor back on @2
selections = []
for frame in screen.frames:
    for line in frame:
        if "▶" in line:
            selections.append(line.strip())
            break

print(json.dumps({"selections": selections}, ensure_ascii=False, sort_keys=True))
PY
)"

# Cursor should visit: @1 (editor), @2 (logs), %5 (claude), @2 (logs)
assert_contains "$output" '"▶ editor"'
assert_contains "$output" '"▶ logs"'
assert_contains "$output" '"▶ claude [~]"'

# Test x on a collapsed window: kill-window when session has multiple windows
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

module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda opt: "on" if opt == "@tmux_sidebar_hide_panes" else ""
module.close_sidebar = lambda: None
module.focus_main_pane = lambda: None
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None

tmux_commands = []
original_run = __import__("subprocess").run


def capture_run(args, **kwargs):
    if args and args[0] == "tmux":
        tmux_commands.append(" ".join(args))
    return original_run(args, **kwargs)


__import__("subprocess").run = capture_run


def fake_load_tree():
    return [
        {"kind": "session", "text": "work", "session": "work"},
        {"kind": "window", "text": "editor", "session": "work", "window": "@1", "pane_id": "@1"},
        {"kind": "window", "text": "logs", "session": "work", "window": "@2", "pane_id": "@2"},
    ]


module.load_tree = fake_load_tree

class FakeScreen:
    def __init__(self, keys):
        self.keys = list(keys)
        self.lines = {}
        self.frames = []
    def keypad(self, enabled): pass
    def timeout(self, milliseconds): pass
    def erase(self): self.lines = {}
    def addnstr(self, y, x, text, limit, attr=0): self.lines[y] = text[:limit]
    def refresh(self):
        self.frames.append([self.lines.get(i, "") for i in range(module.curses.LINES)])
    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)

# Press x on first window (@1), then quit
keys = [ord("x"), ord("q")]
screen = FakeScreen(keys)
module.run_interactive(screen)

__import__("subprocess").run = original_run
print(json.dumps({"commands": tmux_commands}, ensure_ascii=False, sort_keys=True))
PY
)"

# Two windows in the session — should kill-window, not kill-session
assert_contains "$output" 'kill-window -t @1'
assert_not_contains "$output" 'kill-session'

# Test x on a collapsed window: kill-session when it's the only window
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

module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.tmux_option = lambda opt: "on" if opt == "@tmux_sidebar_hide_panes" else ""
module.close_sidebar = lambda: None
module.focus_main_pane = lambda: None
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None

tmux_commands = []
original_run = __import__("subprocess").run


def capture_run(args, **kwargs):
    if args and args[0] == "tmux":
        tmux_commands.append(" ".join(args))
    return original_run(args, **kwargs)


__import__("subprocess").run = capture_run


def fake_load_tree():
    return [
        {"kind": "session", "text": "solo", "session": "solo"},
        {"kind": "window", "text": "editor", "session": "solo", "window": "@5", "pane_id": "@5"},
    ]


module.load_tree = fake_load_tree

class FakeScreen:
    def __init__(self, keys):
        self.keys = list(keys)
        self.lines = {}
        self.frames = []
    def keypad(self, enabled): pass
    def timeout(self, milliseconds): pass
    def erase(self): self.lines = {}
    def addnstr(self, y, x, text, limit, attr=0): self.lines[y] = text[:limit]
    def refresh(self):
        self.frames.append([self.lines.get(i, "") for i in range(module.curses.LINES)])
    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)

# Press x on the only window, then quit
keys = [ord("x"), ord("q")]
screen = FakeScreen(keys)
module.run_interactive(screen)

__import__("subprocess").run = original_run
print(json.dumps({"commands": tmux_commands}, ensure_ascii=False, sort_keys=True))
PY
)"

# Only one window in session — should kill-session
assert_contains "$output" 'kill-session -t solo'
assert_not_contains "$output" 'kill-window'
