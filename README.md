# kakera

Claude Code 向けの自己学習プラットフォーム。

会話の中で学んだことを自然言語で蓄積し、次の対話で自然に再会する。
野口悠紀雄『超』勉強法 (面白い・全体から・8 割) と精緻化 / 体制化を実装したもの。

## 何ができるか

- **入力**: 「これメモ」「覚えといて」「同じミスしたくない」のような自然言語で蓄積
- **蓄積**: 構造化 Markdown として `~/kakera/knowledge/` に保存。Obsidian 不要、`cat` / `grep` で読める
- **再会**: 次の session で関連話題が出たら Claude が能動的に想起する
- **育成**: `/kakera-review` で 8 割止めの問いや鮮度切れノートを点検

## 設計思想

### 受動再会を主軸

「育成」フェーズで `REVIEW.md` を見に行く義務化は続かない。
Claude が次の session で関連知見を自然に想起する方が UX 的に強い。
session 開始時に話題に関連する hub note を黙って Read し、話の流れで `[[X]]` と参照する。
能動レビュー (`/kakera-review`) はオプション扱い。

### 明示保存は自然言語のみ

「これメモ」「覚えといて」のような自然言語のトリガー語を Claude が検知して保存する。
別ツールは開かない、タグは選ばない、フォルダは指定しない。カテゴリも Claude が文脈から判断する。
slash command は強制しないが、ユーザーが言わなければ保存されない (沈黙のメモは取らない)。

### Obsidian は装飾

Markdown ファイルとして全てを保存する。Obsidian を使えば graph view で可視化できるが、
使わなくても `cat` / `grep` / `rg` で操作できる。

### Surprise 3 段判定 (A-MEM / Titans 由来)

新しい知見を保存する時、既存メモリとの関係で 3 分類して扱う。

| 種別 | 条件 | 動作 |
|---|---|---|
| 整合 (low surprise) | 既存と 90% 超重複 | 新規作成せず references に日付追記 |
| 補強 (medium surprise) | より一般化 / 反例 / 適用拡張 | 既存ノートを Edit |
| 矛盾 (high surprise) | 既存の前提を覆す | 新規作成 + 双方向リンク |

これにより「冗長な重複ノートで Vault が汚れる」「矛盾が放置される」を防ぐ。

### 鮮度減衰

| decay | 用途 |
|---|---|
| `permanent` | 設計哲学・行動原則 |
| `6months` | アーキテクチャ判断、技術選定 |
| `3months` | プロジェクト固有の設計判断 |
| `1month` | 暫定対応、未解決の問い |

`references` が 3 件以上に達すると `permanent` に昇格 (繰り返し再確認された知見)。

## 使い方

### 1. session 開始時 (受動再会)

ユーザーが最初の話題を出した時点で、Claude は関連カテゴリの hub note を Read する。
ユーザーは何もしなくていい。

```
ユーザー: Postgres の接続プールでまた詰まってる
Claude:   (knowledge/mistakes/ と decisions/ を確認)
         以前 [[2026-03-15_pgBouncerはtransactionモードで]] でこの問題を扱っています。
         transaction モードに切り替えた経緯がありますが、また再発ですか?
```

### 2. 明示的に残したい時 (自然言語トリガー)

トリガー語を含む発話で保存される。slash command は不要。

```
ユーザー: 今日 Postgres の RLS で詰まった。row_security ON にしてもポリシー定義してないと
        全行返らないのか。これ罠だな、覚えといて
Claude:   mistakes/ に保存しました: 2026-05-19_RLSはポリシー無しだと全行ブロック.md
```

主なトリガー語
- 「これメモ」「覚えといて」「残しておいて」 → 文脈から保存先を判断
- 「同じミスしたくない」「またやらかした」「これ罠だった」 → `mistakes/`
- 「あとで調べたい」「今は 8 割で進める」 → `questions/`
- 「次回からこう判断する」 → `feedback/` or `design/`
- 「この決定の理由を残したい」 → `decisions/`

### 3. 過去の判断を引きたい時 (能動検索)

ユーザーが過去を参照する話題を出すと Claude が `knowledge/` を検索する。
明示的に呼びたい時は `/kakera-search <query>`。

```
ユーザー: 前にこのフレームワーク選んだ理由って何だっけ
Claude:   (kakera を検索)
         以前 [[2026-03-12_状態管理にZustandを選定]] でこう判断しています:
         - Redux は学習コスト過大、Recoil は実験的
         - Zustand は API が単純で SSR に強い
         今回も同じ要件ですか?
```

### 4. 育てたい時 (能動レビュー)

```
/kakera-review

# 今週の復習キュー
## 未解決の問い (3 件)
- 8 割止めだった疑問が並ぶ
## 鮮度切れ (1 件)
## 昇格候補 (2 件)
```

## インストール

### A. Claude Code marketplace 経由

```
/plugin marketplace add nayukata/kakera
/plugin install kakera
/kakera-init
```

更新は `/plugin marketplace update kakera` で取得後 `/plugin update kakera`。

### B. install.sh 経由

```sh
git clone https://github.com/nayukata/kakera.git
cd kakera
./install.sh
```

install.sh が完了後の `次のステップ` を表示するのでそれに従う。

## ディレクトリ構造

```
$KAKERA_HOME/
├── MEMORY.md            # インデックス
├── REVIEW.md            # 復習キュー (週次自動生成)
├── .kakera-config.toml  # ユーザー設定
└── knowledge/
    ├── decisions/   # 技術選定・方針決定
    ├── mistakes/    # エラー・修正指示
    ├── feedback/    # 行動ガイドライン
    ├── design/      # 設計原則
    ├── project/     # プロジェクト固有
    ├── user/        # ユーザー背景
    └── questions/   # 未解決の問い
```

サブ hub は同名サブフォルダとして物理階層に反映される (例: `design/長期記憶設計/MemoryEvolutionで知見を育てる.md`)。3 件以上の関連ノートが溜まると Claude が自動でサブ hub を作る。

## 環境変数

| 変数 | default | 説明 |
|---|---|---|
| `KAKERA_HOME` | `~/kakera` | Vault 保存先 |

## skill

| skill | 用途 |
|---|---|
| `/kakera-init` | 初回セットアップ |
| `/kakera-search <query>` | 蓄積知識の検索 + 要約 |
| `/kakera-review` | 復習キュー生成 + 対話レビュー |

## hook

`hooks/on-session-end.sh` を Claude Code の SessionEnd hook に登録すると、
session 終了時に Claude が transcript を読んで自動抽出する (デタッチ実行)。

## 依存

- Claude Code CLI (`claude`)
- `jq`
- `python3`
- `rg` (ripgrep、`/kakera-search` 用、無くても動くが遅い)

## ライセンス

MIT
