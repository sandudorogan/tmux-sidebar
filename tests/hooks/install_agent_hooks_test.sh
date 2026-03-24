#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/../testlib.sh"

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
HOME_DIR="$TEST_TMP/home"
PLUGIN_DST="$HOME_DIR/.config/tmux/plugins/tmux-sidebar"
CLAUDE_SETTINGS="$HOME_DIR/.claude/settings.json"
CODEX_CONFIG="$HOME_DIR/.codex/config.toml"
OPENCODE_PLUGIN="$HOME_DIR/.config/opencode/plugins/tmux-sidebar.js"

mkdir -p "$PLUGIN_DST" "$(dirname "$CLAUDE_SETTINGS")" "$(dirname "$CODEX_CONFIG")"
cp -R "$REPO_ROOT"/. "$PLUGIN_DST"/

cat > "$CLAUDE_SETTINGS" <<'EOF'
{}
EOF

cat > "$CODEX_CONFIG" <<'EOF'
model = "gpt-5"
EOF

HOME="$HOME_DIR" \
PLUGIN_DST="$PLUGIN_DST" \
TIMESTAMP="20260320000000" \
bash "$REPO_ROOT/scripts/features/hooks/install-agent-hooks.sh"

assert_file_contains "$CLAUDE_SETTINGS" 'scripts/features/hooks/hook-claude.sh'
assert_file_contains "$CLAUDE_SETTINGS" '"SubagentStop"'
assert_file_contains "$CODEX_CONFIG" 'scripts/features/hooks/hook-codex.sh'
assert_file_contains "$OPENCODE_PLUGIN" 'scripts/features/hooks/hook-opencode.sh'
assert_file_contains "$OPENCODE_PLUGIN" 'properties?.status?.type'
assert_file_contains "$OPENCODE_PLUGIN" 'JSON.stringify'
