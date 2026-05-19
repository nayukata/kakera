# kakera

Claude Code 向けの自己学習プラットフォーム。

会話の中で学んだことを自然言語で蓄積し、次の対話で自然に再会する。
野口悠紀雄『超』勉強法 (面白い・全体から・8 割) と精緻化 / 体制化を実装したもの。

## 何ができるか

- **入力**: 「これメモ」「覚えといて」「同じミスしたくない」と言うだけで蓄積される
- **蓄積**: 構造化 Markdown として `~/kakera/knowledge/` に保存。Obsidian 不要、`cat` / `grep` で読める
- **再会**: 次の session で関連する話題が出たら Claude が自然に想起
- **育成**: `/kakera-review` で 8 割止めの問いや鮮度切れノートを点検

## インストール

### A. Claude Code marketplace 経由

```
/plugin marketplace add nayukata/kakera
/plugin install kakera
/kakera-init
```

### B. install.sh 経由

```sh
git clone https://github.com/nayukata/kakera.git
cd kakera
./install.sh
```

install.sh が完了後の `次のステップ` を表示するのでそれに従う。

## 使い方

### 1. 普段の対話で

```
ユーザー: 今日 Postgres の RLS で詰まった。row_security ON にしてもポリシー定義してないと
        全行返らないのか。これ罠だな、覚えといて
Claude:   mistakes/ に保存しました: `2026-05-19_RLSはポリシー無しだと全行ブロック.md`
```

### 2. 過去の判断を引きたい時

```
ユーザー: 前にこのフレームワーク選んだ理由って何だっけ
Claude:   (kakera を検索)
         以前 [[2026-03-12_状態管理にZustandを選定]] でこう判断しています:
         - Redux は学習コスト過大、Recoil は実験的
         - Zustand は API が単純で SSR に強い
         今回も同じ要件ですか?
```

### 3. 育てたい時

```
/kakera-review

# 今週の復習キュー
## 未解決の問い (3 件)
- 8 割止めだった疑問が並ぶ
## 鮮度切れ (1 件)
## 昇格候補 (2 件)
```

## 設計思想

### 入力摩擦ゼロ

別ツールを開かない、タグを選ばない、フォルダを指定しない。
自然言語のトリガー語 (「これメモ」「覚えといて」等) を Claude が検知して保存する。
カテゴリも Claude が文脈から判断する。

### 受動再会を主軸

「育成」フェーズで `REVIEW.md` を見に行く義務化は続かない。
Claude が次回 session で関連知見を自然に想起する方が UX 的に強い。
能動レビュー (`/kakera-review`) はオプション扱い。

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
