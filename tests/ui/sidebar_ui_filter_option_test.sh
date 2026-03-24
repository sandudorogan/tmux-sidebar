#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

export TMUX_SIDEBAR_STATE_DIR="$TEST_TMP/state"
mkdir -p "$TMUX_SIDEBAR_STATE_DIR"

fake_tmux_no_sidebar
fake_tmux_set_tree <<'EOF'
work|@1|editor|%1|nvim|shell|0
work|@1|editor|%2|codex-aarch64-apple-darwin|codex --full-auto|1
work|@2|runner|%3|node|repo worker|0
ops|@3|review|%4|python3|assistant runner|0
ops|@4|shells|%5|zsh|zsh|0
scratch|@5|notes|%6|bash|bash|0
EOF

cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%3.json" <<'EOF'
{"pane_id":"%3","app":"opencode","status":"running","updated_at":100}
EOF

cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%4.json" <<'EOF'
{"pane_id":"%4","app":"claude","status":"running","updated_at":100}
EOF

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = module.load_tree()
pane_ids = [row["pane_id"] for row in rows if row["kind"] == "pane"]
texts = [row["text"] for row in rows]

print(json.dumps({"pane_ids": pane_ids, "texts": texts}, ensure_ascii=False, sort_keys=True))
PY
)"

assert_contains "$output" '"%1"'
assert_contains "$output" '"%2"'
assert_contains "$output" '"%3"'
assert_contains "$output" '"%4"'
assert_contains "$output" '"%5"'
assert_contains "$output" '"%6"'

printf ' codex , CLAUDE , opencode \n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_filter.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = module.load_tree()
pane_ids = [row["pane_id"] for row in rows if row["kind"] == "pane"]
texts = [row["text"] for row in rows]

print(json.dumps({"pane_ids": pane_ids, "texts": texts}, ensure_ascii=False, sort_keys=True))
PY
)"

assert_not_contains "$output" '"%1"'
assert_contains "$output" '"%2"'
assert_contains "$output" '"%3"'
assert_contains "$output" '"%4"'
assert_not_contains "$output" '"%5"'
assert_not_contains "$output" '"%6"'

assert_contains "$output" 'work'
assert_contains "$output" 'ops'
assert_not_contains "$output" 'scratch'
assert_contains "$output" 'runner'
assert_contains "$output" 'review'
assert_not_contains "$output" 'shells'

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

module.configured_shortcuts = lambda: dict(module.DEFAULT_SHORTCUTS)
module.sidebar_has_focus = lambda: True
module.close_sidebar = lambda: None
module.focus_main_pane = lambda: None
module.prompt_add_window = lambda pane_id: None
module.prompt_add_session = lambda pane_id: None
module.prompt_rename_session = lambda pane_id: None
module.prompt_rename_window = lambda pane_id: None

filter_state = {"value": "on"}


def fake_tmux_option(opt):
    if opt == "@tmux_sidebar_filter_enabled":
        return filter_state["value"]
    return ""


module.tmux_option = fake_tmux_option

tmux_commands = []
original_run = __import__("subprocess").run


def capture_run(args, **kwargs):
    if args and args[0] == "tmux":
        cmd = " ".join(args)
        tmux_commands.append(cmd)
        if "set" in args and "@tmux_sidebar_filter_enabled" in args:
            filter_state["value"] = args[-1]
        return original_run(["true"], **kwargs)
    return original_run(args, **kwargs)


__import__("subprocess").run = capture_run


def fake_load_tree():
    if filter_state["value"] in ("on", "1", "true", "yes"):
        return [
            {"kind": "session", "text": "work", "session": "work"},
            {"kind": "window", "text": "agents", "session": "work", "window": "@1"},
            {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "codex", "active": True},
        ]
    return [
        {"kind": "session", "text": "work", "session": "work"},
        {"kind": "window", "text": "agents", "session": "work", "window": "@1"},
        {"kind": "pane", "pane_id": "%1", "session": "work", "window": "@1", "text": "shell", "active": False},
        {"kind": "pane", "pane_id": "%2", "session": "work", "window": "@1", "text": "codex", "active": True},
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
        self.frames.append([self.lines.get(i, "") for i in range(module.curses.LINES)])

    def getch(self):
        if not self.keys:
            raise AssertionError("getch called after key sequence ended")
        return self.keys.pop(0)


screen = FakeScreen([ord("f"), ord("f"), ord("q")])
module.run_interactive(screen)
__import__("subprocess").run = original_run

set_commands = [cmd for cmd in tmux_commands if "@tmux_sidebar_filter_enabled" in cmd]
print(json.dumps({"set_commands": set_commands}, ensure_ascii=False, sort_keys=True))
PY
)"

assert_contains "$output" '@tmux_sidebar_filter_enabled off'
assert_contains "$output" '@tmux_sidebar_filter_enabled on'
