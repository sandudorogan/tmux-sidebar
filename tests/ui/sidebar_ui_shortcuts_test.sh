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

shortcuts = module.configured_shortcuts()
print(json.dumps(shortcuts, sort_keys=True))
pending, selected, action, changed = module.process_keypress(15, "%2", [{"pane_id": "%1"}, {"pane_id": "%2"}], "", shortcuts)
print(json.dumps({"action": action, "changed": changed, "pending": pending, "selected": selected}, sort_keys=True))
pending, selected, action, changed = module.process_keypress(9, "%2", [{"pane_id": "%1"}, {"pane_id": "%2"}], "", shortcuts)
print(json.dumps({"action": action, "changed": changed, "pending": pending, "selected": selected}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "g", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "g", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "G", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "r", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "r", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "w", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "a", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "w", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "x", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'
assert_contains "$output" '{"action": "jump_back", "changed": false, "pending": "", "selected": "%2"}'
assert_contains "$output" '{"action": "jump_forward", "changed": false, "pending": "", "selected": "%2"}'
assert_contains "$output" '{"action": null, "pending": "g"}'
assert_contains "$output" '{"action": "go_top", "pending": ""}'
assert_contains "$output" '{"action": "go_bottom", "pending": ""}'
assert_contains "$output" '{"action": null, "pending": "r"}'
assert_contains "$output" '{"action": "rename_session", "pending": ""}'
assert_contains "$output" '{"action": "rename_window", "pending": ""}'
assert_contains "$output" '{"action": null, "pending": "a"}'
assert_contains "$output" '{"action": "add_window", "pending": ""}'
assert_contains "$output" '{"action": "close_pane", "pending": ""}'

printf 'zw\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'zs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'tt\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_go_top_shortcut.txt"
printf 'B\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_go_bottom_shortcut.txt"
printf 'C-p\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_back_shortcut.txt"
printf 'C-n\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_forward_shortcut.txt"
printf 'rsess\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'rwin\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_window_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

shortcuts = module.configured_shortcuts()
print(json.dumps(shortcuts, sort_keys=True))
pending, selected, action, changed = module.process_keypress(16, "%2", [{"pane_id": "%1"}, {"pane_id": "%2"}], "", shortcuts)
print(json.dumps({"action": action, "changed": changed, "pending": pending, "selected": selected}, sort_keys=True))
pending, selected, action, changed = module.process_keypress(14, "%2", [{"pane_id": "%1"}, {"pane_id": "%2"}], "", shortcuts)
print(json.dumps({"action": action, "changed": changed, "pending": pending, "selected": selected}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "t", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "t", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "B", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "z", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "r", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "e", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "r", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "w", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "i", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "n", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "x", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "zs", "add_window": "zw", "close_pane": "x", "go_bottom": "B", "go_top": "tt", "jump_back": "C-p", "jump_forward": "C-n", "rename_session": "rsess", "rename_window": "rwin"}'
assert_contains "$output" '{"action": "jump_back", "changed": false, "pending": "", "selected": "%2"}'
assert_contains "$output" '{"action": "jump_forward", "changed": false, "pending": "", "selected": "%2"}'
assert_contains "$output" '{"action": null, "pending": "t"}'
assert_contains "$output" '{"action": "go_top", "pending": ""}'
assert_contains "$output" '{"action": "go_bottom", "pending": ""}'
assert_contains "$output" '{"action": null, "pending": "z"}'
assert_contains "$output" '{"action": "add_session", "pending": ""}'
assert_contains "$output" '{"action": null, "pending": "r"}'
assert_contains "$output" '{"action": null, "pending": "rs"}'
assert_contains "$output" '{"action": null, "pending": "rse"}'
assert_contains "$output" '{"action": null, "pending": "rses"}'
assert_contains "$output" '{"action": "rename_session", "pending": ""}'
assert_contains "$output" '{"action": null, "pending": "rw"}'
assert_contains "$output" '{"action": null, "pending": "rwi"}'
assert_contains "$output" '{"action": "rename_window", "pending": ""}'
assert_contains "$output" '{"action": "close_pane", "pending": ""}'

printf 'w\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'sess\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'gg\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_go_top_shortcut.txt"
printf 'G\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_go_bottom_shortcut.txt"
printf 'C-o\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_back_shortcut.txt"
printf 'C-i\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_forward_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'rw\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_window_shortcut.txt"
printf 'xx\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

shortcuts = module.configured_shortcuts()
print(json.dumps(shortcuts, sort_keys=True))
pending, action = module.advance_shortcut_state("", "r", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "r", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "w", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "w", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "e", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "s", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state("", "x", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
pending, action = module.advance_shortcut_state(pending, "x", shortcuts)
print(json.dumps({"pending": pending, "action": action}, sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "sess", "add_window": "w", "close_pane": "xx", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'
assert_contains "$output" '{"action": null, "pending": "r"}'
assert_contains "$output" '{"action": "rename_session", "pending": ""}'
assert_contains "$output" '{"action": "rename_window", "pending": ""}'
assert_contains "$output" '{"action": "add_window", "pending": ""}'
assert_contains "$output" '{"action": null, "pending": "s"}'
assert_contains "$output" '{"action": null, "pending": "se"}'
assert_contains "$output" '{"action": null, "pending": "ses"}'
assert_contains "$output" '{"action": "add_session", "pending": ""}'
assert_contains "$output" '{"action": null, "pending": "x"}'
assert_contains "$output" '{"action": "close_pane", "pending": ""}'

printf 'zw\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'zs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'gg\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_go_top_shortcut.txt"
printf 'qG\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_go_bottom_shortcut.txt"
printf 'C-o\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_back_shortcut.txt"
printf 'G\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_forward_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'qs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf 'a\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'as\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'x\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf '\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf '\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf '\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'

printf 'zz\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_window_shortcut.txt"
printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_add_session_shortcut.txt"
printf 'rs\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_rename_session_shortcut.txt"
printf 'xy\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_close_pane_shortcut.txt"

output="$(python3 - <<'PY'
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

print(json.dumps(module.configured_shortcuts(), sort_keys=True))
PY
)"

assert_contains "$output" '{"add_session": "as", "add_window": "aw", "close_pane": "x", "go_bottom": "G", "go_top": "gg", "jump_back": "C-o", "jump_forward": "C-i", "rename_session": "rs", "rename_window": "rw"}'
