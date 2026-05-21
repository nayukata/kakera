---
name: kakera-organize
description: kakera Vault の重複・近接ノートを Claude が分析して 1 画面レポートで提示、ユーザーは multiSelect で承認ペアだけ選ぶ → Claude が一括実行する整理 skill。/kakera-review が機械的キューを出すのに対し、/kakera-organize は判断と実行を伴う整理対話を担当する。マージ / 並存+区別 / 親子関係化 (サブ hub 化) / カテゴリ移動を扱う。
argument-hint: "[query] -- 省略時は重複候補の sim 降順 top 4 から"
---

# kakera-organize

## 目的

重複候補ノートを Claude が分析して 1 画面のレポートで提示し、ユーザーは AskUserQuestion (multiSelect=true) で承認ペアを選ぶだけ。判断負荷を最小化しつつ、整理操作を一括で実行する。

## 実行手順

### 1. 候補収集

- `$KAKERA_HOME/REVIEW.md` の「重複候補」セクションを Read
- 0 件なら `bin/review-queue.py` を実行して最新化
- 引数 query があれば候補をタイトル / description でファジー絞り込み
- sim 降順で上位 4 件まで取得 (AskUserQuestion の option 上限のため)。5 件超なら 2 ラウンドに分割

### 2. ペア分析 (各ペアごと)

両ノートの **description のみ** を Read し (本文は推奨アクション決定後に必要なら参照)、以下を評価:

- **重なり**: 何が同じか (1 文)
- **違い**: 何が別か (1 文)
- **関連示唆**: 他ノートとの関係 / 親子関係の有無 / カテゴリ越境の有無 (1 文)

評価から推奨アクションを決定:

| シグナル | 推奨アクション |
|---|---|
| description ほぼ同義、本文も近い | マージ (importance / decay が強い方をベース) |
| 対概念として互いに参照しあっている (関連 / 対比 が書かれている) | 並存 + 区別を明示 |
| A が B を包含する親概念 | 親子関係化 (A と同名サブフォルダを作り B をそこへ) |
| 一方が固有名詞シグナル多数 | カテゴリ移動 (project/<name>/ 等) |
| frontmatter `name` が英 snake_case で他は日本語 | name 揃え (フォルダ命名ルールに合わせる) |
| 本文が `**Why:**` `**How to apply:**` ラベル付きの段落だけ | 体裁リッチ化 (callout + 表 + mermaid に書き直す、AGENTS.md の推奨構造を参照) |
| description に機械検索語 (固有名詞 / エラー語 / 技術名 / 作業種別) が無い | description 補強 (AGENTS.md 「description 規約」参照、recall ヒット率を上げる) |
| 判断不能 / 現状で完成している | スキップ (multiSelect には**載せない**) |

### 3. レポート 1 画面提示

```
[1/N] A vs B  推奨: <アクション名>
  A desc: <description>
  B desc: <description>
  評価:
    - 重なり: ...
    - 違い: ...
    - 関連示唆: ...
  実行する操作: <具体 (どのファイルを Edit / 削除 / 移動するか、inbound wikilink 張替えの有無)>
```

これを候補数分まとめて表示。

### 4. multiSelect で承認

AskUserQuestion(multiSelect=true) で承認ペアを選ばせる:

- options[i].label: 「N. A↔B (<アクション名>)」
- options[i].description: 推奨アクションの 1 行サマリ
- **スキップ推奨ペアは options に載せない**。判断 slot を無駄にしない
- 代わりに「現状で完成しているノート: N 件」とレポート末尾に件数のみ表示

ユーザーがチェックした分だけ採用。

### 5. 一括実行

承認されたペアそれぞれについて推奨アクションを実行:

- **マージ**: ベースノートを Edit (本文統合 / references 結合 / decay は permanent 寄りに統一) → 他方を削除 → inbound wikilink を grep してベース側に張替え
- **並存 + 区別**: 両ノートに `## 区別` セクションを追加 (どこが違うか) + 双方向 wikilink
- **親子関係化**: 親ノートと同名のサブフォルダを作成 → 親ノート自体もサブフォルダ内に移動 → 子ノートを同サブフォルダへ移動 → 子の戻る link を親に書き換え → 親の frontmatter を **必ず** 自動で `type: sub-hub` に変更し、`name` も日本語タイトル (フォルダ名) に揃える (英 snake_case `user_xxx` 等が残っていたら更新) → 親の `## メンバー` セクションを初期化 (`regen-hubs.py` は親 hub の子としてサブ hub を表示するだけで、サブ hub 内のメンバーリストは触らないため手動初期化が必要)
- **name 揃え**: frontmatter `name` がファイル名 (日本語タイトル) と不一致なら、`name` をファイル名に合わせて Edit。inbound wikilink は実ファイル名で張られているのでリンク切れは起きないが、検索一貫性のため揃える
- **カテゴリ移動**: 該当ノートを target カテゴリへ git mv 相当で移動 → `type` frontmatter を更新 → inbound wikilink は名前変わらないので張替え不要だが、戻る link は更新
- **description 補強**: 該当ノートの frontmatter `description` を Edit。カテゴリに応じて以下の語を 1 つ以上含める (project: 案件名 / ライブラリ固有名、mistakes: エラー文の特徴語 / 関数名 / file path、design: 技術名 / パターン名、feedback: 作業種別)。意味は変えず、grep ヒット用の語を追加するだけ

### 6. dead link 検証

実行後、削除 / 移動したノートに対する dead wikilink が残っていないか grep でチェック。残っていれば警告として報告。

### 7. 完了報告 + 次ラウンド

- 処理件数 (マージ N / 並存 N / 親子化 N / カテゴリ移動 N / dead link 警告 N) を 1 行で
- 残候補があれば「次ラウンドに進みますか?」と問う

## 禁止事項

- 確認なしにノートを削除しない (multiSelect での明示承認必須)
- マージ時に元ノートの主要記述を捨てない (frontmatter の created / references は必ず統合)
- inbound wikilink を放置して dead link を作らない
- 推奨アクションの根拠が薄い時に「マージ」を選ばない (迷ったら「並存 + 区別」が安全)
- multiSelect は 1 ラウンドで 4 件まで (AskUserQuestion 上限)。5+ 件あれば必ず分割
