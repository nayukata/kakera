#!/bin/bash
# SessionEnd hook: stdin から transcript_path / session_id を受け取り、
# save-knowledge.sh をデタッチで起動する。即 exit 0。
#
# Vault パスは KAKERA_HOME (default ~/kakera) から解決。
# このスクリプトは Claude Code 設定 (~/.claude/settings.json の hooks) から呼ばれる。

set -u

KAKERA_HOME="${KAKERA_HOME:-$HOME/kakera}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$KAKERA_HOME/.hook.log"

mkdir -p "$KAKERA_HOME"

# ログサイズ 1MB 超で最新 100 行のみ残す
if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

INPUT=$(cat)
echo "[$(date)] Hook fired (KAKERA_HOME=$KAKERA_HOME)" >> "$LOG"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "[$(date)] ERROR: transcript not found at '$TRANSCRIPT_PATH'" >> "$LOG"
  exit 0
fi

LINES=$(wc -l < "$TRANSCRIPT_PATH" | tr -d ' ')
if [ "$LINES" -lt 30 ]; then
  echo "[$(date)] SKIP: transcript too short ($LINES lines)" >> "$LOG"
  exit 0
fi

CLAUDE_CMD="$(command -v claude 2>/dev/null)"
if [ -z "$CLAUDE_CMD" ]; then
  echo "[$(date)] ERROR: claude CLI not found in PATH" >> "$LOG"
  exit 0
fi

nohup "$SCRIPT_DIR/save-knowledge.sh" \
  "$CLAUDE_CMD" "$KAKERA_HOME" "$TRANSCRIPT_PATH" "$SESSION_ID" "$LOG" 600 \
  >/dev/null 2>&1 &
disown
echo "[$(date)] Save kicked off (pid=$!)" >> "$LOG"
exit 0
