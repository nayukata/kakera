---
name: kakera-coach
description: コーチモードの on/off を切り替える。コーチモードが on の時、Claude は対話の中でユーザーの理解の怪しさを検出して問いかける (メタ認知支援)。off にすると問いかけ無しで答えだけ返す。引数なしで状態反転、on / off の明示も可。$KAKERA_HOME/.kakera-config.toml の [study] enabled を書き換える。
argument-hint: "[on|off] -- 省略時は現在値を反転"
---

# kakera-coach

## 目的

「Claude が会話の途中で問いかけてくる」コーチモードのスイッチ。

コーチモードが on の時、Claude はユーザーの発話に怪しさを検出すると「ここの理解、確認させて」と問いかける。
off の時は通常通り答えだけ返す。

検出シグナルや問いかけの挙動は CLAUDE.md の「コーチモードプロトコル」セクションに定義されている。
このスキルは状態切り替えのみを担う。

## 実行手順

### 1. 設定ファイル確定

`$KAKERA_HOME/.kakera-config.toml` を確認。無ければ `/kakera-init` を案内して exit。

### 2. 現在値の読み取り

`[study]` セクションの `enabled` を読む。未設定なら default `true` とする。

### 3. 新しい値の決定

| 引数 | 動作 |
|---|---|
| なし | 現在値を反転 |
| `on` / `enable` / `true` | true に固定 |
| `off` / `disable` / `false` | false に固定 |
| 同じ値の指示 | 「既に X です」とだけ報告して exit |

### 4. 書き戻し

`.kakera-config.toml` の `[study]` セクションに `enabled = <新値>` を書き込む。
同セクションの `off_streak` カウンタは

- on にした時: 0 にリセット
- off にした時: そのまま (連続 off 検出に使う)

セクションが無ければ新規作成。

### 5. 報告

```
コーチモード: on → off に切り替えました
```

同じ値だった場合

```
コーチモード: 既に on です
```

### 6. off にした時の補足

ユーザーに「次回の session で復活するわけではないので、戻したい時は `/kakera-coach on`」と一言添える。
これは恒久 off であり、session 内 off (「いいから答えだけ」) とは別物。

## 設定ファイルの構造

```toml
[study]
enabled = true       # コーチモード on/off
off_streak = 0       # 連続 off カウント (CLAUDE.md 側で更新)
```

## 禁止事項

- `.kakera-config.toml` の他セクション (`[vault]` `[recall]` `[obsidian]` 等) は触らない
- 確認なしに `[study]` セクション自体を削除しない
