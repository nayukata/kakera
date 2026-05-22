---
name: kakera-init
description: kakera の初回セットアップ。Vault パス / Obsidian 連携 / 再会スタイル (明示頻度) / コーチモード on-off を対話で決め、$KAKERA_HOME/.kakera-config.toml に保存する。MEMORY.md とカテゴリ hub の雛形が無ければ作成する。plugin インストール直後の最初の入口。
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
   - yes なら `$KAKERA_HOME/.obsidian/graph.json` に repo の `templates/obsidian/graph.json` をコピー (既存があれば触らない)。INDEX / RECENT / REVIEW を除外する search filter とカテゴリ別カラーグループが入っている
   - no なら何もしない
3. **再会スタイル**: `explicit` (明示多め) / `implicit` (明示少なめ、default)
4. **コーチモード**: on / off (default on)。Claude が対話中の理解の怪しさを検出して問いかけるかどうか。後で `/kakera-coach` でも切り替え可能
5. **環境変数の永続化方法**: `~/.zshrc` / `~/.bashrc` / 手動 (`echo` するだけ)

### 3. 設定ファイル書き込み

`$KAKERA_HOME/.kakera-config.toml`

```toml
[vault]
path = "/Users/.../kakera"

[recall]
style = "implicit"  # or "explicit"

[obsidian]
enabled = false  # or true

[study]
enabled = true   # コーチモード on/off
off_streak = 0   # 連続 off カウント
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

### 5.5. `~/.claude/CLAUDE.md` にカテゴリ判定指針を追記

**目的**: plugin の CLAUDE.md は Claude セッションに自動ロードされないため、knowledge/ 配下に直書きするケースで design/project 判定が抜け落ちる事故が起きる。user 個人の `~/.claude/CLAUDE.md` に直接追記して、全セッションで判定指針が context に入る状態にする。

実施:

- `~/.claude/CLAUDE.md` の中に「## 記憶 (kakera)」セクションがあるか grep で確認
- 無ければ末尾に下記 stub を追記
- 既に同名セクションがあれば、内容差分を提示してユーザーに上書き/skip を確認

追記する stub (リポジトリ URL や plugin 情報は含めない):

```markdown
## 記憶 (kakera)

個人 Vault は `~/Obsidian/kakera/` (`KAKERA_HOME` で指定)。

### カテゴリ早見表

| カテゴリ | 用途 |
|---|---|
| `decisions/` | プロジェクト跨ぎで参照する技術選定・方針決定 |
| `mistakes/` | エラー・修正指示の原因と再発防止策 |
| `feedback/` | ユーザーから受けた行動ガイドライン |
| `design/` | **他プロジェクトでも適用できる**設計哲学・原則 |
| `project/<name>/` | プロジェクト固有の文脈 / 設計判断 / 実装メモ |
| `user/` | ユーザー背景・働き方 |
| `questions/` | 保留中の問い |

### project vs design の判定 (knowledge/ に保存する前に必ず実行)

下記シグナルが **1 つでも本文にあれば即 `project/<name>/`** に置く。design/ には移さない。

- 特定の製品名 / 案件名
- 特定ライブラリ / ツールの固有機能名
- 固有のファイルパス / スクリプト名
- 固有の関数名

3 つ全部 yes なら `design/`、1 つでも no なら `project/<name>/`。

1. 別の会社 / 別の案件で読まれても意味が通じるか?
2. 本文を 3 行に要約した時、固有名を消しても骨子が崩れないか?
3. 固有名を一般語 (「あるツール」「あるライブラリ」) に置換しても読めるか?

迷ったら `project/<name>/`。あとで一般化できると判断したら design/ に派生ノートを作る方が安全。
```

### 6. SessionEnd hook の登録

`~/.claude/settings.json` の `hooks.SessionEnd` に plugin の hook が登録されているか確認。
plugin 経由なら自動。`install.sh` 経由なら手動追加の指示を提示。

### 7. 完了報告

- セットアップ完了内容を 5 行以内で要約
- 次のアクション「会話の中で『これメモ』と言うだけで蓄積される。検索は `/kakera-search`、保留した問いを解くなら `/kakera-study`、メンテは `/kakera-review`、コーチモード切替は `/kakera-coach`」を提示

## 禁止事項

- 既存ファイルを許可なく上書きしない (config.toml 含む)
- ユーザーの rc ファイル / `~/.claude/CLAUDE.md` を許可なく書き換えない (確認してから追記)
- KAKERA_HOME を環境変数なしで動かそうとしない (必ず export を促す)
