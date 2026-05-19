# kakera

Claude Code 向けの長期記憶ツール。

会話の中で出てきた学びを残しておくと、次の対話で勝手に思い出してくれる。

## 何ができるか

- **メモる**: 「これメモ」「覚えといて」と話すだけで Markdown ファイルに保存される
- **思い出す**: 次の session で関連する話題が出たら Claude が自分から引いてくる
- **育てる**: `/kakera-review` で「あとで調べる」と保留したやつを後追いできる

保存先は `~/kakera/knowledge/` で、ただのテキストファイル。Obsidian なしでも `cat` / `grep` で読める。

## なぜこの設計か

### 思い出す側を Claude に任せる

「定期的に過去のメモを見返す」って続かない。だから受け側を全部 Claude に寄せる。
session が始まったら関連の hub note を黙って読み込んでおいて、話の流れで `[[X]]` と参照する。
ユーザーは何もしなくていい。`/kakera-review` で能動的に見ることもできるけど、そこに頼らない設計。

### 保存は普通の会話で

slash command を覚えなくていい。「これメモ」「覚えといて」みたいな普通の発話で動く。
ただし黙ってメモを取ったりはしない。ユーザーが言わない限り保存されない。
カテゴリは Claude が文脈で決めるので、フォルダもタグも選ばなくていい。

### Obsidian は使っても使わなくてもいい

全部ただの Markdown ファイル。Obsidian で graph view を眺めるのもいいし、ターミナルで `rg` するだけでもいい。
どっちで運用しても同じものが見える。

### 似たメモを増やさない仕組み

新しい話題が出てきた時、既存のメモとの関係を 3 つに分けて扱う。

| 種別 | 条件 | 動作 |
|---|---|---|
| かぶり | 既存とほぼ同じ | 新規作成しない。日付だけ追記 |
| 上書き | 既存をより一般化 / 反例 | 既存を編集する |
| 別物 | 既存の前提を覆す | 新規 + 双方向リンク |

同じ話をするノートが増えない。矛盾は両方残るので後から辿れる。
(元ネタは A-MEM / Titans の memory surprise 判定。)

### 古くなるメモには有効期限

| `decay` 値 | 想定 |
|---|---|
| `permanent` | 哲学・原則。減衰しない |
| `6months` | アーキ判断・技術選定 |
| `3months` | プロジェクト固有 |
| `1month` | 暫定対応、保留中の問い |

何度も再確認されたメモ (references 3 件以上) は自動で `permanent` に昇格する。

## 使い方

### 1. session が始まった時 (自動)

ユーザーが最初に話題を出した時点で Claude が裏で `knowledge/` を見る。何もしなくていい。

```
ユーザー: Postgres の接続プールでまた詰まってる
Claude:   (knowledge/mistakes と decisions を確認)
         [[2026-03-15_pgBouncerはtransactionモードで]] でこの問題やってますね。
         transaction モードに切り替えた経緯がありますが、また再発ですか?
```

### 2. メモを残したい時

トリガーになる発話例

| 言い方 | しまう先 |
|---|---|
| 「これメモ」「覚えといて」 | Claude が文脈で判断 |
| 「同じミスしたくない」「これ罠だった」 | `mistakes/` |
| 「あとで調べたい」「今は 8 割で進める」 | `questions/` |
| 「次回からこう判断する」 | `feedback/` / `design/` |
| 「この決定の理由を残したい」 | `decisions/` |

```
ユーザー: 今日 Postgres の RLS で詰まった。row_security ON にしてもポリシー定義してないと
        全行返らないのか。これ罠だな、覚えといて
Claude:   mistakes/ に保存しました: 2026-05-19_RLSはポリシー無しだと全行ブロック.md
```

### 3. 過去の判断を引きたい時

ユーザーが「前に〜」「以前〜」と言うと Claude が検索する。明示的に呼ぶなら `/kakera-search <query>`。

```
ユーザー: 前にこのフレームワーク選んだ理由って何だっけ
Claude:   (kakera を検索)
         以前 [[2026-03-12_状態管理にZustandを選定]] でこう判断してました:
         - Redux は学習コスト過大、Recoil は実験的
         - Zustand は API が単純で SSR に強い
         今回も同じ要件ですか?
```

### 4. 育てたい時

```
/kakera-review

# 今週の復習キュー
## 未解決の問い (3 件)
- 8 割で止めた疑問が並ぶ
## 古くなった (1 件)
## 昇格候補 (2 件)
```

## インストール

### A. Claude Code marketplace 経由

```
/plugin marketplace add nayukata/kakera
/plugin install kakera
/kakera-init
```

更新は `/plugin marketplace update kakera` してから `/plugin update kakera`。

### B. install.sh 経由

```sh
git clone https://github.com/nayukata/kakera.git
cd kakera
./install.sh
```

install.sh が終わると「次のステップ」を出すので、それに従う。

## ディレクトリ構造

```
$KAKERA_HOME/
├── MEMORY.md            # 目次
├── REVIEW.md            # 復習キュー (週次自動生成)
├── .kakera-config.toml  # 設定ファイル
└── knowledge/
    ├── decisions/   # 技術選定・方針決定
    ├── mistakes/    # エラー・修正指示
    ├── feedback/    # 行動ガイドライン
    ├── design/      # 設計原則
    ├── project/     # プロジェクト固有
    ├── user/        # ユーザー背景
    └── questions/   # 保留中の問い
```

同じテーマのメモが 3 件以上溜まると、Claude が自動でサブフォルダを作って束ねる。
例: `design/長期記憶設計/MemoryEvolutionで知見を育てる.md`

## 環境変数

| 変数 | default | 説明 |
|---|---|---|
| `KAKERA_HOME` | `~/kakera` | Vault の場所 |

## skill

| skill | 用途 |
|---|---|
| `/kakera-init` | 初回セットアップ |
| `/kakera-search <query>` | メモの全文検索 + 要約 |
| `/kakera-review` | 復習キュー生成 + 1 件ずつ対話で処理 |

## hook

`hooks/on-session-end.sh` を Claude Code の SessionEnd hook に登録すると、session が終わるたびに Claude が transcript を読んで自動抽出する (バックグラウンドで動く)。

## 依存

- Claude Code CLI (`claude`)
- `jq`
- `python3`
- `rg` (検索用、無くても動くけど遅い)

## ライセンス

MIT
