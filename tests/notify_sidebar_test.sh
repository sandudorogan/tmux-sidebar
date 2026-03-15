#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

fake_tmux_no_sidebar

bash scripts/notify-sidebar.sh

assert_file_not_contains "$TEST_TMUX_DATA_DIR/commands.log" 'split-window'

fake_tmux_no_sidebar
printf '1\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_enabled.txt"

bash scripts/notify-sidebar.sh

assert_eq "$?" "0"
