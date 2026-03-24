#!/usr/bin/env bash
set -euo pipefail

plugin_dir="${TMUX_SIDEBAR_PLUGIN_DIR:-$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)}"

toggle_key="$(tmux show-options -gv @tmux_sidebar_toggle_key 2>/dev/null || true)"
focus_key="$(tmux show-options -gv @tmux_sidebar_focus_key 2>/dev/null || true)"
jump_sidebar_condition='#{m/r:^(Sidebar|tmux-sidebar)$,#{pane_title}}'

bind_control_sidebar_action() {
  local action_name="$1"
  local default_key="$2"
  local script_action="$3"
  local option_name="@tmux_sidebar_${action_name}_shortcut"
  local bound_option_name="@tmux_sidebar_bound_${action_name}_shortcut"
  local run_shell_command
  local configured_key
  local previous_key
  local binding_key

  configured_key="$(tmux show-options -gv "$option_name" 2>/dev/null || true)"
  previous_key="$(tmux show-options -gv "$bound_option_name" 2>/dev/null || true)"
  binding_key="${configured_key:-$default_key}"

  if [ -n "$previous_key" ] && [ "$previous_key" != "$binding_key" ]; then
    tmux unbind-key -n "$previous_key" 2>/dev/null || true
  fi
  if [ "$binding_key" != "$default_key" ]; then
    tmux unbind-key -n "$default_key" 2>/dev/null || true
  fi

  if [[ ! "$binding_key" =~ ^C-[A-Za-z]$ ]]; then
    tmux set-option -g -u "$bound_option_name" 2>/dev/null || true
    return
  fi

  printf -v run_shell_command "run-shell -b '\"%s/scripts/features/sidebar/request-sidebar-action.sh\" %s'" \
    "$plugin_dir" "$script_action"
  tmux bind-key -n "$binding_key" if-shell -F "$jump_sidebar_condition" \
    "$run_shell_command" \
    "send-keys $binding_key"
  tmux set-option -g "$bound_option_name" "$binding_key"
}

if [ -n "$toggle_key" ] && [ "$toggle_key" != "t" ]; then
  tmux unbind-key t
  tmux bind-key "$toggle_key" run-shell -b "\"$plugin_dir/scripts/features/sidebar/toggle-sidebar.sh\""
fi

if [ -n "$focus_key" ] && [ "$focus_key" != "T" ]; then
  tmux unbind-key T
  tmux bind-key "$focus_key" run-shell -b "\"$plugin_dir/scripts/features/sidebar/focus-sidebar.sh\""
fi

bind_control_sidebar_action jump_back C-o jump_back
bind_control_sidebar_action jump_forward C-i jump_forward
