---
description: kakera の初回セットアップ。Vault パス / Obsidian 連携 / 再会スタイル (明示頻度) を対話で決め、$KAKERA_HOME/.kakera-config.toml に保存する。MEMORY.md とカテゴリ hub の雛形が無ければ作成する。plugin インストール直後の最初の入口。
---

# kakera-init

## 目的

kakera plugin の初回セットアップを対話で完了する。
ユーザーの環境に合わせて Vault パス・再会スタイル・Obsidian 連携を決定する。

## 実行手順

### 1. 環境確認

- `$KAKERA_HOME` 環境変数を確認 (未設定なら `~/kakera` を default に提示)
- 既に `$KAKERA_HOME/.kakera-config.toml` があれば「既存設定を編集しますか? それとも再セットアップ?」と確認

### 2. 対話項目 (AskUserQuestion を使って 1 問ずつ)

順序

1. **Vault パス**: `~/kakera` (default) / `~/Obsidian/<vault名>/kakera` / カスタム
2. **Obsidian 連携**: 「Obsidian で graph view を使いますか?」 yes/no
   - yes なら graph 設定 (フォルダ別カラーグループ等) の `.obsidian/graph.json` 雛形を提案
   - no なら何もしない
3. **再会スタイル**: `explicit` (明示多め) / `implicit` (明示少なめ、default)
4. **環境変数の永続化方法**: `~/.zshrc` / `~/.bashrc` / 手動 (`echo` するだけ)

### 3. 設定ファイル書き込み

`$KAKERA_HOME/.kakera-config.toml`

```toml
[vault]
path = "/Users/.../kakera"

[recall]
style = "implicit"  # or "explicit"

[obsidian]
enabled = false  # or true
```

### 4. 雛形作成 (既存なら触らない)

- `$KAKERA_HOME/MEMORY.md` (インデックス)
- `$KAKERA_HOME/knowledge/{decisions,mistakes,feedback,design,project,user,questions}/`
- 各カテゴリ直下の hub note (`フィードバック.md` `設計.md` `ユーザー.md` `プロジェクト.md` `意思決定.md` `失敗学習.md` `問い.md`)

### 5. 環境変数の永続化

選択された rc ファイルに以下を追記 (既に存在すれば skip)

```bash
export KAKERA_HOME="<選択パス>"
```

### 6. SessionEnd hook の登録

`~/.claude/settings.json` の `hooks.SessionEnd` に plugin の hook が登録されているか確認。
plugin 経由なら自動。`install.sh` 経由なら手動追加の指示を提示。

### 7. 完了報告

- セットアップ完了内容を 5 行以内で要約
- 次のアクション「会話の中で『これメモ』と言うだけで蓄積される。明示的に貯めたい時は `/kakera-review`、検索は `/kakera-search`」を提示

## 禁止事項

- 既存ファイルを許可なく上書きしない (config.toml 含む)
- ユーザーの rc ファイルを許可なく書き換えない (確認してから追記)
- KAKERA_HOME を環境変数なしで動かそうとしない (必ず export を促す)
