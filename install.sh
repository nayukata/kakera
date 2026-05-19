#!/bin/bash
# kakera installer (non-plugin path)
#
# Claude Code marketplace を使わずに kakera を導入する場合のスクリプト。
# 冪等。再実行しても既存ファイルを壊さない。
#
# 使い方:
#   ./install.sh              # 対話モード
#   KAKERA_HOME=~/foo ./install.sh   # パス指定
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
KAKERA_HOME="${KAKERA_HOME:-$HOME/kakera}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  \033[32mok\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m!!\033[0m %s\n" "$*"; }

bold "kakera installer"
echo
echo "  Repo:        $REPO_DIR"
echo "  KAKERA_HOME: $KAKERA_HOME"
echo

if [ -t 0 ]; then
  read -r -p "  Vault パスをこのまま使う? [Y/n] " ans
  case "$ans" in
    n|N|no|No) read -r -p "  Vault パスを入力 (例: ~/kakera): " custom
               KAKERA_HOME="${custom/#\~/$HOME}" ;;
  esac
fi

mkdir -p "$KAKERA_HOME/knowledge"/{decisions,mistakes,feedback,design,project,user,questions}
ok "Vault dir ensured: $KAKERA_HOME"

# MEMORY.md 雛形 (既存なら触らない)
if [ ! -f "$KAKERA_HOME/MEMORY.md" ]; then
  cat > "$KAKERA_HOME/MEMORY.md" <<'EOF'
# MEMORY

Claude Code セッションを跨いで参照する長期記憶 Vault のインデックス。

## クラスター (カテゴリ別 hub)

- [[フィードバック]] — 行動ガイドライン
- [[設計]] — 設計哲学・原則
- [[ユーザー]] — ユーザー背景・働き方
- [[プロジェクト]] — プロジェクト固有の文脈
- [[意思決定]] — 技術選定と理由
- [[失敗学習]] — エラー・修正指示の原因と再発防止
- [[問い]] — 未解決の問い (8 割止め)
EOF
  ok "MEMORY.md created"
else
  warn "MEMORY.md already exists (skipped)"
fi

# Hub note 雛形
declare_hub() {
  local category="$1" hub_name="$2" desc="$3"
  local path="$KAKERA_HOME/knowledge/$category/$hub_name.md"
  if [ -f "$path" ]; then
    warn "$category/$hub_name.md exists (skipped)"
    return
  fi
  cat > "$path" <<EOF
---
name: $hub_name
description: $desc
type: hub
importance: high
created: $(date +%Y-%m-%d)
decay: permanent
---

# $hub_name

$desc

戻る: [[MEMORY]]

## メンバー

_未記録。_
EOF
  ok "$category/$hub_name.md created"
}

declare_hub feedback  "フィードバック" "行動ガイドライン"
declare_hub design    "設計"           "設計哲学・原則"
declare_hub user      "ユーザー"       "ユーザー背景"
declare_hub project   "プロジェクト"   "プロジェクト固有の文脈"
declare_hub decisions "意思決定"       "技術選定と理由"
declare_hub mistakes  "失敗学習"       "エラー・修正指示の原因と再発防止"
declare_hub questions "問い"           "未解決の問い (8 割止め)"

# bin/ hooks/ を symlink (リポジトリ更新が即反映されるように)
mkdir -p "$KAKERA_HOME/bin" "$KAKERA_HOME/hooks"
for f in audit.py regen-hubs.py review-queue.py build-index.py; do
  ln -sfn "$REPO_DIR/bin/$f" "$KAKERA_HOME/bin/$f"
done
for f in on-session-end.sh save-knowledge.sh; do
  ln -sfn "$REPO_DIR/hooks/$f" "$KAKERA_HOME/hooks/$f"
done
ok "bin/ hooks/ symlinked from repo"

# Obsidian graph view テンプレ (INDEX/RECENT/REVIEW を除外、カテゴリ別カラーグループ)
# 既存の .obsidian/graph.json があれば触らない (ユーザー設定を尊重)
if [ -d "$KAKERA_HOME/.obsidian" ] || [ -t 0 ] && read -r -p "  Obsidian で graph view を使う? graph.json テンプレを置きますか [y/N] " ans 2>/dev/null; then
  case "${ans:-n}" in
    y|Y|yes|Yes)
      mkdir -p "$KAKERA_HOME/.obsidian"
      if [ ! -f "$KAKERA_HOME/.obsidian/graph.json" ]; then
        cp "$REPO_DIR/templates/obsidian/graph.json" "$KAKERA_HOME/.obsidian/graph.json"
        ok ".obsidian/graph.json template copied"
      else
        warn ".obsidian/graph.json already exists (skipped)"
      fi
      ;;
  esac
fi

# .kakera-config.toml 雛形 (既存なら触らない)
if [ ! -f "$KAKERA_HOME/.kakera-config.toml" ]; then
  cat > "$KAKERA_HOME/.kakera-config.toml" <<EOF
[vault]
path = "$KAKERA_HOME"

[recall]
style = "implicit"

[obsidian]
enabled = false
EOF
  ok ".kakera-config.toml created"
else
  warn ".kakera-config.toml already exists (skipped)"
fi

# CLAUDE.md (kakera section) の merge 案内
echo
bold "次のステップ"
echo
cat <<EOF
1. 環境変数を永続化:
   echo 'export KAKERA_HOME="$KAKERA_HOME"' >> ~/.zshrc   # or ~/.bashrc

2. SessionEnd hook を Claude Code に登録:
   ~/.claude/settings.json の hooks.SessionEnd に以下を追加
   {
     "matcher": "*",
     "hooks": [{
       "type": "command",
       "command": "$REPO_DIR/hooks/on-session-end.sh"
     }]
   }

3. CLAUDE.md の kakera セクションを ~/.claude/CLAUDE.md に取り込む:
   この repo の CLAUDE.md を読み、ご自身の ~/.claude/CLAUDE.md に追記してください。
   (marketplace 経由なら plugin が自動 provide します)

4. 初回セットアップ skill を Claude Code で実行:
   /kakera-init

完了です。会話の中で「これメモ」「同じミスしたくない」等と言うだけで蓄積されます。
EOF
