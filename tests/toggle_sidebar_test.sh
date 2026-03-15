#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

fake_tmux_no_sidebar
fake_tmux_register_pane "%1" "work" "@1" "editor" "nvim"

bash scripts/toggle-sidebar.sh
assert_eq "$(fake_tmux_sidebar_count)" "1"
assert_eq "$(fake_tmux_current_pane)" "%99"
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'split-window -t %1 -h -b -d -f -l 25'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'select-pane -t %99 -T Sidebar'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -p -t %99 allow-set-title off'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -g @tmux_sidebar_main_pane %1'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -g @tmux_sidebar_enabled 1'
assert_file_not_contains "$TEST_TMUX_DATA_DIR/commands.log" 'sleep 1'
assert_file_not_contains "$TEST_TMUX_DATA_DIR/commands.log" 'while true'

bash scripts/toggle-sidebar.sh
assert_eq "$(fake_tmux_sidebar_count)" "0"
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -g @tmux_sidebar_enabled 0'

fake_tmux_no_sidebar
fake_tmux_register_pane "%1" "work" "@1" "editor" "nvim"
printf '1\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_enabled.txt"
printf '%%90\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_pane_w1.txt"

bash scripts/toggle-sidebar.sh

assert_eq "$(fake_tmux_sidebar_count)" "1"
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -g @tmux_sidebar_enabled 1'
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -g -u @tmux_sidebar_pane_w1'

fake_tmux_no_sidebar
fake_tmux_register_pane "%1" "work" "@1" "editor" "nvim"
printf '0\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_focus_on_open.txt"

bash scripts/toggle-sidebar.sh

assert_eq "$(fake_tmux_sidebar_count)" "1"
assert_eq "$(fake_tmux_current_pane)" "%1"

fake_tmux_no_sidebar
fake_tmux_register_pane "%1" "work" "@1" "editor" "nvim"
fake_tmux_register_pane "%2" "logs" "@2" "server" "bash" "bash"

bash scripts/toggle-sidebar.sh
assert_eq "$(fake_tmux_sidebar_count)" "1"
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -g @tmux_sidebar_enabled 1'

printf '%%2\n' > "$TEST_TMUX_DATA_DIR/current_pane.txt"
bash scripts/ensure-sidebar-pane.sh
assert_eq "$(fake_tmux_sidebar_count)" "2"
assert_file_contains "$TEST_TMUX_DATA_DIR/toggle_panes.txt" '%98|Sidebar|@2'

bash scripts/toggle-sidebar.sh
assert_eq "$(fake_tmux_sidebar_count)" "0"
assert_file_contains "$TEST_TMUX_DATA_DIR/commands.log" 'set-option -g @tmux_sidebar_enabled 0'

assert_file_contains "sidebar.tmux" 'bind-key t run-shell'
assert_file_contains "sidebar.tmux" 'ensure-sidebar-pane.sh'
assert_file_contains "sidebar.tmux" '#{d:current_file}/scripts/toggle-sidebar.sh'
assert_file_contains "sidebar.tmux" 'on-pane-focus.sh'
assert_file_contains "sidebar.tmux" 'bind-key T run-shell'
assert_file_contains "sidebar.tmux" '#{d:current_file}/scripts/focus-sidebar.sh'
assert_file_contains "sidebar.tmux" 'apply-key-overrides.sh'
