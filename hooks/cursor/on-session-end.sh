#!/bin/bash
# Cursor sessionEnd hook: stdin から transcript_path を受け取り、save-knowledge.sh を起動する。
#
# Cursor の hook 設定 (~/.cursor/hooks.json):
#   {
#     "version": 1,
#     "hooks": {
#       "sessionEnd": [{ "command": "/path/to/kakera/hooks/cursor/on-session-end.sh" }]
#     }
#   }
#
# 抽出に使う agent CLI は KAKERA_AGENT_CMD で上書き可能 (default: claude)。
# Cursor 自体には非対話 prompt CLI が無いため、claude / codex のどちらかが必要。
set -u

KAKERA_HOME="${KAKERA_HOME:-$HOME/kakera}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="$KAKERA_HOME/.hook.log"

mkdir -p "$KAKERA_HOME"

INPUT=$(cat)
echo "[$(date)] Cursor sessionEnd fired (KAKERA_HOME=$KAKERA_HOME)" >> "$LOG"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null)
REASON=$(echo "$INPUT" | jq -r '.reason // empty' 2>/dev/null)

# error / aborted は抽出に値しないのでスキップ
if [ "$REASON" = "error" ] || [ "$REASON" = "aborted" ]; then
  echo "[$(date)] SKIP: reason=$REASON" >> "$LOG"
  exit 0
fi

# transcript_path は CURSOR_TRANSCRIPT_PATH env でも来る
[ -z "$TRANSCRIPT_PATH" ] && TRANSCRIPT_PATH="${CURSOR_TRANSCRIPT_PATH:-}"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "[$(date)] SKIP: transcript not found (path='$TRANSCRIPT_PATH')" >> "$LOG"
  exit 0
fi

LINES=$(wc -l < "$TRANSCRIPT_PATH" | tr -d ' ')
if [ "$LINES" -lt 30 ]; then
  echo "[$(date)] SKIP: transcript too short ($LINES lines)" >> "$LOG"
  exit 0
fi

# 抽出 CLI を選択 (KAKERA_AGENT_CMD > claude > codex)
if [ -n "${KAKERA_AGENT_CMD:-}" ]; then
  AGENT_BIN="$KAKERA_AGENT_CMD"
  AGENT_SUBCMD="${KAKERA_AGENT_SUBCMD:--p}"
elif command -v claude >/dev/null 2>&1; then
  AGENT_BIN="$(command -v claude)"
  AGENT_SUBCMD="-p"
elif command -v codex >/dev/null 2>&1; then
  AGENT_BIN="$(command -v codex)"
  AGENT_SUBCMD="exec"
else
  echo "[$(date)] ERROR: no agent CLI (claude/codex) found" >> "$LOG"
  exit 0
fi

nohup "$HOOK_ROOT/save-knowledge.sh" \
  "$AGENT_BIN" "$KAKERA_HOME" "$TRANSCRIPT_PATH" "$SESSION_ID" "$LOG" 600 "$AGENT_SUBCMD" \
  >/dev/null 2>&1 &
disown
echo "[$(date)] Cursor save kicked off via $AGENT_BIN (pid=$!)" >> "$LOG"
exit 0
