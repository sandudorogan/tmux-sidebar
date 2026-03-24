#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PLUGIN_DST="${PLUGIN_DST:-$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)}"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CODEX_CONFIG="${CODEX_CONFIG:-$HOME/.codex/config.toml}"
OPENCODE_PLUGIN="${OPENCODE_PLUGIN:-$HOME/.config/opencode/plugins/tmux-sidebar.js}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d%H%M%S)}"

mkdir -p "$(dirname "$CLAUDE_SETTINGS")" "$(dirname "$CODEX_CONFIG")" "$(dirname "$OPENCODE_PLUGIN")"

if [ -f "$CLAUDE_SETTINGS" ]; then
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak-tmux-sidebar-$TIMESTAMP"
else
  printf '{}\n' > "$CLAUDE_SETTINGS"
fi

CLAUDE_SETTINGS="$CLAUDE_SETTINGS" PLUGIN_DST="$PLUGIN_DST" python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["CLAUDE_SETTINGS"]).expanduser()
plugin_dir = Path(os.environ["PLUGIN_DST"]).expanduser()
text = path.read_text().strip()
data = json.loads(text) if text else {}
if not isinstance(data, dict):
    data = {}
hooks = data.setdefault("hooks", {})
command = str(plugin_dir / "scripts/features/hooks/hook-claude.sh")

def ensure_event(event_name: str, async_enabled: bool) -> None:
    rules = hooks.setdefault(event_name, [])
    target = None
    for rule in rules:
        if rule.get("matcher", "") == "":
            target = rule
            break
    if target is None:
        target = {"matcher": "", "hooks": []}
        rules.append(target)
    hook_list = target.setdefault("hooks", [])
    for hook in hook_list:
        if hook.get("type") == "command" and hook.get("command") == command:
            hook["timeout"] = 10
            if async_enabled:
                hook["async"] = True
            else:
                hook.pop("async", None)
            return
    entry = {"type": "command", "command": command, "timeout": 10}
    if async_enabled:
        entry["async"] = True
    hook_list.append(entry)

for event_name, async_enabled in [
    ("SessionStart", False),
    ("UserPromptSubmit", True),
    ("Stop", True),
    ("SubagentStop", True),
    ("Notification", True),
    ("PermissionRequest", True),
    ("SessionEnd", True),
    ("SubagentStart", True),
]:
    ensure_event(event_name, async_enabled)

path.write_text(json.dumps(data, indent=2) + "\n")
PY

if [ -f "$CODEX_CONFIG" ]; then
  cp "$CODEX_CONFIG" "$CODEX_CONFIG.bak-tmux-sidebar-$TIMESTAMP"
else
  : > "$CODEX_CONFIG"
fi

CODEX_CONFIG="$CODEX_CONFIG" PLUGIN_DST="$PLUGIN_DST" python3 - <<'PY'
from pathlib import Path
import os
import re

path = Path(os.environ["CODEX_CONFIG"]).expanduser()
plugin_dir = Path(os.environ["PLUGIN_DST"]).expanduser()
text = path.read_text()
line = f'notify = ["bash", "{plugin_dir / "scripts/features/hooks/hook-codex.sh"}"]'
if re.search(r"^notify\s*=\s*\[.*\]$", text, flags=re.M):
    text = re.sub(r"^notify\s*=\s*\[.*\]$", line, text, count=1, flags=re.M)
else:
    text = text.rstrip() + ("\n" if text.rstrip() else "") + line + "\n"
path.write_text(text)
PY

if [ -f "$OPENCODE_PLUGIN" ]; then
  cp "$OPENCODE_PLUGIN" "$OPENCODE_PLUGIN.bak-tmux-sidebar-$TIMESTAMP"
fi

OPENCODE_PLUGIN="$OPENCODE_PLUGIN" PLUGIN_DST="$PLUGIN_DST" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["OPENCODE_PLUGIN"]).expanduser()
plugin_dir = Path(os.environ["PLUGIN_DST"]).expanduser()
hook = plugin_dir / "scripts/features/hooks/hook-opencode.sh"

path.write_text(
    """const hook = {hook_path!r}

export const TmuxSidebarPlugin = async () => {{
  return {{
    event: async ({{ event }}) => {{
      const eventType = String(event?.type ?? "")
      const status = String(
        event?.properties?.status?.type
        ?? event?.status
        ?? event?.state
        ?? ""
      )
      const message = String(
        event?.properties?.status?.message
        ?? event?.properties?.error?.message
        ?? event?.message
        ?? event?.summary
        ?? event?.transcript_summary
        ?? ""
      )

      if (!eventType && !status && !message) {{
        return
      }}

      const payload = JSON.stringify({{
        event: eventType,
        status,
        message,
      }})

      const proc = Bun.spawn(["bash", hook, payload], {{
        env: {{
          ...process.env,
        }},
        stdin: "ignore",
        stdout: "ignore",
        stderr: "ignore",
      }})

      await proc.exited
    }},
  }}
}}
""".format(hook_path=str(hook))
)
PY
