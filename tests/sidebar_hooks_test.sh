#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

assert_file_contains "sidebar.tmux" 'client-active[198]'
assert_file_contains "sidebar.tmux" 'client-attached[199]'
assert_file_contains "sidebar.tmux" 'client-session-changed[200]'
assert_file_contains "sidebar.tmux" 'window-pane-changed[201]'
assert_file_contains "sidebar.tmux" 'client-focus-in[202]'
assert_file_contains "sidebar.tmux" 'after-select-window[203]'
assert_file_contains "sidebar.tmux" 'after-select-pane[204]'
assert_file_contains "sidebar.tmux" 'session-window-changed[205]'
assert_file_contains "sidebar.tmux" 'after-split-window[206]'
assert_file_contains "sidebar.tmux" 'after-new-window[207]'
assert_file_contains "sidebar.tmux" 'pane-exited[208]'
assert_file_contains "sidebar.tmux" 'window-layout-changed[209]'
assert_file_contains "sidebar.tmux" 'window-renamed[210]'
assert_file_contains "sidebar.tmux" 'on-pane-focus.sh'
assert_file_contains "sidebar.tmux" 'ensure-sidebar-pane.sh'
assert_file_contains "sidebar.tmux" 'notify-sidebar.sh'
assert_file_contains "sidebar.tmux" 'handle-pane-exited.sh'
assert_file_contains "sidebar.tmux" 'configure-pane-border-format.sh'
assert_file_contains "sidebar.tmux" 'client-attached[199] "run-shell -b'
assert_file_contains "sidebar.tmux" 'client-active[198] "run-shell -b'
