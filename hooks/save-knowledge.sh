#!/bin/bash
# 知見抽出の実処理。on-session-end.sh から nohup で呼ばれる。
# 引数: claude_cmd kakera_home transcript_path session_id log_path [timeout_seconds]
set -u

CLAUDE_CMD="$1"
KAKERA_HOME="$2"
TRANSCRIPT_PATH="$3"
SESSION_ID="$4"
LOG="$5"
TIMEOUT="${6:-600}"

export KAKERA_HOME

# transcript は tool I/O 等のノイズ込みで肥大化しやすく、生のまま渡すと "Prompt is too long" になる。
# user / assistant の text のみ抽出し、800KB を超える場合は末尾優先で切り詰める。
MAX_BYTES=819200
EXTRACTED=$(jq -r '
  select(.type=="user" or .type=="assistant") |
  "[" + .type + "] " + (
    if (.message.content | type) == "string" then .message.content
    else (.message.content | map(select(.type=="text") | .text) | join("\n"))
    end
  ) | select(length > 5)
' "$TRANSCRIPT_PATH" 2>/dev/null)

BYTES=$(printf '%s' "$EXTRACTED" | wc -c | tr -d ' ')
if [ "$BYTES" -gt "$MAX_BYTES" ]; then
  EXTRACTED=$(printf '%s' "$EXTRACTED" | tail -c "$MAX_BYTES")
  TRUNCATED=" (truncated to last ${MAX_BYTES}B from original ${BYTES}B)"
else
  TRUNCATED=""
fi
echo "[$(date)] Extracted transcript text: ${BYTES}B${TRUNCATED}" >> "$LOG"

# CLAUDE.md (kakera section) のルールに従って抽出するよう促す。
# 具体的なプロトコル (Surprise 判定、サブ hub 振り分け等) はインストール時に
# ~/.claude/CLAUDE.md へ追記された kakera セクションを Claude が読む。
PROMPT="あなたは kakera の知見抽出エージェントです。
下記 Claude Code セッション transcript (user / assistant の text のみ) を読み、~/.claude/CLAUDE.md の「kakera」セクションのプロトコルに従って、新しく学べた構造化知見だけを ${KAKERA_HOME}/knowledge/ 配下に保存してください。

カテゴリ: decisions / mistakes / feedback / design / project / user / questions

抽出ルールはすべて ~/.claude/CLAUDE.md に書かれています。
- Surprise 3 段判定 (整合 / 補強 / 矛盾) でファイル新規作成 / Edit / references 追記を選ぶ
- サブ hub への振り分け
- frontmatter (name / description / type / importance / created / decay / references) 必須
- 価値ある知見がない場合は何も書かない

完了後、書いた/更新したファイル一覧と Surprise 判定を出力。何も書かなかった場合は「no knowledge to save」とだけ出力。

セッション ID: $SESSION_ID
Vault: $KAKERA_HOME"

printf '%s' "$EXTRACTED" | "$CLAUDE_CMD" -p "$PROMPT" >> "$LOG" 2>&1 &
SAVE_PID=$!

(sleep "$TIMEOUT" && kill "$SAVE_PID" 2>/dev/null && echo "[$(date)] TIMEOUT: killed save (pid=$SAVE_PID)" >> "$LOG") &
WATCHDOG_PID=$!

wait "$SAVE_PID" 2>/dev/null
EXIT=$?
kill "$WATCHDOG_PID" 2>/dev/null
echo "[$(date)] Save finished (exit=$EXIT)" >> "$LOG"

BIN_DIR="$(dirname "$0")/../bin"
PYTHON="$(command -v python3 || echo /usr/bin/python3)"

# hub note を importance × recency で再生成
if [ -x "$BIN_DIR/regen-hubs.py" ]; then
  "$PYTHON" "$BIN_DIR/regen-hubs.py" >> "$LOG" 2>&1 || true
  echo "[$(date)] Hubs regenerated" >> "$LOG"
fi

# 全ノートサマリ INDEX.md を再生成 (検索の入口)
if [ -x "$BIN_DIR/build-index.py" ]; then
  "$PYTHON" "$BIN_DIR/build-index.py" >> "$LOG" 2>&1 || true
  echo "[$(date)] INDEX rebuilt" >> "$LOG"
fi

# 月初 audit (その月にまだ走っていなければ実行)
AUDIT_FLAG="$KAKERA_HOME/.audit-$(date +%Y-%m).md"
if [ -x "$BIN_DIR/audit.py" ] && [ ! -f "$AUDIT_FLAG" ]; then
  "$PYTHON" "$BIN_DIR/audit.py" > "$AUDIT_FLAG" 2>&1 || true
  echo "[$(date)] Monthly audit ran -> $AUDIT_FLAG" >> "$LOG"
fi

# 週次 review-queue (ISO 週単位で flag)
REVIEW_FLAG="$KAKERA_HOME/.review-$(date +%G-W%V).flag"
if [ -x "$BIN_DIR/review-queue.py" ] && [ ! -f "$REVIEW_FLAG" ]; then
  "$PYTHON" "$BIN_DIR/review-queue.py" >> "$LOG" 2>&1 || true
  touch "$REVIEW_FLAG"
  echo "[$(date)] Weekly review-queue regenerated" >> "$LOG"
fi
