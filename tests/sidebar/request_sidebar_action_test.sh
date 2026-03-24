#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

unset TMUX_PANE
export TMUX_SIDEBAR_STATE_DIR="$TEST_TMP/state"
mkdir -p "$TMUX_SIDEBAR_STATE_DIR"

fake_tmux_no_sidebar
fake_tmux_register_pane "%99" "work" "@1" "editor" "Sidebar"
printf '%%99\n' > "$TEST_TMUX_DATA_DIR/current_pane.txt"

bash scripts/features/sidebar/request-sidebar-action.sh jump_back
bash scripts/features/sidebar/request-sidebar-action.sh jump_forward

assert_file_contains "$TMUX_SIDEBAR_STATE_DIR/sidebar-%99.actions" 'jump_back'
assert_file_contains "$TMUX_SIDEBAR_STATE_DIR/sidebar-%99.actions" 'jump_forward'

fake_tmux_no_sidebar
fake_tmux_register_pane "%1" "work" "@1" "editor" "zsh"
printf '%%1\n' > "$TEST_TMUX_DATA_DIR/current_pane.txt"
rm -f "$TMUX_SIDEBAR_STATE_DIR/sidebar-%1.actions"

bash scripts/features/sidebar/request-sidebar-action.sh jump_back

[ ! -e "$TMUX_SIDEBAR_STATE_DIR/sidebar-%1.actions" ] || fail "expected no action file for non-sidebar pane"
