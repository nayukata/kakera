---
description: kakera の能動レビュー導線。$KAKERA_HOME/REVIEW.md を再生成し、未解決の問い / 鮮度切れ / 昇格候補を Top 10 で表示する。週末や節目に「最近の学びを育てたい」と思った時に呼ぶ。Obsidian を使わない人にも価値が出る設計。
---

# kakera-review

## 目的

蓄積した知識を「育てる」フェーズの能動入口。受動再会だけだと触れない領域 (8 割止めの問い / 古くなったノート / 何度も再確認されたが decay 残っているノート) をユーザーに提示する。

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
# 今週の復習キュー

## 未解決の問い (N 件)
- [[X]] — 8 割止めだった疑問
- ...

## 鮮度切れ (N 件)
- [[Y]] — 6months 超過

## 昇格候補 (N 件)
- [[Z]] — references 4 件、permanent に格上げ可
```

### 3. 1 件ずつ対話

ユーザーが「最初の問いを解こう」と言ったら

- そのノートを Read
- 現在の知識状態を確認
- 解決できそうなら通常ノートへ昇格 (questions/ から移動 + type 変更)
- まだ未解決なら decay を延長 (1month → 1month のまま、created 更新)

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
