#!/usr/bin/env python3
"""kakera Vault の全ノートサマリ INDEX.md を生成する。

検索時の入口として `/kakera-search` が最初に Read するもの。
1 ノート 1 行に圧縮することで、Vault が数百件規模になっても
コンテキスト消費を抑えて関連候補を絞れる。

Vault パスは KAKERA_HOME 環境変数で解決。
"""

from __future__ import annotations

import os
import re
import sys
from datetime import date, datetime
from pathlib import Path

VAULT = Path(os.environ.get("KAKERA_HOME", str(Path.home() / "kakera")))
KNOWLEDGE = VAULT / "knowledge"
OUTPUT = VAULT / "INDEX.md"

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")

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


def main() -> int:
    if not KNOWLEDGE.exists():
        print(f"knowledge dir not found: {KNOWLEDGE}", file=sys.stderr)
        return 1

    by_cat = collect_by_category()
    today = date.today().isoformat()
    lines = [
        "---",
        "name: INDEX",
        "description: 全ノートのサマリ。検索時の入口。自動生成。",
        f"updated: {today}",
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
        for name, fm, rel in items:
            importance = str(fm.get("importance", "?"))
            decay = str(fm.get("decay", "?"))
            desc = truncate(str(fm.get("description", "")), 60)
            lines.append(f"| [[{name}]] | {importance} | {decay} | {desc} |")
            total += 1
        lines.append("")

    lines.append(f"_対象ノート: {total} 件_")
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT} ({total} notes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
