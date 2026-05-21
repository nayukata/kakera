#!/bin/bash
# Codex Stop hook: ターン終了ごとに発火するため debounce 必須。
# 直前実行から DEBOUNCE_SECONDS 以内ならスキップ。
#
# Codex の hook 設定 (~/.codex/config.toml):
#   [[hooks.Stop]]
#   command = "/path/to/kakera/hooks/codex/on-stop.sh"
#
# 仕様の制約:
#   - Codex には SessionEnd 相当が無いため Stop で代替
#   - Stop は毎ターン発火 → flag-file で頻度制御
#   - transcript は ~/.codex/sessions/<id>/ 配下に置かれる想定 (Codex 仕様変更時は要更新)
set -u

KAKERA_HOME="${KAKERA_HOME:-$HOME/kakera}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="$KAKERA_HOME/.hook.log"
DEBOUNCE_SECONDS="${KAKERA_CODEX_DEBOUNCE:-300}"
FLAG="$KAKERA_HOME/.codex-last-save"

mkdir -p "$KAKERA_HOME"

if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

INPUT=$(cat)
echo "[$(date)] Codex Stop fired (KAKERA_HOME=$KAKERA_HOME)" >> "$LOG"

# Debounce: 直前実行から DEBOUNCE_SECONDS 以内ならスキップ
if [ -f "$FLAG" ]; then
  LAST=$(stat -f%m "$FLAG" 2>/dev/null || stat -c%Y "$FLAG" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  DIFF=$((NOW - LAST))
  if [ "$DIFF" -lt "$DEBOUNCE_SECONDS" ]; then
    echo "[$(date)] SKIP: debounced (${DIFF}s < ${DEBOUNCE_SECONDS}s)" >> "$LOG"
    exit 0
  fi
fi

# session_id / transcript_path を抽出 (Codex payload 形式に依存)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // .transcriptPath // empty' 2>/dev/null)

# transcript_path が無い場合は ~/.codex/sessions/<id>/transcript.jsonl を試す
if [ -z "$TRANSCRIPT_PATH" ] && [ -n "$SESSION_ID" ]; then
  for candidate in \
    "$HOME/.codex/sessions/$SESSION_ID/transcript.jsonl" \
    "$HOME/.codex/sessions/$SESSION_ID/messages.jsonl"; do
    if [ -f "$candidate" ]; then
      TRANSCRIPT_PATH="$candidate"
      break
    fi
  done
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "[$(date)] SKIP: transcript not found (session=$SESSION_ID)" >> "$LOG"
  exit 0
fi

LINES=$(wc -l < "$TRANSCRIPT_PATH" | tr -d ' ')
if [ "$LINES" -lt 30 ]; then
  echo "[$(date)] SKIP: transcript too short ($LINES lines)" >> "$LOG"
  exit 0
fi

CODEX_CMD="$(command -v codex 2>/dev/null)"
if [ -z "$CODEX_CMD" ]; then
  echo "[$(date)] ERROR: codex CLI not found in PATH" >> "$LOG"
  exit 0
fi

touch "$FLAG"
nohup "$HOOK_ROOT/save-knowledge.sh" \
  "$CODEX_CMD" "$KAKERA_HOME" "$TRANSCRIPT_PATH" "$SESSION_ID" "$LOG" 600 "exec" \
  >/dev/null 2>&1 &
disown
echo "[$(date)] Codex save kicked off (pid=$!)" >> "$LOG"
exit 0
