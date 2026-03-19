#!/usr/bin/env bash
set -euo pipefail
export PS4='+${LINENO}: '
set -x

. "$(dirname "$0")/real_tmux_testlib.sh"

real_tmux_start_server
real_tmux_source_plugin

real_tmux split-window -t work:editor -h -d
real_tmux new-session -d -s ops -n logs
real_tmux split-window -t ops:logs -v -d
real_tmux set-option -g @tmux_sidebar_enabled 1
real_tmux set-option -g @tmux_sidebar_focus_on_open 0

main_window_id="$(real_tmux display-message -p -t work:editor '#{window_id}')"
main_pane_id="$(real_tmux display-message -p -t work:editor '#{pane_id}')"
real_tmux set-option -g @tmux_sidebar_main_pane "$main_pane_id"
printf -v ensure_main_sidebar_cmd 'TMUX_SIDEBAR_TRACE=1 %q %q %q' \
  "$REPO_ROOT/scripts/features/sidebar/ensure-sidebar-pane.sh" "$main_pane_id" "$main_window_id"
real_tmux run-shell -b "$ensure_main_sidebar_cmd"

sidebar_pane_id="$(real_tmux_wait_for_sidebar_pane "$main_window_id")"
capture="$(real_tmux_wait_for_capture "$sidebar_pane_id" 'work')"

assert_contains "$capture" 'work'
assert_contains "$capture" 'editor'
assert_contains "$capture" 'ops'
assert_contains "$capture" 'logs'

rendered="$(real_tmux_run_shell_capture "$REPO_ROOT/scripts/features/sidebar/render-sidebar.sh")"
assert_contains "$rendered" 'work'
assert_contains "$rendered" 'ops'

selected_title="$(real_tmux display-message -p -t "$sidebar_pane_id" '#{pane_title}')"
assert_eq "$selected_title" 'Sidebar'

build_window_id="$(real_tmux new-window -P -F '#{window_id}' -t work -n build)"
build_main_pane_id="$(real_tmux list-panes -t "$build_window_id" -F '#{pane_id}' | sed -n '1p')"
printf -v ensure_build_sidebar_cmd 'TMUX_SIDEBAR_TRACE=1 %q %q %q' \
  "$REPO_ROOT/scripts/features/sidebar/ensure-sidebar-pane.sh" "$build_main_pane_id" "$build_window_id"
real_tmux run-shell -b "$ensure_build_sidebar_cmd"
build_sidebar_pane_id="$(real_tmux_wait_for_sidebar_pane "$build_window_id")"
build_capture="$(real_tmux_wait_for_capture "$build_sidebar_pane_id" 'build')"

assert_contains "$build_capture" 'work'
assert_contains "$build_capture" 'build'
assert_contains "$build_capture" 'ops'
