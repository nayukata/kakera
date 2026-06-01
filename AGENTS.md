# kakera

AI コーディングエージェント (Claude Code / Codex / Cursor 等) のセッションを跨いだ長期記憶 + 学習システム。
Vault パス: 環境変数 `$KAKERA_HOME` (default `~/kakera`)。
詳細プロトコルは各 skill (`/kakera-init` `/kakera-search` `/kakera-study` `/kakera-review` `/kakera-coach` `/kakera-book`) を参照。

<!-- kakera-inject:start -->
## 入力トリガー (自然言語で保存)

ユーザーが以下のような発話をしたら、直近の会話から要点を抽出して保存する。
保存後に「`<カテゴリ>` に保存しました: `<ファイル名>`」と短く報告する。

| トリガー語 (例) | 保存先 |
|---|---|
| 「これメモ」「覚えといて」「残しておいて」 | 文脈で判定 |
| 「同じミスしたくない」「またやらかした」「これ罠だった」 | `mistakes/` |
| 「あとで調べたい」「先に進めたい」「ここ分からないまま」「なぜ」「どう」「何が違う」を session 内で発した話題 | `questions/` (status: open/resolved 問わず、探究履歴として保存) |
| 「次回からこう判断する」「これは原則として残す」 | `feedback/` または `design/` (他プロジェクトでも適用できる原則の時) / `project/<name>/` (そのプロジェクト固有の判断の時) |
| 「この決定の理由を残したい」「技術選定の根拠」 | `decisions/` (プロジェクト跨ぎ) / `project/<name>/` (固有) |

「またこれだ」「前にもあった」と発話されたら `mistakes/` の再発検出を発動する (下記)。

## 検索トリガー (Claude が記憶を引く)

「関連しそうなら検索」では発火しない。dev flow の**観測可能な瞬間**を発火点にする。

### dev flow と recall point

| 瞬間 | 観測シグナル | アクション |
|---|---|---|
| prompt 受領直後 | 固有名詞 (project 名 / file path / エラー語 / 技術名) を含む | `$KAKERA_HOME/INDEX.md` を Read → keyword で絞る |
| 編集対象ファイル確定時 | これから Read/Edit する path / ドメイン | INDEX の `project/` `mistakes/` を path keyword で確認 |
| ユーザー訂正/否定を受けた時 | 「違う」「そうじゃない」「また」「前にも」 | INDEX の `feedback/` `mistakes/` を確認してから返答 |
| 設計判断の前 | 「どう設計するか」「どっちが良いか」 / 新規ファイル構成を提案する直前 | INDEX の `design/` `decisions/` を確認 |
| エラー遭遇時 | スタックトレース / エラーメッセージ | エラー語で `knowledge/mistakes/` を grep |
| 過去 Q&A を引く瞬間 | 「前に何て答えたっけ」「以前同じことを聞いた」「あの結論どうだった」 | INDEX の `questions/` を keyword で確認 |

スキップしてよい場面 typo 修正、純粋な表示文言変更、明らかに 1 行で終わる作業。

### 検索手順

1. `$KAKERA_HOME/INDEX.md` (全ノート 1 行サマリ) を Read
2. 候補が出たら本文を Read
3. ヒット 0 件でも「INDEX 確認済み」を 1 行残す (例: `kakera: 該当ノートなし`)。沈黙すると検索したか事後に判別不能

INDEX は `bin/build-index.py` が SessionEnd hook で自動更新。ユーザー向け `RECENT.md` も同走査で生成 (Claude は Read 不要)。
<!-- kakera-inject:end -->

### description 規約 (検索ヒット率を上げる)

ノートを書く時、description には**機械検索される語**を 1 つ以上含める。

- project 系 → 案件名 / ライブラリ固有名 (例: `ATSURAE DS`, `Figma Code Connect`)
- mistakes 系 → エラー文の特徴語 / 失敗対象の関数名 / ファイルパス
- design 系 → 適用される技術名 / パターン名 (例: `Compound Component`)
- feedback 系 → 適用される作業種別 (例: `PR 説明文`, `コミットメッセージ`)

「読んで意味が通じる説明文」だけでは grep に当たらない。**何の語で思い出されるべきか**を意識する。

## session 開始時の受動再会

ユーザーの最初の話題が出たら、関連カテゴリの hub note を Read して context に取り込む。
関連話題が出たら自分から `[[X]]` を引用する。

再会スタイル (`$KAKERA_HOME/.kakera-config.toml` の `[recall] style`)
- `explicit`: 関連知見を見つけたら毎回明示
- `implicit` (default): `importance: high` または矛盾発生時のみ明示

<!-- kakera-inject:start -->
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
<!-- kakera-inject:end -->

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

### ノート本文の推奨構造 (Obsidian で読むことを想定)

長文の Why / How to apply ラベルを並べた段落形式は読みにくい。下記要素を組み合わせる。

- 冒頭: `> [!tip] 一言で` または `> [!important]` で結論を 1-2 行
- 手順 / チェックリスト: 箇条書きまたは番号付きリスト
- 比較 / 区別 / 状態マトリクス: **表** (列=軸、行=対象、セル=値)。「状況→判定」のような単方向ペアは表にしない (認知負荷高) → 箇条書きや callout に
- 手順の分岐が複雑なら **mermaid (`flowchart TD` 縦方向)** で視覚化
- 注意 / 失敗例: `> [!warning]` `> [!danger]`
- 例: `> [!example]` (長ければ `> [!example]-` で折りたたみ)
- 関連ノート: 末尾の `## 関連` セクションに wikilink、または `戻る:` リンク

避ける

- 段落だけで埋めない (スキャンできない)
- `**Why:**` `**How to apply:**` ラベルを多用しない (古いテンプレ、表 / callout に置き換える)
- 1 ノート 1 主題、複数主題なら分割する
- **本文先頭の `# タイトル` は書かない**。Obsidian がファイル名を見出しとして表示するので二重になる。冒頭はいきなり `> [!tip] / > [!important]` から始める

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
| `decisions/` | プロジェクト跨ぎで参照する技術選定・方針決定 |
| `mistakes/` | エラー・修正指示の原因と再発防止策 |
| `feedback/` | ユーザーから受けた行動ガイドライン |
| `design/` | **他プロジェクトでも適用できる**設計哲学・原則 |
| `project/<name>/` | プロジェクト固有の文脈 / 設計判断 / 実装メモ。プロジェクト名のサブフォルダで分ける |
| `user/` | ユーザー背景・働き方 |
| `questions/` | 保留中の問い (`/kakera-study` で 4 セクション化: 問い / 自分の答え / 補強 / 結論) |

**カテゴリ分岐の指針 (project vs design)**

design/ にしまう前に**必ず固有名詞チェック**を実行する。下記シグナルが**1 つでも本文にあれば即 `project/<name>/`** に置く。design/ には移さない。

固有名シグナル (即 project 行き)

- 特定の製品名 / 案件名 (例: ATSURAE DS, kakera)
- 特定ライブラリ / ツールの固有機能名 (例: Figma Code Connect, `.figma.ts`)
- 固有のファイルパス / ディレクトリ構造 (例: `Parts/TextField.figma.ts`)
- 固有の関数名 / スクリプト名 (例: `save-knowledge.sh`)

判定の問い (3 つ全部 yes なら design/、1 つでも no なら project/)

1. 別の会社 / 別の案件で読まれても意味が通じるか?
2. 本文を 3 行に要約した時、固有名を消しても骨子が崩れないか?
3. 固有名を一般語 (「あるツール」「あるライブラリ」) に置換しても読めるか?

迷ったら `project/<name>/`。あとで一般化できると判断したら design/ に派生ノートを作る方が安全 (再発防止: [[2026-05-20_design配下にプロジェクト固有知識を混入]])。

**project/<name>/ が未作成の時**

「フォルダが無い」を design/ 逃避の理由にしない。本文の最有力固有名から snake_case でフォルダ名を決め、サブ hub note (`type: sub-hub`、`戻る: [[プロジェクト]]`) と一緒に新規作成する。命名に確信が無くても保存を優先 — 改名は cheap、design/ に紛れる回収コストの方が高い。

## skill 役割分担

| skill | 担当 |
|---|---|
| `/kakera-init` | セットアップ (Vault パス・再会スタイル・コーチモード) |
| `/kakera-search` | 検索 (ファジー / 自然文対応) |
| `/kakera-study` | 学習 (保留した問いを 1 件解く対話) |
| `/kakera-review` | メンテキュー表示 (古いメモ・昇格候補・重複候補) |
| `/kakera-organize` | 重複候補を 1 組ずつ提示してマージ / 削除 / 別物保持を対話判定 |
| `/kakera-coach` | コーチモードの on/off 切り替え |
| `/kakera-book` | 読書ノートから 6 ステップ対話で気付き抽出 |

`/kakera-review` (機械的キュー表示) と `/kakera-organize` (対話マージ) と `/kakera-study` (学習) を混同しない。review はリスト、organize は判断、study はユーザーの理解の整理。
