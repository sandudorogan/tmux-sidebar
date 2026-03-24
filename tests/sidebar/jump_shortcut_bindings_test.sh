#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fake_tmux_no_sidebar

TMUX_SIDEBAR_PLUGIN_DIR="$PLUGIN_DIR" bash scripts/features/sidebar/apply-key-overrides.sh

assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'bind-key -n C-o if-shell -F'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" "run-shell -b '"
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'request-sidebar-action.sh" jump_back'"'"''
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'send-keys C-o'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'bind-key -n C-i if-shell -F'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'request-sidebar-action.sh" jump_forward'"'"''
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'send-keys C-i'

fake_tmux_no_sidebar
printf 'C-p\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_back_shortcut.txt"
printf 'C-n\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_jump_forward_shortcut.txt"

TMUX_SIDEBAR_PLUGIN_DIR="$PLUGIN_DIR" bash scripts/features/sidebar/apply-key-overrides.sh

assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'unbind-key -n C-o'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'unbind-key -n C-i'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'bind-key -n C-p if-shell -F'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" "run-shell -b '"
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'request-sidebar-action.sh" jump_back'"'"''
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'send-keys C-p'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'bind-key -n C-n if-shell -F'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'request-sidebar-action.sh" jump_forward'"'"''
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'send-keys C-n'
