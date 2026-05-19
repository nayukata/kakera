# kakera

Claude Code セッションを跨いだ長期記憶 + 学習システム。
Vault パス: 環境変数 `$KAKERA_HOME` (default `~/kakera`)。
詳細プロトコルは各 skill (`/kakera-init` `/kakera-search` `/kakera-study` `/kakera-review` `/kakera-coach` `/kakera-book`) を参照。

## 入力トリガー (自然言語で保存)

ユーザーが以下のような発話をしたら、直近の会話から要点を抽出して保存する。
保存後に「`<カテゴリ>` に保存しました: `<ファイル名>`」と短く報告する。

| トリガー語 (例) | 保存先 |
|---|---|
| 「これメモ」「覚えといて」「残しておいて」 | 文脈で判定 |
| 「同じミスしたくない」「またやらかした」「これ罠だった」 | `mistakes/` |
| 「あとで調べたい」「先に進めたい」「ここ分からないまま」 | `questions/` |
| 「次回からこう判断する」「これは原則として残す」 | `feedback/` または `design/` |
| 「この決定の理由を残したい」「技術選定の根拠」 | `decisions/` |

「またこれだ」「前にもあった」と発話されたら `mistakes/` の再発検出を発動する (下記)。

## 検索トリガー (Claude が記憶を引く)

過去参照 (「前に」「以前」「あの時」「前回」) や設計判断議論では、提案前に knowledge を検索する。
typo 修正やスタイル変更などはスキップ。

検索手順
1. まず `$KAKERA_HOME/INDEX.md` (全ノート 1 行サマリ) を Read
2. 関連候補を description ベースで絞り込む
3. 必要なら該当ノート本文を Read

これでファイル数が増えても context 消費を抑えられる。INDEX は `bin/build-index.py` が SessionEnd hook で自動更新する。

## session 開始時の受動再会

ユーザーの最初の話題が出たら、関連カテゴリの hub note を Read して context に取り込む。
関連話題が出たら自分から `[[X]]` を引用する。

再会スタイル (`$KAKERA_HOME/.kakera-config.toml` の `[recall] style`)
- `explicit`: 関連知見を見つけたら毎回明示
- `implicit` (default): `importance: high` または矛盾発生時のみ明示

## コーチモード (理解度チェック)

`[study] enabled = true` の時のみ有効 (default on)。

検出シグナル
- 曖昧な言い回し (「なんか」「たぶん」「気がする」)
- 過去判断との不整合
- 専門用語を借りているだけ
- 前提→結論の推論が飛んでいる

検出したら 1 session 2-3 回まで「ここの理解、確認させて」と問う。
opt-out 発話 (「いいから答えだけ」「飛ばして」) で session 内 off。
連続 3 セッション off で恒久 off 確認 (`[study] off_streak` で追跡)。
詳細: `/kakera-coach` SKILL.md。

## 書き込み時の必須ルール

### Surprise 3 段判定

- **重複** (low surprise): 既存と 90% 超一致 → 新規作成せず `references` に日付追記
- **更新** (medium surprise): 既存をより一般化 / 反例 / 適用拡張 → 既存を Edit、`references` 追記
- **新規** (high surprise): 既存の前提を覆す → 新規作成 + 旧ノートと双方向リンク

矛盾の場合は旧ノートに `## 矛盾するノート`、新ノートに `## 上書きする旧見解` を相互記載。

### mistakes/ 再発検出

`mistakes/` ノートは frontmatter に `recurrence` (再発回数) と `last_hit` (最後の再発日) を持つ。
類似する既存ノートがあれば新規作成せず `recurrence` を +1 する (Surprise 重複判定の特化形)。

| recurrence | 動作 |
|---|---|
| 1 | 通常通り保存 |
| 2 | 「過去の `[[X]]` と同じパターン。対策ある?」 |
| 3+ | 「N 回目です。ガードレール (lint / 型 / テスト / CI / デフォルト変更 / レビュー観点) を追加して `decisions/` に判断を残しませんか?」と能動提案 |

session 開始時に `recurrence ≥ 3` のノートがあれば先んじて注意喚起する。

### frontmatter 必須項目

```yaml
name: <ファイル名と同じ>
description: <一行要約>
type: feedback | design | user | project | decision | mistake | question
importance: high | medium | low
created: YYYY-MM-DD
decay: 1month | 3months | 6months | permanent
references:
  - YYYY-MM-DD
```

`references` が 3 件以上になったら `decay: permanent` に自動昇格。

### ファイル命名規則

- ファイル名 = 日本語タイトルそのもの。`feedback_` 等のカテゴリ prefix は付けない (フォルダで表現)
- `decisions/` `mistakes/` のみ `YYYY-MM-DD_` 日付 prefix を付ける
- wikilink `[[name]]` は実ファイル名と完全一致 (kebab/snake/英訳の揺れ厳禁)

### サブ hub (同名フォルダ運用)

同テーマで 3 件以上溜まったら、同名のサブフォルダを作って配下に集約 (例: `design/長期記憶設計/`)。
サブ hub ノート (`type: sub-hub`) を作り、`## メンバー` に `[[name]]` を列挙。
新ノートの末尾は `戻る: [[サブhub名]]`。
親 hub のメンバーリストは触らない (`bin/regen-hubs.py` が rglob 再帰で自動表示する)。

## カテゴリ早見表

| カテゴリ | 用途 |
|---|---|
| `decisions/` | 技術選定・方針決定 |
| `mistakes/` | エラー・修正指示の原因と再発防止策 |
| `feedback/` | ユーザーから受けた行動ガイドライン |
| `design/` | 設計哲学・原則 |
| `project/` | プロジェクト固有の文脈 |
| `user/` | ユーザー背景・働き方 |
| `questions/` | 保留中の問い (`/kakera-study` で 4 セクション化: 問い / 自分の答え / 補強 / 結論) |

## skill 役割分担

| skill | 担当 |
|---|---|
| `/kakera-init` | セットアップ (Vault パス・再会スタイル・コーチモード) |
| `/kakera-search` | 検索 (ファジー / 自然文対応) |
| `/kakera-study` | 学習 (保留した問いを 1 件解く対話) |
| `/kakera-review` | メンテ (古いメモ・昇格候補) |
| `/kakera-coach` | コーチモードの on/off 切り替え |
| `/kakera-book` | 読書ノートから 6 ステップ対話で気付き抽出 |

`/kakera-review` (メンテ) と `/kakera-study` (学習) を混同しない。前者はファイルの整理、後者はユーザーの理解の整理。
