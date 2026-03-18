#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

assert_file_contains "sidebar.tmux" 'client-active[198]'
assert_file_contains "sidebar.tmux" 'client-attached[199]'
assert_file_contains "sidebar.tmux" 'client-session-changed[200]'
assert_file_contains "sidebar.tmux" 'client-focus-in[202]'
assert_file_contains "sidebar.tmux" 'after-select-window[203]'
assert_file_contains "sidebar.tmux" 'after-select-pane[204]'
assert_file_contains "sidebar.tmux" 'session-window-changed[205]'
assert_file_contains "sidebar.tmux" 'after-split-window[206]'
assert_file_contains "sidebar.tmux" 'after-new-window[207]'
assert_file_contains "sidebar.tmux" 'after-kill-pane[208]'
assert_file_contains "sidebar.tmux" 'after-resize-pane[209]'
assert_file_contains "sidebar.tmux" 'after-rename-window[210]'
assert_file_contains "sidebar.tmux" 'on-pane-focus.sh'
assert_file_contains "sidebar.tmux" 'ensure-sidebar-pane.sh'
assert_file_contains "sidebar.tmux" 'notify-sidebar.sh'
assert_file_contains "sidebar.tmux" 'handle-pane-exited.sh'
assert_file_contains "sidebar.tmux" 'configure-pane-border-format.sh'
assert_file_contains "sidebar.tmux" 'client-attached[199]" "run-shell -b'
assert_file_contains "sidebar.tmux" 'client-active[198]" "run-shell -b'
# after-new-window must call ensure-sidebar-pane (not notify-sidebar)
assert_not_contains "$(grep 'after-new-window' sidebar.tmux)" 'notify-sidebar'
