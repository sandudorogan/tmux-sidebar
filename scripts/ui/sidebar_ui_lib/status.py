from __future__ import annotations

import os
import re
from pathlib import Path

from .core import run_tmux, tmux_option


SEMVER_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
NON_AGENT_COMMANDS = {
    "",
    "ash",
    "bash",
    "fish",
    "htop",
    "ksh",
    "less",
    "nano",
    "nvim",
    "sh",
    "ssh",
    "tail",
    "tmux",
    "top",
    "vi",
    "vim",
    "yazi",
    "zsh",
}
DEFAULT_BADGES: dict[str, str] = {
    "running": "⏳",
    "needs-input": "❓",
    "done": "✅",
    "error": "❌",
}
ASCII_ICONS: dict[str, str] = {
    "claude": "C",
    "codex": "X",
    "opencode": "O",
    "cursor": "U",
    "shell": "$",
    "node": "N",
    "python": "P",
    "git": "G",
    "lazygit": "G",
    "yazi": "Y",
    "ranger": "R",
    "bb": "B",
    "cat": "c",
    "clojure": "L",
    "java": "J",
    "less": ":",
    "vim": "V",
    "ssh": "@",
    "pager": ":",
    "top": "%",
    "tmux": "T",
    "unknown": "?",
}
UNICODE_ICONS: dict[str, str] = {
    "claude": "◎",
    "codex": "⌘",
    "opencode": "◌",
    "cursor": "▣",
    "shell": "›",
    "node": "⬢",
    "python": "¶",
    "git": "⎇",
    "lazygit": "⎇",
    "yazi": "▤",
    "ranger": "▥",
    "bb": "β",
    "cat": "⌂",
    "clojure": "λ",
    "java": "♨",
    "less": "↕",
    "vim": "◇",
    "ssh": "↗",
    "pager": "↕",
    "top": "▦",
    "tmux": "⊞",
    "unknown": "·",
}
NERD_FONT_ICONS: dict[str, str] = {
    "claude": "\U000f0d70",
    "codex": "\U000f0d70",
    "opencode": "\U000f0d70",
    "cursor": "\U000f0d70",
    "shell": "\U000f016c",
    "node": "\ue719",
    "python": "\ue73c",
    "git": "\ue702",
    "lazygit": "\ue8a9",
    "yazi": "\U000f024b",
    "ranger": "\ueb86",
    "bb": "\ue768",
    "cat": "\U000f011b",
    "clojure": "\ue768",
    "java": "\ue738",
    "less": "\ue758",
    "vim": "\ue7c5",
    "ssh": "\ue8b1",
    "pager": "\ueb2f",
    "top": "\U000f1513",
    "tmux": "\uebc8",
    "unknown": "\ueb32",
}
ICON_THEMES: dict[str, dict[str, str]] = {
    "ascii": ASCII_ICONS,
    "nerdfont": NERD_FONT_ICONS,
    "unicode": UNICODE_ICONS,
}
APP_ALIASES: dict[str, str] = {
    "ash": "shell",
    "bash": "shell",
    "dash": "shell",
    "elvish": "shell",
    "fish": "shell",
    "ksh": "shell",
    "nu": "shell",
    "sh": "shell",
    "xonsh": "shell",
    "zsh": "shell",
    "node": "node",
    "nodejs": "node",
    "python": "python",
    "python2": "python",
    "python3": "python",
    "git": "git",
    "lazygit": "lazygit",
    "yazi": "yazi",
    "ranger": "ranger",
    "bb": "bb",
    "babashka": "bb",
    "cat": "cat",
    "clj": "clojure",
    "clojure": "clojure",
    "java": "java",
    "less": "less",
    "vi": "vim",
    "vim": "vim",
    "nvim": "vim",
    "view": "vim",
    "ssh": "ssh",
    "mosh": "ssh",
    "mosh-client": "ssh",
    "more": "pager",
    "most": "pager",
    "tail": "pager",
    "atop": "top",
    "bpytop": "top",
    "btop": "top",
    "htop": "top",
    "top": "top",
    "tmux": "tmux",
}
BADGE_OPTIONS: dict[str, str] = {
    "running": "@tmux_sidebar_badge_running",
    "needs-input": "@tmux_sidebar_badge_needs_input",
    "done": "@tmux_sidebar_badge_done",
    "error": "@tmux_sidebar_badge_error",
}
ICON_THEME_OPTION = "@tmux_sidebar_icon_theme"
GHOSTTY_CONFIG_ENV = "TMUX_SIDEBAR_GHOSTTY_CONFIG"

_badge_cache: dict[str, str] | None = None
_icon_cache: dict[str, str] | None = None


def configured_badges() -> dict[str, str]:
    global _badge_cache
    if _badge_cache is not None:
        return _badge_cache
    badges = dict(DEFAULT_BADGES)
    for status, option in BADGE_OPTIONS.items():
        custom = tmux_option(option)
        if custom:
            badges[status] = custom
    _badge_cache = badges
    return badges


def badge_for_status(status: str) -> str:
    return configured_badges().get(status, "")


def ghostty_config_paths() -> tuple[Path, ...]:
    override = os.environ.get(GHOSTTY_CONFIG_ENV)
    if override is not None:
        return (Path(override),)
    xdg_config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    return (
        xdg_config_home / "ghostty" / "config",
        Path.home() / ".config" / "ghostty" / "config",
    )


def ghostty_uses_nerd_font() -> bool:
    for config_path in ghostty_config_paths():
        try:
            raw = config_path.read_text()
        except OSError:
            continue
        for line in raw.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if "=" not in stripped:
                continue
            key, value = (part.strip().lower() for part in stripped.split("=", 1))
            if key != "font-family":
                continue
            if "nerd font" in value or "symbols nerd font" in value or value.endswith(" nfm"):
                return True
    return False


def configured_icon_theme() -> str:
    theme_name = tmux_option(ICON_THEME_OPTION).strip().lower()
    if theme_name and theme_name != "auto":
        return theme_name
    if ghostty_uses_nerd_font():
        return "nerdfont"
    return "ascii"


def configured_icons() -> dict[str, str]:
    global _icon_cache
    if _icon_cache is not None:
        return _icon_cache
    theme_name = configured_icon_theme()
    icons = dict(ICON_THEMES.get(theme_name, ASCII_ICONS))
    for app in icons:
        custom = tmux_option(f"@tmux_sidebar_icon_{app}")
        if custom:
            icons[app] = custom
    _icon_cache = icons
    return icons


def icon_for_app(app: str) -> str:
    return configured_icons().get(app, "")


def normalize_token(value: str) -> str:
    token = value.strip().lower()
    if "/" in token:
        token = token.rsplit("/", 1)[-1]
    return token


def looks_like_codex(value: str) -> bool:
    return normalize_token(value).startswith("codex")


def looks_like_opencode(value: str) -> bool:
    return normalize_token(value).startswith("opencode")


def looks_like_cursor(value: str) -> bool:
    return normalize_token(value).startswith("cursor")


def looks_like_claude(value: str) -> bool:
    token = normalize_token(value)
    if token == "claude" or token.startswith("claude-") or token.startswith("claude_"):
        return True
    return bool(re.search(r"\bclaude\b", value, re.IGNORECASE))


def looks_like_semver(value: str) -> bool:
    return bool(SEMVER_PATTERN.match(normalize_token(value)))


def should_preserve_live_label(command: str, title: str) -> bool:
    command_token = normalize_token(command)
    title_token = normalize_token(title)
    return command_token in NON_AGENT_COMMANDS or title_token in NON_AGENT_COMMANDS


def state_agent_app(command: str, title: str, state: dict | None) -> str:
    app = str((state or {}).get("app", "")).strip().lower()
    status = str((state or {}).get("status", "")).strip().lower()
    if app not in ("claude", "codex", "opencode", "cursor"):
        return ""
    if app == "cursor":
        if status and status != "idle":
            return "cursor"
        return ""
    if should_preserve_live_label(command, title):
        return ""
    if app == "claude" and (looks_like_semver(command) or looks_like_semver(title)):
        return "claude"
    if status and status != "idle":
        return app
    return ""


def claude_title_status(title: str) -> str:
    match = re.search(r":\s*([a-z_-]+)\s*$", title.strip().lower())
    if match:
        suffix = match.group(1)
        return {
            "done": "done",
            "error": "error",
            "needs-input": "needs-input",
            "running": "running",
        }.get(suffix, "")
    if re.match(r"^[\u2800-\u28FF]", title.strip()):
        return "running"
    return ""


def live_agent_app(command: str, title: str, state: dict | None) -> str:
    if looks_like_codex(command) or looks_like_codex(title):
        return "codex"
    if looks_like_opencode(command) or looks_like_opencode(title):
        return "opencode"
    if looks_like_cursor(command) or looks_like_cursor(title):
        return "cursor"
    if looks_like_claude(command) or looks_like_claude(title):
        return "claude"
    if looks_like_semver(command) and not should_preserve_live_label(command, title):
        return "claude"
    return state_agent_app(command, title, state)


def canonical_pane_app(command: str, title: str, state: dict | None) -> str:
    live_app = live_agent_app(command, title, state)
    if live_app:
        return live_app
    command_token = normalize_token(command)
    if command_token in APP_ALIASES:
        return APP_ALIASES[command_token]
    title_token = normalize_token(title)
    if title_token in APP_ALIASES:
        return APP_ALIASES[title_token]
    if command_token.startswith("python"):
        return "python"
    if command_token:
        return "unknown"
    return ""


def codex_terminal_status(pane_id: str) -> str:
    if not pane_id:
        return ""
    try:
        capture = run_tmux("capture-pane", "-pt", pane_id)
    except Exception:
        return ""
    if re.search(r"^\s*[•·]\s+Working \([^)]*esc to interrupt\)\s*$", capture, re.MULTILINE):
        return "running"
    return ""


def effective_pane_status(pane_id: str, command: str, title: str, state: dict | None) -> str:
    live_app = live_agent_app(command, title, state)
    if not live_app:
        return ""

    status = str((state or {}).get("status", "")).strip().lower()
    if live_app == "codex":
        if status in ("running", "needs-input", "error", "done"):
            return status
        terminal_status = codex_terminal_status(pane_id)
        if terminal_status:
            return terminal_status
        return ""

    if status == "idle":
        return ""
    title_status = claude_title_status(title)
    if title_status:
        return title_status
    if status in ("running", "needs-input", "error", "done"):
        return status
    return ""


def pane_display_label(command: str, title: str, state: dict | None) -> str:
    live_app = live_agent_app(command, title, state)
    if live_app:
        return live_app
    return command


def pane_icon(command: str, title: str, state: dict | None) -> str:
    return icon_for_app(canonical_pane_app(command, title, state))


def auto_window_name(window_name: str, panes: list[dict]) -> bool:
    if (
        looks_like_semver(window_name)
        or looks_like_codex(window_name)
        or looks_like_opencode(window_name)
        or looks_like_cursor(window_name)
        or looks_like_claude(window_name)
    ):
        return True
    active_pane = next((pane for pane in panes if pane["active"]), panes[0] if panes else None)
    if active_pane is None:
        return False
    return normalize_token(window_name) == normalize_token(active_pane["label"])


def window_display_name(window_name: str, panes: list[dict], pane_states: dict[str, dict]) -> str:
    if not auto_window_name(window_name, panes):
        return window_name

    for pane in sorted(panes, key=lambda p: not p["active"]):
        pane_state = pane_states.get(pane["id"], {})
        label = pane_display_label(pane["label"], pane["title"], pane_state)
        if label != pane["label"]:
            return label

    return window_name
