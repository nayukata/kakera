---
description: kakera Vault の蓄積知識を全文検索 + Claude が関連度評価して要約する。「あの判断どこだっけ」「以前似た問題を扱った」の救済。ユーザーが「kakera を検索」「過去の判断を引きたい」と発言した時、または引数 query が与えられた時に発動。
argument-hint: <検索クエリ> -- 省略時はユーザーに尋ねる
---

# kakera-search

## 目的

蓄積された knowledge ノートから、現在の話題に関連するものを引き出す。
ripgrep で全文検索し、Claude が関連度を判断して要約する。

## 実行手順

### 1. クエリ確定

- `$ARGUMENTS` が空 → ユーザーに「何を探しますか?」と尋ねる
- ある → そのまま使う

### 2. 検索範囲

- `$KAKERA_HOME/knowledge/` 配下を `rg` で再帰検索
- frontmatter の `description` と本文の両方を対象
- 大文字小文字無視 (`-i`)、wikilink 内も含む

### 3. 検索コマンド

```bash
KAKERA_HOME="${KAKERA_HOME:-$HOME/kakera}"
rg -l -i "<query>" "$KAKERA_HOME/knowledge/"
```

- ヒット数が多すぎる時 (10 件超) は `description` のみで再検索して絞る

### 4. Claude による関連度評価

ヒットファイルを Read し、以下を判定

- 現在の話題と本当に関連するか (キーワード一致だけで関連と判断しない)
- 鮮度 (decay と最新 reference 日付を見る)
- 矛盾するノート同士があれば両方提示

### 5. 出力形式

```markdown
## 関連知見 (N 件)

### 1. [[ノート名]] (importance: high / decay: permanent)
description

**要点**: 1-2 行で本文の核

### 2. ...
```

- 上位 3-5 件まで
- 関連度低いものは省略
- 鮮度切れ警告: 「このノートは decay: 3months を超過。現状と照合してください」

### 6. ヒットゼロの時

「knowledge/ に該当なし。今の話題は新規の可能性が高い」と伝える。
ユーザーに「現状の判断を kakera に保存しますか?」と提案する (強制しない)。

## 禁止事項

- 検索結果を鵜呑みにせず、現在の状況と照合する旨を必ず添える
- 古いノート (decay 超過) を「正しい答え」として引用しない
- 一度に大量 (10 件超) のノートを並べない (認知負荷)
