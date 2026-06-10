#!/usr/bin/env python3
"""kakera Vault の検索/ブラウズ用インデックスを生成する。

- `INDEX.md` (機械向け): 全ノートを 1 行サマリにしてカテゴリ別に並べる。`/kakera-search` が先頭で Read する
- `RECENT.md` (人間向け): 直近の活動 (latest reference または created) の新しい順にトップ N 件

両方を 1 回の走査で生成。Vault パスは KAKERA_HOME 環境変数で解決。
"""

from __future__ import annotations

import os
import re
import sys
from datetime import date, datetime
from pathlib import Path

VAULT = Path(os.environ.get("KAKERA_HOME", str(Path.home() / "kakera")))
KNOWLEDGE = VAULT / "knowledge"
INDEX_PATH = VAULT / "INDEX.md"
RECENT_PATH = VAULT / "RECENT.md"
BROKEN_PATH = VAULT / "BROKEN.md"
RECENT_LIMIT = 30

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
WIKILINK_RE = re.compile(r"\[\[([^\]\|#]+)(?:[|#][^\]]*)?\]\]")
INLINE_CODE_RE = re.compile(r"`[^`]*`")
FENCE_RE = re.compile(r"```")
TOP_LEVEL_MDS = ("INDEX.md", "RECENT.md", "MEMORY.md", "REVIEW.md", "BROKEN.md")

IMPORTANCE_WEIGHT = {"high": 3, "medium": 2, "low": 1}

CATEGORY_ORDER = [
    "decisions",
    "mistakes",
    "feedback",
    "design",
    "project",
    "user",
    "questions",
]


def parse_frontmatter(text: str) -> dict:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    fm: dict = {}
    current = None
    for line in m.group(1).splitlines():
        if line.startswith("  -"):
            if current:
                fm.setdefault(current, []).append(line[3:].strip())
            continue
        current = None
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        k, v = k.strip(), v.strip()
        if not v:
            current = k
        else:
            fm[k] = v.strip('"').strip("'")
    return fm


def latest_ref(fm: dict) -> date | None:
    refs = fm.get("references", [])
    if isinstance(refs, str):
        refs = [refs]
    dates = []
    for r in refs:
        m = DATE_RE.search(r)
        if m:
            try:
                dates.append(datetime.strptime(m.group(), "%Y-%m-%d").date())
            except ValueError:
                pass
    if dates:
        return max(dates)
    created = fm.get("created", "")
    m = DATE_RE.search(str(created))
    if m:
        try:
            return datetime.strptime(m.group(), "%Y-%m-%d").date()
        except ValueError:
            pass
    return None


def collect_by_category() -> dict[str, list[tuple[str, dict, Path]]]:
    by_cat: dict[str, list[tuple[str, dict, Path]]] = {c: [] for c in CATEGORY_ORDER}
    for md in KNOWLEDGE.rglob("*.md"):
        text = md.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        # hub と sub-hub は除外 (それ自体は検索対象でない)
        if fm.get("type") in ("hub", "sub-hub"):
            continue
        # トップカテゴリを path から推定
        try:
            rel = md.relative_to(KNOWLEDGE)
        except ValueError:
            continue
        category = rel.parts[0] if rel.parts else "other"
        if category not in by_cat:
            by_cat.setdefault(category, [])
        by_cat[category].append((md.stem, fm, rel))
    return by_cat


def sort_key(item: tuple[str, dict, Path]) -> tuple:
    name, fm, _ = item
    importance = str(fm.get("importance", "low"))
    weight = IMPORTANCE_WEIGHT.get(importance, 0)
    last = latest_ref(fm) or date(1970, 1, 1)
    return (-weight, -last.toordinal(), name)


def truncate(text: str, n: int) -> str:
    text = str(text).replace("\n", " ").replace("|", "/").strip()
    return text[:n] + ("…" if len(text) > n else "")


def write_index(by_cat: dict, today_str: str) -> int:
    lines = [
        "---",
        "name: INDEX",
        "description: 全ノートのサマリ。検索時の入口。自動生成。",
        f"updated: {today_str}",
        "---",
        "",
        "# kakera INDEX",
        "",
        "`/kakera-search` はまずこのファイルを Read して候補を絞り込む。1 ノート 1 行のサマリ。",
        "",
    ]

    total = 0
    for cat in list(CATEGORY_ORDER) + [c for c in by_cat if c not in CATEGORY_ORDER]:
        items = by_cat.get(cat, [])
        if not items:
            continue
        items.sort(key=sort_key)
        lines.append(f"## {cat}/ ({len(items)} 件)")
        lines.append("")
        lines.append("| ノート | 重要度 | decay | 概要 |")
        lines.append("|---|---|---|---|")
        for name, fm, _rel in items:
            importance = str(fm.get("importance", "?"))
            decay = str(fm.get("decay", "?"))
            desc = truncate(str(fm.get("description", "")), 60)
            lines.append(f"| [[{name}]] | {importance} | {decay} | {desc} |")
            total += 1
        lines.append("")

    lines.append(f"_対象ノート: {total} 件_")
    INDEX_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return total


def write_recent(by_cat: dict, today_str: str) -> int:
    # 全ノートをフラットにして latest_ref or created でソート
    flat: list[tuple[date, str, str, dict]] = []  # (sort_date, name, category, fm)
    for cat, items in by_cat.items():
        for name, fm, _rel in items:
            d = latest_ref(fm) or date(1970, 1, 1)
            flat.append((d, name, cat, fm))
    flat.sort(key=lambda x: (-x[0].toordinal(), x[1]))

    lines = [
        "---",
        "name: RECENT",
        "description: 直近に追加 / 更新されたノート 上位 30 件。ブラウズ用、自動生成。",
        f"updated: {today_str}",
        "---",
        "",
        "# 直近のメモ",
        "",
        "最後に触れた (新規作成 or references 追記) 順。新着の見落とし防止。",
        "",
        "| 日付 | ノート | カテゴリ | 概要 |",
        "|---|---|---|---|",
    ]

    for d, name, cat, fm in flat[:RECENT_LIMIT]:
        date_str = d.isoformat() if d.year > 1970 else "?"
        desc = truncate(str(fm.get("description", "")), 60)
        lines.append(f"| {date_str} | [[{name}]] | {cat} | {desc} |")

    RECENT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return min(RECENT_LIMIT, len(flat))


def collect_actual_names() -> set[str]:
    """Vault 内の全 .md ファイル名 (拡張子なし) を集める。BROKEN.md 自身は除外。"""
    names: set[str] = set()
    for md in VAULT.rglob("*.md"):
        if ".obsidian" in md.parts:
            continue
        if md.name == "BROKEN.md":
            continue
        names.add(md.stem)
    return names


def find_dangling(actual: set[str]) -> list[tuple[Path, int, str, str]]:
    """inline code / fenced code の外で実ファイル名と一致しない wikilink を検出する。

    返り値: (path, line_no, link_name, line_excerpt) のリスト。
    """
    targets: list[Path] = list(KNOWLEDGE.rglob("*.md"))
    for name in TOP_LEVEL_MDS:
        p = VAULT / name
        if p.exists() and name != "BROKEN.md":
            targets.append(p)

    hits: list[tuple[Path, int, str, str]] = []
    for f in targets:
        try:
            lines = f.read_text(encoding="utf-8").splitlines()
        except Exception:
            continue
        in_fence = False
        for i, line in enumerate(lines, 1):
            if FENCE_RE.search(line):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            stripped = INLINE_CODE_RE.sub("", line)
            for m in WIKILINK_RE.finditer(stripped):
                name = m.group(1).strip()
                if name not in actual:
                    excerpt = line.strip()[:120]
                    hits.append((f, i, name, excerpt))
    return hits


def write_broken(hits: list[tuple[Path, int, str, str]], today_str: str) -> int:
    """ダングリングが 0 件なら BROKEN.md を消し、1 件以上なら書き出す。

    リンク名ごとに集約して原因切り分け (rename 漏れ / mistakes prefix 忘れ / typo) しやすくする。
    """
    if not hits:
        if BROKEN_PATH.exists():
            BROKEN_PATH.unlink()
        return 0

    by_name: dict[str, list[tuple[Path, int, str]]] = {}
    for path, ln, name, excerpt in hits:
        by_name.setdefault(name, []).append((path, ln, excerpt))

    lines = [
        "---",
        "name: BROKEN",
        "description: 実ファイルに解決しない wikilink の一覧。0 件になるよう直す。",
        f"updated: {today_str}",
        "---",
        "",
        "# 壊れた wikilink",
        "",
        "次の `[[X]]` は実ファイル名と一致しない。`bin/build-index.py` が SessionEnd で再生成する。0 件になればこのファイルは自動削除される。",
        "",
        "## 直し方の見立て",
        "",
        "- mistakes/ ノートを参照していて prefix 欠落 → `[[2026-MM-DD_xxx]]` に書き換え",
        "- ノートを rename した残骸 → 新ファイル名に置換",
        "- placeholder (説明文中の `[[name]]` 等) → バッククォートで囲んで非リンク化",
        "- 存在しないノートを書こうとした → そのノートを実体作成するか、リンクを外す",
        "",
        f"## 検出 ({len(hits)} 箇所 / {len(by_name)} 種類)",
        "",
    ]
    for name in sorted(by_name):
        occs = by_name[name]
        lines.append(f"### `[[{name}]]` ({len(occs)} 箇所)")
        lines.append("")
        for path, ln, excerpt in occs:
            try:
                rel = path.relative_to(VAULT)
            except ValueError:
                rel = path
            lines.append(f"- `{rel}:{ln}` — {excerpt}")
        lines.append("")

    BROKEN_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(hits)


def main() -> int:
    if not KNOWLEDGE.exists():
        print(f"knowledge dir not found: {KNOWLEDGE}", file=sys.stderr)
        return 1

    by_cat = collect_by_category()
    today_str = date.today().isoformat()
    n_index = write_index(by_cat, today_str)
    n_recent = write_recent(by_cat, today_str)

    actual = collect_actual_names()
    hits = find_dangling(actual)
    n_broken = write_broken(hits, today_str)

    print(f"Wrote {INDEX_PATH} ({n_index} notes), {RECENT_PATH} ({n_recent} entries)")
    if n_broken:
        print(f"Wrote {BROKEN_PATH} ({n_broken} dangling wikilinks)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
