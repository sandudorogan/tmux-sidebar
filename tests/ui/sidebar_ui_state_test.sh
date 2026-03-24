#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/testlib.sh"

export TMUX_SIDEBAR_STATE_DIR="$TEST_TMP/state"
mkdir -p "$TMUX_SIDEBAR_STATE_DIR"

fake_tmux_set_tree <<'EOF'
work|@1|editor|%1|nvim|shell|0
work|@1|editor|%2|claude|claude|1
work|@1|editor|%99|python3|Sidebar|0
ops|@3|logs|%9|tail|tail|0
solo|@5|sidebar-only|%77|python3|Sidebar|0
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

case "$output" in
  *'invalid option:'* ) fail "sidebar UI should not leak tmux stderr for missing options" ;;
esac

fake_tmux_register_main_pane "%9"

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" '├─ work'
assert_contains "$output" '│     └─ claude'
assert_contains "$output" '▶       └─ tail'
case "$output" in
  *'%99 Sidebar'* ) fail "sidebar pane should be hidden when window has other panes" ;;
esac
case "$output" in
  *'└─ solo'* ) fail "sidebar-only sessions should be hidden from the mirrored tree" ;;
esac

fake_tmux_set_tree <<'EOF'
work|@1|editor|%1|nvim|shell|0
work|@1|editor|%99|python3|tmux-sidebar|0
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

case "$output" in
  *'%99 tmux-sidebar'* ) fail "legacy sidebar pane titles should still be hidden when window has other panes" ;;
esac

fake_tmux_set_tree <<'EOF'
work|@1|editor|%3|codex-aarch64-apple-darwin|codex-aarch64-apple-darwin|1
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex'
assert_not_contains "$output" '⏳'
case "$output" in
  *'codex-aarch64-apple-darwin'* ) fail "codex target-triple binary names should normalize to codex" ;;
esac

fake_tmux_set_tree <<'EOF'
work|@1|codex-aarch64-apple-darwin|%33|codex-aarch64-apple-darwin|codex --full-auto|1
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

window_line="$(printf '%s\n' "$output" | grep -E '^\s+[├└]─' | sed -n '2p')"
assert_contains "$window_line" 'codex'
assert_not_contains "$window_line" 'codex-aarch64-apple-darwin'

fake_tmux_set_tree <<'EOF'
work|@1|env|%34|env|codex --full-auto|1
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

window_line="$(printf '%s\n' "$output" | grep -E '^\s+[├└]─' | sed -n '2p')"
assert_contains "$window_line" 'codex'
assert_not_contains "$window_line" 'env'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%4|2.1.76|2.1.76|1
work|@1|editor|%5|2.1.76|2.1.76|0
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%4.json" <<'EOF'
{"pane_id":"%4","app":"claude","status":"running","updated_at":100}
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR/pane-%5.json"

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'claude'
assert_not_contains "$output" '2.1.76'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%6|zsh|zsh|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%6.json" <<'EOF'
{"pane_id":"%6","app":"claude","status":"idle","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'zsh'
case "$output" in
  *'│     └─ claude'* ) fail "stale claude state should not relabel obvious shell panes" ;;
esac

fake_tmux_set_tree <<'EOF'
work|@1|editor|%7|zsh|sandu.dorogan@host:~/workdir/tmux-sidebar|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%7.json" <<'EOF'
{"pane_id":"%7","app":"codex","status":"running","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'zsh'
case "$output" in
  *'⏳'* ) fail "stale codex state should not show a running badge on obvious shell panes" ;;
esac

fake_tmux_set_tree <<'EOF'
work|@1|editor|%10|python3|assistant runner|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%10.json" <<'EOF'
{"pane_id":"%10","app":"claude","status":"running","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'claude ⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%11|node|repo worker|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%11.json" <<'EOF'
{"pane_id":"%11","app":"codex","status":"running","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex ⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%111|node|repo worker|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%111.json" <<'EOF'
{"pane_id":"%111","app":"opencode","status":"running","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'opencode ⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%8|codex-aarch64-apple-darwin|● project: done|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%8.json" <<'EOF'
{"pane_id":"%8","app":"codex","status":"running","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex ⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%9|codex-aarch64-apple-darwin|codex --full-auto|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%9.json" <<'EOF'
{"pane_id":"%9","app":"codex","status":"done","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex ✅'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%12|codex-aarch64-apple-darwin|codex --full-auto|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%12.json" <<'EOF'
{"pane_id":"%12","app":"codex","status":"idle","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex'
assert_not_contains "$output" '⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%13|codex-aarch64-apple-darwin|● project: done|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%13.json" <<'EOF'
{"pane_id":"%13","app":"codex","status":"idle","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex'
assert_not_contains "$output" '✅'
assert_not_contains "$output" '⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%14|codex-aarch64-apple-darwin|● project: working on task|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%14.json" <<'EOF'
{"pane_id":"%14","app":"codex","status":"idle","pane_title":"● project: done","updated_at":100}
EOF
fake_tmux_set_capture "%14" <<'EOF'
• Working (15s • esc to interrupt)
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex'
assert_contains "$output" '⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%15|codex-aarch64-apple-darwin|● project: working on task|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%15.json" <<'EOF'
{"pane_id":"%15","app":"codex","status":"idle","pane_title":"● project: working on task","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'codex'
assert_not_contains "$output" '⏳'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%2|superlongpanecommand|superlongpanecommand|1
EOF
printf '14\n' > "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_width.txt"

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" '…'
case "$output" in
  *'superlongpanecommand'* ) fail "sidebar UI should truncate long rows for narrow widths" ;;
esac

rm -f "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_width.txt"
export TMUX_SIDEBAR_WIDTH=''
python_width="$(
python3 - <<'PY'
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("sidebar_ui", Path("scripts/ui/sidebar-ui.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.configured_sidebar_width())
PY
)"

assert_eq "$python_width" "25"

rm -f "$TEST_TMUX_DATA_DIR/option__tmux_sidebar_width.txt"
export TMUX_SIDEBAR_WIDTH=''

fake_tmux_set_tree <<'EOF'
work|@1|2.1.76|%20|2.1.76|2.1.76|1
work|@1|2.1.76|%21|lazygit|lazygit|0
work|@1|2.1.76|%22|2.1.76|2.1.76|0
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%20.json" <<'EOF'
{"pane_id":"%20","app":"claude","status":"needs-input","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

window_line="$(printf '%s\n' "$output" | grep -E '^\s+[├└]─' | sed -n '2p')"
assert_contains "$window_line" 'claude'
assert_not_contains "$window_line" '2.1.76'

fake_tmux_set_tree <<'EOF'
work|@1|2.1.76|%23|2.1.76|2.1.76|1
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'claude'
assert_not_contains "$output" '2.1.76'

fake_tmux_set_tree <<'EOF'
work|@1|myproject|%24|2.1.76|2.1.76|1
EOF
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%24.json" <<'EOF'
{"pane_id":"%24","app":"claude","status":"running","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" '└─ myproject'
case "$output" in
  *'├─ claude'* | *'└─ claude'*'├─'* ) ;;
esac

fake_tmux_set_tree <<'EOF'
work|@1|2.1.76|%25|2.1.76|2.1.76|1
work|@1|2.1.76|%26|lazygit|lazygit|0
work|@1|2.1.76|%27|2.1.76|2.1.76|0
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json
cat > "$TMUX_SIDEBAR_STATE_DIR/pane-%27.json" <<'EOF'
{"pane_id":"%27","app":"claude","status":"running","updated_at":100}
EOF

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

window_line="$(printf '%s\n' "$output" | grep -E '^\s+[├└]─' | sed -n '2p')"
assert_contains "$window_line" 'claude'
assert_not_contains "$window_line" '2.1.76'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%30|2.1.76|⠂ Claude Code|1
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'claude ⏳'
assert_not_contains "$output" '2.1.76'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%31|2.1.76|● sandu.dorogan: done|1
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'claude ✅'
assert_not_contains "$output" '2.1.76'

fake_tmux_set_tree <<'EOF'
work|@1|editor|%32|2.1.76|● project: error|1
EOF
rm -f "$TMUX_SIDEBAR_STATE_DIR"/pane-*.json

output="$(python3 scripts/ui/sidebar-ui.py --dump-render 2>&1)"

assert_contains "$output" 'claude ❌'
