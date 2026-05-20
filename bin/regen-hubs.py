#!/usr/bin/env python3
"""hub note (フィードバック.md / 設計.md など) のメンバー一覧を再生成する。

score = importance_weight * 100 + recency_bonus
importance_weight: high=3, medium=2, low=1
recency_bonus: 直近 references から 30 日以内なら (30 - days)、超過は 0

サブ hub (frontmatter `type: sub-hub`) を検出すると、親 hub では
[サブ hub を score 降順で先頭] + [サブ hub に含まれない直結 member] を表示する。
サブ hub 自体のメンバーリストは触らない (子の振り分けは抽出時に行う)。

Vault パスは環境変数 KAKERA_HOME (default: ~/kakera) から解決する。
"""

from __future__ import annotations

import os
import re
import sys
from datetime import date, datetime
from pathlib import Path

VAULT = Path(os.environ.get("KAKERA_HOME", str(Path.home() / "kakera")))
KNOWLEDGE = VAULT / "knowledge"

CATEGORY_TO_HUB: dict[str, str] = {
    "feedback": "フィードバック",
    "design": "設計",
    "user": "ユーザー",
    "project": "プロジェクト",
    "decisions": "意思決定",
    "mistakes": "失敗学習",
    "questions": "問い",
}

IMPORTANCE_WEIGHT: dict[str, int] = {"high": 3, "medium": 2, "low": 1}

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
MEMBER_SECTION_RE = re.compile(
    r"(## メンバー\s*\n)(.*?)(\n##(?!#)|\n戻る:|\n*$)",
    re.DOTALL,
)
WIKILINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]")


def parse_frontmatter(text: str) -> dict[str, str | list[str]]:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    fm: dict[str, str | list[str]] = {}
    current_list_key: str | None = None
    for line in m.group(1).splitlines():
        if line.startswith("  -"):
            if current_list_key:
                fm.setdefault(current_list_key, []).append(line[3:].strip())  # type: ignore[union-attr]
            continue
        current_list_key = None
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if val == "":
            current_list_key = key
        else:
            fm[key] = val
    return fm


def most_recent_ref(fm: dict[str, str | list[str]]) -> date | None:
    refs = fm.get("references")
    candidates: list[date] = []
    if isinstance(refs, list):
        for r in refs:
            match = DATE_RE.search(r)
            if match:
                try:
                    candidates.append(datetime.strptime(match.group(0), "%Y-%m-%d").date())
                except ValueError:
                    pass
    created = fm.get("created")
    if isinstance(created, str):
        match = DATE_RE.search(created)
        if match:
            try:
                candidates.append(datetime.strptime(match.group(0), "%Y-%m-%d").date())
            except ValueError:
                pass
    return max(candidates) if candidates else None


def score(fm: dict[str, str | list[str]], today: date) -> int:
    importance = fm.get("importance", "low")
    if not isinstance(importance, str):
        importance = "low"
    w = IMPORTANCE_WEIGHT.get(importance, 1)
    recent = most_recent_ref(fm)
    bonus = 0
    if recent is not None:
        days = (today - recent).days
        bonus = max(0, 30 - days)
    return w * 100 + bonus


def member_links_in_section(text: str) -> set[str]:
    m = MEMBER_SECTION_RE.search(text)
    if not m:
        return set()
    return set(WIKILINK_RE.findall(m.group(2)))


def collect_for_parent_hub(category: str, hub_name: str, today: date) -> tuple[list[tuple[str, dict]], list[tuple[str, dict]]]:
    folder = KNOWLEDGE / category
    sub_hubs: list[tuple[str, dict]] = []
    flat_members: list[tuple[str, dict]] = []
    claimed: set[str] = set()

    if not folder.exists():
        return [], []

    # サブ hub は同名サブフォルダ内に置く運用 (例: design/Hookパターン/Hookパターン.md)。
    # 親 hub 直下の .md は parent hub 自身か直結 member、サブフォルダ内は sub-hub + その member。
    for md in folder.rglob("*.md"):
        if md.stem == hub_name:
            continue
        text = md.read_text(encoding="utf-8")
        fm = parse_frontmatter(text)
        if fm.get("type") == "sub-hub":
            sub_hubs.append((md.stem, fm))
            claimed |= member_links_in_section(text)
        elif md.parent == folder:
            flat_members.append((md.stem, fm))

    direct_members = [(n, fm) for n, fm in flat_members if n not in claimed]

    sub_hubs.sort(key=lambda m: (-score(m[1], today), m[0]))
    direct_members.sort(key=lambda m: (-score(m[1], today), m[0]))
    return sub_hubs, direct_members


def format_member_line(name: str, fm: dict[str, str | list[str]], *, is_sub_hub: bool = False) -> str:
    importance = fm.get("importance", "?")
    desc = fm.get("description", "")
    if isinstance(desc, str):
        desc = desc.strip().strip('"').split("。")[0]
        desc = desc[:60]
    prefix = "**[[" if is_sub_hub else "[["
    suffix = "]]**" if is_sub_hub else "]]"
    return f"- {prefix}{name}{suffix} ({importance}) — {desc}"


def regen_hub(category: str, hub_name: str, today: date) -> str:
    hub_path = KNOWLEDGE / category / f"{hub_name}.md"
    if not hub_path.exists():
        return f"skip (no hub at {hub_path})"

    sub_hubs, direct_members = collect_for_parent_hub(category, hub_name, today)
    lines: list[str] = []
    if sub_hubs:
        lines.append("### サブ hub")
        lines.extend(format_member_line(n, fm, is_sub_hub=True) for n, fm in sub_hubs)
        if direct_members:
            lines.append("")
            lines.append("### 直結メンバー")
            lines.extend(format_member_line(n, fm) for n, fm in direct_members)
    else:
        if direct_members:
            lines.extend(format_member_line(n, fm) for n, fm in direct_members)

    if not lines:
        new_section_body = "\n_未記録。_\n"
    else:
        new_section_body = "\n" + "\n".join(lines) + "\n"

    text = hub_path.read_text(encoding="utf-8")
    m = MEMBER_SECTION_RE.search(text)
    if not m:
        new_text = text.rstrip() + f"\n\n## メンバー\n{new_section_body}"
    else:
        new_text = text[: m.start()] + f"## メンバー\n{new_section_body}" + text[m.end() - len(m.group(3)) :]

    if new_text == text:
        return f"{hub_name}: unchanged ({len(sub_hubs)} sub-hubs, {len(direct_members)} direct)"
    hub_path.write_text(new_text, encoding="utf-8")
    return f"{hub_name}: regenerated ({len(sub_hubs)} sub-hubs, {len(direct_members)} direct)"


def main() -> int:
    if not KNOWLEDGE.exists():
        print(f"knowledge dir not found: {KNOWLEDGE}", file=sys.stderr)
        return 1
    today = date.today()
    for category, hub in CATEGORY_TO_HUB.items():
        print(regen_hub(category, hub, today))
    return 0


if __name__ == "__main__":
    sys.exit(main())
