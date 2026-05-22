#!/bin/bash
# SessionEnd hook: stdin から transcript_path / session_id を受け取り、
# save-knowledge.sh をデタッチで起動する。即 exit 0。
#
# Vault パスの解決順序:
#   1. 環境変数 KAKERA_HOME (対話 shell で export 済の場合のみ伝播。Claude Code が
#      hook を spawn する非対話 subprocess には .zshrc が読まれず空になるため、
#      これだけに依存すると Vault パスが意図しない default にフォールバックする)
#   2. 既知候補 ($HOME/Obsidian/kakera, $HOME/kakera, $HOME/.kakera) に
#      .kakera-config.toml があれば、その vault.path を読む
#   3. それでも見つからなければ $HOME/kakera にフォールバック
# このスクリプトは Claude Code 設定 (~/.claude/settings.json の hooks) から呼ばれる。

set -u

resolve_kakera_home() {
  if [ -n "${KAKERA_HOME:-}" ]; then
    printf '%s' "$KAKERA_HOME"
    return
  fi
  local candidate cfg p
  for candidate in "$HOME/Obsidian/kakera" "$HOME/kakera" "$HOME/.kakera"; do
    cfg="$candidate/.kakera-config.toml"
    if [ -f "$cfg" ]; then
      p=$(grep -E '^[[:space:]]*path[[:space:]]*=' "$cfg" | head -1 \
            | sed -E 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')
      if [ -n "$p" ] && [ -d "$p" ]; then
        printf '%s' "$p"
        return
      fi
      printf '%s' "$candidate"
      return
    fi
  done
  printf '%s' "$HOME/kakera"
}

KAKERA_HOME="$(resolve_kakera_home)"
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
