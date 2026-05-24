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

# plugin の repo root を解決し、templates 参照用に export する
KAKERA_PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export KAKERA_PLUGIN_DIR

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
- 同時に **questions/ 候補** も列挙する。発火条件:
  - ユーザーが session 内で「なぜ」「どう」「何が違う」「どこで」等の疑問形を発した話題
  - ユーザーが「分からない」「気になる」「調べたい」を表明した話題
  - 同じ話題で 2 回以上問い直した形跡 (繰り返し問い直し = 重要)
  - 除外: typo 確認 / コマンド syntax 質問 / 既存ノートを参照すれば即解ける自明な事実確認
- questions 候補は解決済 / 未解決を**問わず**全部挙げる (現状の B 方針 = 探究履歴化)。

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
- questions/ は status: open | resolved を frontmatter に必ず付与
  - session 内で答えに到達 → status: resolved。「答え」セクションに到達点を記述
  - 未解決のまま終了 → status: open。「答え」セクションは「未解決」
  - 既存 questions/ ノートと類似の問いがあれば新規作成せず references 追記 + 「答え」セクション更新
- frontmatter (name / description / type / importance / created / decay / references) 必須
- 価値ある知見がない場合は何も書かない

STEP 6. 書き方品質ガード (新規作成時に必須、更新時は該当箇所のみ)

(a) Template 参照
- ${KAKERA_PLUGIN_DIR}/templates/notes/<type>.md (design / mistakes / feedback / project / question) を Read してスケルトン踏襲
- decisions / user は既存 Note 2 件以上を Read して style 踏襲

(b) 書き方ルール
- 視覚構造 (callout / 表 / mermaid / 箇条書き)、散文濫用禁止、見出し構造は **AGENTS.md「ノート本文の推奨構造」に従う** (agent rule として load 済み)

(c) 読み手語彙レベル
- transcript の語彙レベルに合わせる。専門用語は同段落で平易な言い換え併置
- ユーザーが理解の浅さを示した場合 (「分からない」「何それ」)、専門用語禁止 + たとえ話必須

(d) references の事実性 (捏造禁止)
- transcript で観測された発話 / tool 結果のみ。物語化禁止
  - NG: 「ユーザー指摘で気づいた」(指摘発話なし) / 「〜事故」「〜から学んだ」(該当文脈なし)
  - OK: 発話の要約、発生した tool 呼び出しの結果

【必須】design/ への保存前に**固有名詞チェック**: 製品 / 案件 / ライブラリ固有名 / ファイルパス / 関数名が本文に 1 つでもあれば design/ に置かず project/<name>/ に置く。詳細判定 + project/<name>/ 未作成時の対応は **AGENTS.md「カテゴリ分岐の指針」「project/<name>/ が未作成の時」** に従う。再発防止: mistakes/2026-05-20_design配下にプロジェクト固有知識を混入.md

完了後、各候補ごとに以下を 1 行で報告:
  <候補見出し> -> [新規|更新|references追記|スキップ] <ファイル名> (Surprise: <integer 1-10>, 既存 <該当ノート名 or なし>)

**最後の 1 行は必ず以下の形式 (機械が grep するので厳守):**
  KAKERA_SUMMARY: created=<N> updated=<N> refs=<N> skipped=<N>

何も書かなかった場合は KAKERA_SUMMARY: created=0 updated=0 refs=0 skipped=0 を出力。

セッション ID: $SESSION_ID
Vault: $KAKERA_HOME
Plugin: $KAKERA_PLUGIN_DIR"

# agent の自由文出力は session 別の debug log に隔離 (main log に流すとノイズ化)
SAFE_SID=$(printf '%s' "${SESSION_ID:-unknown}" | tr -c '[:alnum:]_-' '_' | cut -c1-40)
SAVE_LOG="$KAKERA_HOME/.hook-save-${SAFE_SID}-$(date +%Y%m%d-%H%M%S).log"

printf '%s' "$EXTRACTED" | "$AGENT_CMD" "$AGENT_SUBCMD" "$PROMPT" > "$SAVE_LOG" 2>&1 &
SAVE_PID=$!

(sleep "$TIMEOUT" && kill "$SAVE_PID" 2>/dev/null && echo "[$(date)] TIMEOUT: killed save (pid=$SAVE_PID)" >> "$LOG") &
WATCHDOG_PID=$!

wait "$SAVE_PID" 2>/dev/null
EXIT=$?
kill "$WATCHDOG_PID" 2>/dev/null

# agent 出力から KAKERA_SUMMARY 行を抽出。無ければ "missing" として可視化
SUMMARY=$(grep -m1 '^KAKERA_SUMMARY:' "$SAVE_LOG" 2>/dev/null || echo "KAKERA_SUMMARY: missing (agent did not emit summary; see $SAVE_LOG)")
echo "[$(date)] Save finished (exit=$EXIT) $SUMMARY (detail=$SAVE_LOG)" >> "$LOG"

# 30 日以上前の save log を掃除
find "$KAKERA_HOME" -maxdepth 1 -name ".hook-save-*.log" -mtime +30 -delete 2>/dev/null || true

BIN_DIR="$(dirname "$0")/../bin"
PYTHON="$(command -v python3 || echo /usr/bin/python3)"

# post-processing は INDEX.md / hub note に並列書き込みすると壊れるので mkdir lock で排他化
# 別 session 同時終了 → 別 hook プロセスの並列実行を想定。lock 取得失敗側は次回 hook が拾うので skip 安全
POST_LOCK="$KAKERA_HOME/.post.lock"
# 5 分以上古い lock は前プロセスのクラッシュ残骸とみなして掃除
if [ -d "$POST_LOCK" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f%m "$POST_LOCK" 2>/dev/null || stat -c%Y "$POST_LOCK" 2>/dev/null || echo 0) ))
  if [ "$LOCK_AGE" -gt 300 ]; then
    rmdir "$POST_LOCK" 2>/dev/null || true
    echo "[$(date)] Stale post-lock removed (age=${LOCK_AGE}s)" >> "$LOG"
  fi
fi

if mkdir "$POST_LOCK" 2>/dev/null; then
  trap 'rmdir "$POST_LOCK" 2>/dev/null || true' EXIT

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
else
  echo "[$(date)] Post-processing skipped (another hook holds lock)" >> "$LOG"
fi
