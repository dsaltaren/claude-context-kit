#!/bin/bash
# Installs the hooks, statusline and skill into ~/.claude (or $CLAUDE_CONFIG_DIR).
#
# Copies files and prints the settings.json snippet to paste. It does NOT edit
# settings.json for you: that file holds your own configuration and merging it
# blindly is a good way to lose it.

set -euo pipefail

DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$DEST" ]; then
  echo "error: $DEST does not exist. Is Claude Code installed?" >&2
  exit 1
fi

mkdir -p "$DEST/hooks" "$DEST/skills/handoff"

for f in "$SRC"/hooks/*.sh; do
  cp "$f" "$DEST/hooks/" && chmod +x "$DEST/hooks/$(basename "$f")"
  echo "installed hooks/$(basename "$f")"
done

cp "$SRC/statusline/statusline-context.sh" "$DEST/"
chmod +x "$DEST/statusline-context.sh"
echo "installed statusline-context.sh"

cp "$SRC/skills/handoff/SKILL.md" "$DEST/skills/handoff/"
echo "installed skills/handoff/SKILL.md"

cat <<'SNIPPET'

Now merge this into your settings.json ("hooks" and "statusLine" keys).
Replace ~ with your absolute home path: Claude Code does not expand it here.

  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-context.sh",
    "padding": 0
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "mcp__paper__get_screenshot",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/paper-shot-guard.sh" }] }
    ],
    "PostToolUse": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/session-size-warn.sh" }] },
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/context-weight.sh" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/compact-reset.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/stop-compact-nudge.sh" }] }
    ]
  }

If you already have hooks configured, add these entries to the existing arrays
rather than replacing them.
SNIPPET
