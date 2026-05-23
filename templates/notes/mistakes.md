---
name: YYYY-MM-DD_<日本語タイトル>
description: <一行要約。エラー文の特徴語 / 失敗対象の関数名 / ファイルパスを含める>
type: mistake
importance: high | medium | low
created: YYYY-MM-DD
decay: 3months | 6months | permanent
recurrence: 1
last_hit: YYYY-MM-DD
references:
  - YYYY-MM-DD: <発生時の状況 (transcript の事実のみ)>
---

> [!danger] 失敗の要旨
> <1-2 行で「何を間違えたか」を率直に書く>

## 事象

<何をしようとして / 何が起きたか。再現できるレベルで>

## なぜそうなったか — 根本原因

<表層原因ではなく、構造的・思考的原因を書く>

- <原因 1>
- <原因 2>

## 再発防止

<具体的なガードレール。「気をつける」は禁止、検証可能な対策を書く>

- [ ] <対策 1 (lint / 型 / テスト / CI / レビュー観点 等)>
- [ ] <対策 2>

> [!warning] 再発の兆候
> <次に同じパターンに踏み込みそうな時のシグナル>

## 関連

- [[<関連ノート名>]] — <なぜ関連するか>
