---
name: kakera-review
description: kakera Vault のメンテ導線。$KAKERA_HOME/REVIEW.md を再生成し、古くなったメモ (decay 超過) と昇格候補 (references 3 件以上) を Top 10 で表示する。週末や節目に「最近溜まったメモを整える」「古い判断を最新化する」と思った時に呼ぶ。保留した問いの再訪・学習対話は /kakera-study が担当する (役割分離)。
---

# kakera-review

## 目的

Vault のメンテ用入口。古いメモの更新と permanent への昇格を扱う。
学習対話 (保留した問いを解く) は `/kakera-study` 側にあるので、ここでは扱わない。

## 実行手順

### 1. REVIEW.md 再生成

```bash
KAKERA_HOME="${KAKERA_HOME:-$HOME/kakera}"
python3 "$(dirname "$0")/../../bin/review-queue.py"
```

plugin のパス解決は環境で変わるので、`$CLAUDE_PLUGIN_ROOT` 等の変数が利用できるならそれを優先する。
それも無ければ `command -v` で kakera plugin を探す。

### 2. REVIEW.md を Read して表示

```markdown
# 今週のメンテキュー

## 鮮度切れ (N 件)
- [[Y]] — 6months 超過

## 昇格候補 (N 件)
- [[Z]] — references 4 件、permanent に格上げ可
```

### 3. 1 件ずつ対話

ユーザーが「最初の鮮度切れを処理しよう」と言ったら

- そのノートを Read
- 現在の状況と照合
- まだ有効なら `created` を今日に更新 (鮮度リセット)
- 古くなっていれば内容を最新化、または削除
- 「保留中の問い」が出てきたら `/kakera-study` を案内する (このコマンドでは処理しない)

### 4. バッチ処理オプション

ユーザーが「全部処理して」と言ったら
- 昇格候補は `decay: permanent` に一括更新
- 鮮度切れは「現状と照合した結果」をユーザーに確認しながら更新 or 削除

### 5. Obsidian 連携

`.kakera-config.toml` で `obsidian.enabled = true` なら、最後に
`open -a Obsidian "$KAKERA_HOME/REVIEW.md"` を提案 (実行しない、コマンド提示のみ)

## 禁止事項

- ユーザーに無断でノートを移動・削除・更新しない (1 件ずつ確認)
- バッチ処理は明示的に「全部処理して」と言われた時のみ
- REVIEW.md 自体をユーザーが編集している可能性に注意 (再生成前に diff を見せる)
