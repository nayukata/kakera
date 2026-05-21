#!/bin/bash
# 知見抽出の実処理。on-session-end.sh (Claude Code) / codex/on-stop.sh (Codex) から nohup で呼ばれる。
# 引数: agent_cmd kakera_home transcript_path session_id log_path [timeout_seconds] [agent_subcmd]
#   agent_cmd     : エージェント CLI のフルパス (例: /usr/local/bin/claude, /usr/local/bin/codex)
#   agent_subcmd  : prompt を渡すサブコマンド / フラグ (default "-p", codex は "exec")
set -u

AGENT_CMD="$1"
KAKERA_HOME="$2"
TRANSCRIPT_PATH="$3"
SESSION_ID="$4"
LOG="$5"
TIMEOUT="${6:-600}"
AGENT_SUBCMD="${7:--p}"

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

# kakera プロトコル (Surprise 判定 / サブ hub / frontmatter 必須) はエージェントの
# agent rule (Claude Code なら CLAUDE.md、Codex なら AGENTS.md) に既に読み込まれている前提。
PROMPT="あなたは kakera の知見抽出エージェントです。
下記セッション transcript (user / assistant の text のみ) を読み、kakera プロトコルに従って、新しく学べた構造化知見だけを ${KAKERA_HOME}/knowledge/ 配下に保存してください。

カテゴリ: decisions / mistakes / feedback / design / project / user / questions

【必須の作業手順】 以下の順序で実行すること。スキップ厳禁。

STEP 1. INDEX を読む
- ${KAKERA_HOME}/INDEX.md を **必ず** Read する。全ノートの 1 行サマリが入っている。

STEP 2. 抽出候補を列挙
- transcript から「保存に値する知見」を**短文の見出しリスト**として 1 度に書き出す (この時点ではファイルを作らない)。

STEP 3. 各候補について既存ノート検索を実行
- 候補ごとに INDEX 上で類似テーマを探す
- 加えて Grep / find で keyword 検索 (タイトル語 / description キー語 / 同義語) を **必ず実行**
- 候補ごとに「該当する既存ノート」を 0〜3 件挙げる

STEP 4. Surprise 3 段判定を**候補ごとに**適用
- 既存と 90% 超一致 → **新規作成しない**。既存ノートを Read → `references` に今日の日付を追記する Edit を実行
- 既存をより一般化 / 反例 / 適用拡張 → 既存を Read → 該当箇所を Edit (重要: 上書きではなく追記/補強)。`references` も追記
- 既存の前提を覆す or 既存に該当無し → 新規作成。旧ノートがあれば双方向 wikilink を追加
- 「既存無し」判定は STEP 3 の検索結果が空だった場合のみ許可

STEP 5. 書き込み
- mistakes/ は recurrence チェック (既存があれば recurrence +1、新規作成しない)
- design/ への保存前に固有名詞チェック (下記)
- frontmatter (name / description / type / importance / created / decay / references) 必須
- 価値ある知見がない場合は何も書かない

【必須】design/ への保存前に固有名詞チェックを実行:
本文に「特定の製品 / 案件 / ツール / ライブラリ / ファイルパス / 関数名」が出現する場合は design/ には置かず、必ず project/<name>/ に置く。判断の問い 3 つ (別案件で意味通るか / 固有名消して骨子残るか / 一般語に置換できるか) を内部で確認し、1 つでも no なら project/。再発防止: mistakes/2026-05-20_design配下にプロジェクト固有知識を混入.md 参照。

【project/<name>/ フォルダが無い場合】
- 既存フォルダに合致しなくても design/ に逃さない
- 本文の最有力固有名 (頭字語 / 製品名 / リポジトリ名 / 拡張子付きファイル名の親概念) から folder 名を snake_case で決め、project/<name>/ を新規作成
- 同時にサブ hub note (type: sub-hub, 戻る: [[プロジェクト]]) も作成し ## メンバー を初期化
- 命名に確信が無くても保存を優先。後の改名は cheap、design/ に紛れる方が回収コスト高い

完了後、各候補ごとに以下を 1 行で報告:
  <候補見出し> -> [新規|更新|references追記|スキップ] <ファイル名> (Surprise: <integer 1-10>, 既存 <該当ノート名 or なし>)
何も書かなかった場合は「no knowledge to save」とだけ出力。

セッション ID: $SESSION_ID
Vault: $KAKERA_HOME"

printf '%s' "$EXTRACTED" | "$AGENT_CMD" "$AGENT_SUBCMD" "$PROMPT" >> "$LOG" 2>&1 &
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
