#!/usr/bin/env python3
"""kakera Vault のメンテ用キュー生成。

Top 10 を選んで `$KAKERA_HOME/REVIEW.md` に書き出す。
選定基準 (優先順):
1. stale (decay 期限を超えて references 更新なし)
2. promotion 候補 (references 3 件以上だが decay != permanent)
3. duplicate 候補 (同一カテゴリ内で description が酷似)

未解決の問い (questions/) はここでは扱わない。
学習対話は /kakera-study が、重複マージは /kakera-organize が担当する。
"""

from __future__ import annotations

import os
import re
import sys
from datetime import date, datetime
from pathlib import Path

VAULT = Path(os.environ.get("KAKERA_HOME", str(Path.home() / "kakera")))
KNOWLEDGE = VAULT / "knowledge"
OUTPUT = VAULT / "REVIEW.md"

DECAY_DAYS = {"1month": 30, "3months": 90, "6months": 180, "permanent": None}
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")


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


def latest_ref_date(fm: dict) -> date | None:
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
    return max(dates) if dates else None


def is_stale(fm: dict, today: date) -> bool:
    decay = fm.get("decay")
    if decay not in DECAY_DAYS or DECAY_DAYS[decay] is None:
        return False
    base = latest_ref_date(fm)
    if base is None:
        created = fm.get("created", "")
        m = DATE_RE.search(created)
        if not m:
            return False
        base = datetime.strptime(m.group(), "%Y-%m-%d").date()
    return (today - base).days > DECAY_DAYS[decay]


def description_similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    ta = set(a.replace("。", " ").split())
    tb = set(b.replace("。", " ").split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def collect():
    today = date.today()
    stale, promotion = [], []
    by_category: dict[str, list[tuple[str, str, str]]] = {}
    for md in KNOWLEDGE.rglob("*.md"):
        text = md.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        if fm.get("type") in ("hub", "sub-hub", "question"):
            continue
        rel = md.relative_to(VAULT).as_posix()
        desc = fm.get("description", "")
        if is_stale(fm, today):
            stale.append((md.stem, rel, desc))
        refs = fm.get("references", [])
        if isinstance(refs, list) and len(refs) >= 3 and fm.get("decay") != "permanent":
            promotion.append((md.stem, rel, desc))
        category = md.parent.name
        by_category.setdefault(category, []).append((md.stem, rel, desc))

    duplicates: list[tuple[str, str, float]] = []
    for items in by_category.values():
        for i, (a_name, _, a_desc) in enumerate(items):
            for b_name, _, b_desc in items[i + 1 :]:
                sim = description_similarity(a_desc, b_desc)
                if sim > 0.6:
                    duplicates.append((a_name, b_name, sim))
    duplicates.sort(key=lambda x: -x[2])
    return stale, promotion, duplicates


def render():
    if not KNOWLEDGE.exists():
        print(f"knowledge dir not found: {KNOWLEDGE}", file=sys.stderr)
        return 1

    stale, promotion, duplicates = collect()
    today = date.today().isoformat()
    lines = [
        "---",
        "name: REVIEW",
        "description: Vault メンテ用のキュー。週次自動生成。問いの再訪は /kakera-study、重複マージは /kakera-organize が担当。",
        f"updated: {today}",
        "---",
        "",
        "# メンテキュー",
        "",
        "古いメモの更新候補、permanent 昇格候補、重複候補。",
        "学習目的の「保留した問い」は `/kakera-study`、重複の対話マージは `/kakera-organize` で扱う。",
        "",
    ]

    def section(title: str, items: list, limit: int, note: str, formatter):
        lines.append(f"## {title} ({len(items)} 件中 上位 {min(limit, len(items))})")
        lines.append("")
        lines.append(f"_{note}_")
        lines.append("")
        if not items:
            lines.append("- 該当なし")
        else:
            for item in items[:limit]:
                lines.append(formatter(item))
        lines.append("")

    def basic_fmt(item):
        name, _rel, desc = item
        desc_short = desc[:80].replace("\n", " ") if desc else ""
        return f"- [[{name}]] — {desc_short}"

    def dup_fmt(item):
        a, b, sim = item
        return f"- [[{a}]] <-> [[{b}]] (sim={sim:.2f})"

    section("鮮度切れ", stale, 10,
            "decay 期限超過。現状と照合して更新または削除する。", basic_fmt)
    section("昇格候補", promotion, 10,
            "references 3 件以上。decay: permanent に格上げする。", basic_fmt)
    section("重複候補", duplicates, 10,
            "description の jaccard 類似度 0.6 超。/kakera-organize でマージ判断する。", dup_fmt)

    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT} (stale={len(stale)}, promotion={len(promotion)}, duplicates={len(duplicates)})")
    return 0


if __name__ == "__main__":
    sys.exit(render())
