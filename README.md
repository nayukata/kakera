# kakera

Claude Code 向けの長期記憶 + 学習ツール。

会話の中で学んだことを残しておくと、次の対話で Claude が自分から思い出す。
保留した疑問は `/kakera-study` で対話的に深掘りして、自分の理解として定着させる。

## 何ができるか

- **メモる**: 「これメモ」「覚えといて」と話すだけで Markdown ファイルに保存される
- **思い出す**: 次の session で関連する話題が出たら Claude が自分から引用する
- **学ぶ**: 保留した問いを `/kakera-study` で 1 件ずつソクラテス式に対話。Claude は答えを先に出さず、ユーザーが自分の言葉で書いたら過去メモと照合して補強する
- **整える**: 古いメモを最新化、よく使うメモを永続化。`/kakera-review` で一覧

保存先は `~/kakera/knowledge/`。ただのテキストファイルなので Obsidian なしでも `cat` / `grep` で読める。

## なぜこの設計か

### 思い出す側を Claude に任せる

「定期的に過去のメモを見返す」って続かない。だから受け側を全部 Claude に寄せる。
session が始まると Claude が過去のメモを自分で見に行って、関連する話題が出たら自分から引用する。
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
| 重複 | 既存とほぼ同じ | 新規作成しない。日付だけ追記 |
| 更新 | 既存をより一般化 / 反例 | 既存を編集する |
| 新規 | 既存の前提を覆す | 新規 + 双方向リンク |

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

### 学習を定着させる仕掛け

ただ書いて終わらせない。心理学でいう **精緻化** (既知と関連付ける) と **体制化** (カテゴリで束ねる)、それと **メタ認知** (自分の理解度の可視化) を機能側で自動化する。

- **保留した問いは 1 ヶ月以内に再訪**: `questions/` のメモは `decay: 1month` で `/kakera-study` のリストに浮上する。忘れる前に答えに戻る
- **答えは自分の言葉で**: `/kakera-study` で Claude は答えを先に出さない。ユーザーが書いてからフィードバックする (流暢性の錯覚を破る)
- **何度も使ったメモは永続化**: `references` 3 件で自動 `permanent` 昇格。繰り返しが記憶を強化する
- **新情報は既存と関連付けて保存**: Surprise 判定で重複/更新/新規を判断。既知のネットワークに編み込む
- **同テーマは束ねる**: 3 件溜まるとサブ hub が自動形成される

### 同じ罠を踏まない仕掛け = ガードレール追加のサイン

`mistakes/` のノートには `recurrence` (再発回数) と `last_hit` (最後に踏んだ日) が記録される。
同じ罠を再保存しようとしたら、新規ノートを作らず既存の `recurrence` を +1 する (Surprise の重複判定を mistakes 用に強化したもの)。

| recurrence | Claude の動き |
|---|---|
| 1 | 通常通り保存 |
| 2 | 「これは過去の `[[X]]` と同じパターン。次回踏まないために対策ある?」 |
| 3 以上 | 「これは N 回目。根本対策を `decisions/` に書きませんか?」と能動提案 |

**3 回踏んだ罠は個人の注意では防げない**。これは「気をつけよう」で終わらせず、**ガードレール** (lint ルール / 型シグネチャ / テスト / CI チェック / デフォルト値変更 / コードコメント / レビュー観点) を追加すべきサイン。

ガードレールの利点
- 自分も他人もハマらなくなる (個人記憶に依存しない)
- 知識の属人化を防ぐ
- 「同じ罠で時間を溶かす」のが構造的に止まる

`decisions/` に「なぜそのガードレールを入れたか」を残しておけば、将来の保守者が外す時に踏み直しを防げる。

session 開始時に `recurrence ≥ 3` の罠があれば Claude が先に「この領域、過去 N 回踏んでます」と注意喚起する。
ユーザーが「またこれだ」「前にもあった」と発話するだけでも検出が走る。

### コーチモード (理解度チェック)

Claude が対話の中で「ユーザーの理解の怪しさ」を検出して問いかける。
曖昧な言い回し / 過去判断との不整合 / 用語を借りているだけ / 結論が飛んでる のような兆候を見つけたら

```
「ここの理解、ちょっと確認させて。〜って、どういう仕組み?」
```

と問う。答えられたら OK、詰まったら `questions/` に保留して `/kakera-study` 的に深掘りする。

- 1 session で 2-3 回まで (うるさくしない)
- 「いいから答えだけ」「それは飛ばして」で session 内 off
- 連続 3 セッション off にしたら「恒久 off にする?」と確認
- `/kakera-coach` で手動 on/off。`/kakera-coach on` で復活

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

言い方の例

| 言い方 | 保存先 |
|---|---|
| 「これメモ」「覚えといて」 | Claude が文脈で判断 |
| 「同じミスしたくない」「これ罠だった」 | `mistakes/` |
| 「あとで調べたい」「先に進めたい」 | `questions/` |
| 「次回からこう判断する」 | `feedback/` / `design/` |
| 「この決定の理由を残したい」 | `decisions/` |

```
ユーザー: 今日 Postgres の RLS で詰まった。row_security ON にしてもポリシー定義してないと
        全行返らないのか。これ罠だな、覚えといて
Claude:   mistakes/ に保存しました: 2026-05-19_RLSはポリシー無しだと全行ブロック.md
```

### 3. 過去の判断を引きたい時

ユーザーが「前に〜」「以前〜」と言うと Claude が検索する。明示的に呼ぶ場合は `/kakera-search <query>` を使う。
引数なしでリスト、曖昧キーワードでもファジー検索が効く。

```
ユーザー: 前にこのフレームワーク選んだ理由って何だっけ
Claude:   (kakera を検索)
         以前 [[2026-03-12_状態管理にZustandを選定]] でこう判断してました:
         - Redux は学習コスト過大、Recoil は実験的
         - Zustand は API が単純で SSR に強い
         今回も同じ要件ですか?
```

### 4. 学びたい時 (保留した問いを解く)

`/kakera-study` で保留中の問いを 1 件選んで対話。Claude は答えを先に出さず、ユーザーが自分の言葉で書くまで待つ。

```
> /kakera-study
未解決の問い (3 件)
1. RLS のポリシー無し挙動を整理したい  (1 ヶ月前に保留)
2. Recoil の atom 永続化のベストプラクティス  (3 日前)
3. pgBouncer の transaction モード解除タイミング  (1 週間前)
どれにしますか?

> 1
## 問い
RLS のポリシー無し挙動を整理したい

今ならどう考える? まず自分の言葉で書いてみて。

> row_security ON はポリシーが「ある」前提のフラグ。
> ポリシー未定義テーブルは全行ブロック (空集合) を返す。

そうですね。ただし superuser や BYPASSRLS 持ちはこのブロックを通り抜けます。
これは [[2025-11-02_superuserでRLS無視]] の前提と整合します。
…
```

引数で絞ることもできる: `/kakera-study Postgres` → 候補を絞って提示、1 件なら直行。

### 5. 整えたい時 (Vault のメンテ)

`/kakera-review` で古くなったメモと昇格候補を一覧する。学習対話 (問いの再訪) はここでは扱わない。

```
> /kakera-review

# 今週のメンテキュー
## 鮮度切れ (1 件)
- [[2025-08-30_GraphQL のキャッシュ戦略]] (6months 超過)

## 昇格候補 (2 件)
- [[エラーは原因と再発防止セットで]] (references 4 件)
- [[PR 説明文の書き方]] (references 3 件)
```

### 6. 読んだ本から学びたい時

`/kakera-book <書名>` で 6 ステップ対話 (壁メッセージ → 響いた → なぜ → 今の自分 → 詰まり → 古い前提) 。1 セッション = 1 気付きが原則。

```
> /kakera-book チーズはどこに消えた

『チーズはどこに消えた』の主要メッセージ:
- 変化は必ず起こる
- 変化を予期せよ
- ...

どれが今のあなたに刺さりますか?

> 「変化に備えて、楽しもう」

そのメッセージ、なぜ今のあなたに響くんですか?

> ...
```

得た気付きは適切なカテゴリ (feedback / design / decisions 等) に保存され、frontmatter に `source: book/<書名>` が残る。あとから「あの本から何学んだっけ」で引ける。

## インストール

### A. Claude Code marketplace 経由

```
/plugin marketplace add nayukata/kakera
/plugin install kakera
/kakera-init
```

更新は `/plugin marketplace update kakera` してから `/plugin update kakera`。

### B. install.sh 経由 (Claude Code 以外も対応)

```sh
git clone https://github.com/nayukata/kakera.git
cd kakera
./install.sh
```

install.sh が `~/.claude` / `~/.codex` を検出して、それぞれに合う hook 登録手順を案内する。

### C. Codex で使う場合

Codex は Claude Code 互換の skill 仕様と AGENTS.md (= CLAUDE.md と同内容) を読む。
B の install.sh が出す案内に従って `~/.codex/config.toml` に Stop hook を登録するか、手動で以下を追記する。

```toml
[[hooks.Stop]]
command = "/path/to/kakera/hooks/codex/on-stop.sh"
```

制約

- Codex には SessionEnd 相当が無いため Stop (ターン終了) で代替している
- Stop は毎ターン発火するので内部で debounce (default 300 秒) を噛ませている
- 抽出は `codex exec` を経由する (Claude Code 版は `claude -p`)

### D. その他のエージェント (Cursor / Gemini CLI / Cline / Codex 等)

skill 本体は `skills` CLI (vercel-labs/skills) 経由で配布できる。30 以上のエージェントを横断対応。

```sh
npx skills add nayukata/kakera
```

エージェント別の skill 配置先

| エージェント | グローバル | プロジェクト |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| Codex | `~/.codex/skills/` | `.agents/skills/` |
| Cursor | `~/.cursor/skills/` | `.agents/skills/` |
| Gemini CLI | `~/.gemini/skills/` | `.agents/skills/` |
| Cline | エージェント側設定 | `.agents/skills/` |

agent rule は `AGENTS.md` (= `CLAUDE.md`) を各エージェントの規約パスへ配置するかルートに置けば多くのエージェントが拾う。

自動抽出 hook は Claude Code (`SessionEnd`) / Codex (`Stop`) / Cursor (`sessionEnd`) に対応。それ以外は skill (`/kakera-search` `/kakera-study` 等) の明示呼び出しで運用する。

## ディレクトリ構造

```
$KAKERA_HOME/
├── MEMORY.md            # 目次
├── INDEX.md             # 全ノート 1 行サマリ (検索の入口、自動生成)
├── RECENT.md            # 直近 30 件の新着リスト (ブラウズ用、自動生成)
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
| `/kakera-search [--in <category>] <query>` | メモの検索 (INDEX を先読みして候補絞り込み、ファジー / 自然文 / カテゴリ縛り対応) |
| `/kakera-study <query>` | 保留した問いを 1 件解く対話。引数なしでリスト、曖昧キーワードで絞り込み |
| `/kakera-review` | 古くなったメモ・昇格候補のメンテ。学習対話はしない |
| `/kakera-coach [on\|off]` | コーチモードの on/off 切り替え。引数なしで反転 |
| `/kakera-book <書名>` | 読書の気付きを 6 ステップ対話で kakera に保存 |

## hook

| エージェント | hook | 発火タイミング | 抽出 CLI |
|---|---|---|---|
| Claude Code | `hooks/on-session-end.sh` | SessionEnd (session 終了時) | `claude -p` |
| Codex | `hooks/codex/on-stop.sh` | Stop (ターン終了時、debounce 付き) | `codex exec` |
| Cursor | `hooks/cursor/on-session-end.sh` | sessionEnd | `claude -p` または `codex exec` (PATH から検出) |

session / ターンが終わるとエージェント CLI を非同期で起動し、transcript を読んで自動抽出する。Cursor 自体には非対話 prompt CLI が無いため、claude / codex のいずれかが必要。`KAKERA_AGENT_CMD` で明示指定も可能。

## 依存

- エージェント CLI (`claude` or `codex`)
- `jq`
- `python3`
- `rg` (検索用、無くても動くけど遅い)

## ライセンス

MIT
