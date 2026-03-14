#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

unset TMUX_SIDEBAR_STATE_DIR
unset XDG_STATE_HOME
run_script scripts/lib.sh print_state_dir
assert_eq "$output" "$HOME/.local/state/tmux-sidebar"

export XDG_STATE_HOME="/tmp/xdg-state-test"
run_script scripts/lib.sh print_state_dir
assert_eq "$output" "/tmp/xdg-state-test/tmux-sidebar"
unset XDG_STATE_HOME
