#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test 1: No toggle/focus overrides set -> no toggle/focus rebinds
fake_tmux_no_sidebar

TMUX_SIDEBAR_PLUGIN_DIR="$PLUGIN_DIR" bash scripts/features/sidebar/apply-key-overrides.sh

assert_not_contains "$(cat "$TEST_TMUX_DATA_DIR/commands.log")" 'unbind-key t'
assert_not_contains "$(cat "$TEST_TMUX_DATA_DIR/commands.log")" 'unbind-key T'

# Test 2: Custom toggle key -> unbinds t, binds new key
fake_tmux_no_sidebar
printf 'b\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_toggle_key.txt"

TMUX_SIDEBAR_PLUGIN_DIR="$PLUGIN_DIR" bash scripts/features/sidebar/apply-key-overrides.sh

assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'unbind-key t'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'bind-key b run-shell'

# Test 3: Custom focus key -> unbinds T, binds new key
fake_tmux_no_sidebar
printf 'B\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_focus_key.txt"

TMUX_SIDEBAR_PLUGIN_DIR="$PLUGIN_DIR" bash scripts/features/sidebar/apply-key-overrides.sh

assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'unbind-key T'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'bind-key B run-shell'

# Test 4: Override set to default value -> no rebind
fake_tmux_no_sidebar
printf 't\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_toggle_key.txt"
printf 'T\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_focus_key.txt"

TMUX_SIDEBAR_PLUGIN_DIR="$PLUGIN_DIR" bash scripts/features/sidebar/apply-key-overrides.sh

assert_not_contains "$(cat "$TEST_TMUX_DATA_DIR/commands.log")" 'unbind-key'
