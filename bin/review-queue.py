#!/usr/bin/env python3
"""kakera 自己学習用の復習キュー生成。

Top 10 を選んで `$KAKERA_HOME/REVIEW.md` に書き出す。
選定基準 (優先順):
1. questions/ 配下の未解決 (type: question)
2. stale (decay 期限を超えて references 更新なし)
3. promotion 候補 (references 3 件以上だが decay != permanent)

ユーザーが REVIEW.md を開くだけで「触るべき場所」が分かる入口。
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


def collect():
    today = date.today()
    questions, stale, promotion = [], [], []
    for md in KNOWLEDGE.rglob("*.md"):
        text = md.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        if fm.get("type") in ("hub", "sub-hub"):
            continue
        rel = md.relative_to(VAULT).as_posix()
        desc = fm.get("description", "")
        if fm.get("type") == "question":
            questions.append((md.stem, rel, desc))
            continue
        if is_stale(fm, today):
            stale.append((md.stem, rel, desc))
        refs = fm.get("references", [])
        if isinstance(refs, list) and len(refs) >= 3 and fm.get("decay") != "permanent":
            promotion.append((md.stem, rel, desc))
    return questions, stale, promotion


def render():
    if not KNOWLEDGE.exists():
        print(f"knowledge dir not found: {KNOWLEDGE}", file=sys.stderr)
        return 1

    questions, stale, promotion = collect()
    today = date.today().isoformat()
    lines = [
        "---",
        "name: REVIEW",
        "description: 自己学習用の復習キュー。週次自動生成。",
        f"updated: {today}",
        "---",
        "",
        "# 復習キュー",
        "",
        "自動生成。上から順に「触る」だけで知識が育つ設計。",
        "",
    ]

    def section(title: str, items: list, limit: int, note: str):
        lines.append(f"## {title} ({len(items)} 件中 上位 {min(limit, len(items))})")
        lines.append("")
        lines.append(f"_{note}_")
        lines.append("")
        if not items:
            lines.append("- 該当なし")
        else:
            for name, rel, desc in items[:limit]:
                desc_short = desc[:80].replace("\n", " ") if desc else ""
                lines.append(f"- [[{name}]] — {desc_short}")
        lines.append("")

    section("未解決の問い", questions, 10,
            "8 割止めの疑問。再訪して解決し通常ノートへ昇格させる。")
    section("鮮度切れ", stale, 10,
            "decay 期限超過。現状と照合し更新 or 削除。")
    section("昇格候補", promotion, 10,
            "references 3 件以上。decay: permanent に格上げする。")

    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT} (questions={len(questions)}, stale={len(stale)}, promotion={len(promotion)})")
    return 0


if __name__ == "__main__":
    sys.exit(render())
