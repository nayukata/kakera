#!/usr/bin/env python3
"""kakera Vault の月次監査スクリプト。

検出項目:
1. Orphan: 他のノートから wikilink で参照されていないメンバーノート (hub からも)
2. Stale: decay 期限を超えて references が更新されていないノート
3. Promotion: references が 3 件以上だが decay が permanent でないノート
4. Duplicates: 同一カテゴリ内で description が酷似するノート

出力: stdout に Markdown レポート。Vault パスは KAKERA_HOME 環境変数で解決。
"""

from __future__ import annotations

import os
import re
import sys
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

VAULT = Path(os.environ.get("KAKERA_HOME", str(Path.home() / "kakera")))
KNOWLEDGE = VAULT / "knowledge"

DECAY_DAYS: dict[str, int | None] = {
    "1month": 30,
    "3months": 90,
    "6months": 180,
    "permanent": None,
}

try:
    import yaml  # type: ignore[import-not-found]

    HAS_YAML = True
except ImportError:
    HAS_YAML = False

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")
WIKILINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]")
HUB_NAMES = {"フィードバック", "設計", "ユーザー", "プロジェクト", "意思決定", "失敗学習", "問い"}


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


def reference_count(fm: dict[str, str | list[str]]) -> int:
    refs = fm.get("references")
    if isinstance(refs, list):
        return len(refs)
    return 0


def collect_inbound_links() -> dict[str, set[str]]:
    inbound: dict[str, set[str]] = defaultdict(set)
    for md in KNOWLEDGE.glob("**/*.md"):
        text = md.read_text(encoding="utf-8")
        for target in WIKILINK_RE.findall(text):
            if target == md.stem:
                continue
            inbound[target].add(md.stem)
    return inbound


def description_similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    ta = set(a.replace("。", " ").split())
    tb = set(b.replace("。", " ").split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def main() -> int:
    if not KNOWLEDGE.exists():
        print(f"knowledge dir not found: {KNOWLEDGE}", file=sys.stderr)
        return 1

    today = date.today()
    inbound = collect_inbound_links()

    orphans: list[str] = []
    stales: list[tuple[str, str, int]] = []
    promotions: list[tuple[str, int, str]] = []
    duplicates: list[tuple[str, str, float]] = []
    recurrents: list[tuple[str, int, str]] = []  # (name, recurrence, last_hit)
    by_category: dict[str, list[tuple[str, str]]] = defaultdict(list)
    misclassified_design: list[tuple[str, list[str]]] = []  # (name, matched signals)
    yaml_broken: list[tuple[str, str]] = []  # (path, error)
    bad_titles: list[tuple[str, str]] = []  # (path, reason)

    # design/ にあるノートが固有名詞シグナルを含んでいたら project/<name>/ への誤分類候補とする。
    # 再発防止: mistakes/2026-05-20_design配下にプロジェクト固有知識を混入.md
    #
    # 動的シグナル (vault 横断で収集):
    # 1. project/<name>/ フォルダ名 (各利用者の vault 固有のプロジェクト名)
    # 2. backtick で囲まれた拡張子付き識別子 (`xxx.ts` `foo-bar.sh` 等の固有ファイル名)
    # 3. 3 字以上の連続英大文字頭字語 (ATSURAE / AWS / SaaS 等)
    project_dir = KNOWLEDGE / "project"
    project_names: list[str] = []
    if project_dir.exists():
        project_names = [p.name for p in project_dir.iterdir() if p.is_dir()]
    project_name_re = (
        re.compile("|".join(re.escape(n) for n in project_names), re.IGNORECASE)
        if project_names
        else None
    )
    BACKTICK_FILE_RE = re.compile(r"`([A-Za-z0-9_./\-]+\.[a-zA-Z]{1,5})`")
    ACRONYM_RE = re.compile(r"\b[A-Z]{3,}\b")
    # タイトル品質: ASCII 1-9 文字の直後にスペース無く日本語文字が続く = jargon prefix の疑い
    # 例: rc環境変数... / hubノート... / Surprise3段判定... を検出
    # kakera ノート... のようにスペース挟むものは検出しない (主語が明示されている)
    JARGON_PREFIX_RE = re.compile(r"^([A-Za-z][A-Za-z0-9]{0,8})[ぁ-んァ-ヴ一-龥]")
    # 確立語は contextual に通じるので除外
    ALLOW_HEAD_TOKENS = {
        "AI", "UI", "UX", "API", "URL", "URI", "DOM", "CSS", "HTML", "JSON",
        "E2E", "LLM", "PR", "OS", "DB", "CLI", "GUI", "OAuth", "JWT",
        "INDEX", "RECENT", "REVIEW",
    }
    MIN_TITLE_LEN = 9

    for md in sorted(KNOWLEDGE.glob("**/*.md")):
        name = md.stem
        body = md.read_text(encoding="utf-8")
        fm = parse_frontmatter(body)
        category = md.parent.name

        # タイトル品質チェック (hub/sub-hub は除外: メタノートでタイトル自由度高い)
        is_hub = name in HUB_NAMES or fm.get("type") in ("hub", "sub-hub")
        if not is_hub:
            if len(name) < MIN_TITLE_LEN:
                bad_titles.append((f"{category}/{name}", f"短すぎ ({len(name)} 文字 < {MIN_TITLE_LEN})"))
            else:
                jm = JARGON_PREFIX_RE.match(name)
                if jm and jm.group(1) not in ALLOW_HEAD_TOKENS:
                    bad_titles.append((f"{category}/{name}", f"先頭 jargon '{jm.group(1)}' の直後に日本語 (主語を補う)"))

        # PyYAML が入っていれば frontmatter を厳格パース。`: ` 混入などを検出
        if HAS_YAML:
            fm_match = FRONTMATTER_RE.match(body)
            if fm_match:
                try:
                    yaml.safe_load(fm_match.group(1))
                except yaml.YAMLError as e:
                    msg = str(e).split("\n")[0]
                    yaml_broken.append((f"{category}/{name}", msg))

        # design/ 直下 (サブ hub 配下も含む) に固有名詞シグナルがあれば誤分類候補
        if "design" in md.parts and name not in HUB_NAMES:
            matched: set[str] = set()
            if project_name_re:
                matched.update(m.group(0) for m in project_name_re.finditer(body))
            matched.update(m.group(0) for m in BACKTICK_FILE_RE.finditer(body))
            matched.update(m.group(0) for m in ACRONYM_RE.finditer(body))
            if matched:
                misclassified_design.append((f"{category}/{name}", sorted(matched)))

        if name not in HUB_NAMES and name not in inbound:
            orphans.append(f"{category}/{name}")

        decay = fm.get("decay", "permanent")
        if isinstance(decay, str) and decay in DECAY_DAYS:
            max_days = DECAY_DAYS[decay]
            if max_days is not None:
                recent = most_recent_ref(fm)
                if recent and (today - recent).days > max_days:
                    stales.append((f"{category}/{name}", decay, (today - recent).days))

        rc = reference_count(fm)
        if rc >= 3 and decay != "permanent":
            promotions.append((f"{category}/{name}", rc, str(decay)))

        # mistakes ノートの再発検出 (recurrence ≥ 3)
        if category == "mistakes":
            try:
                recurrence = int(str(fm.get("recurrence", "1")))
            except ValueError:
                recurrence = 1
            if recurrence >= 3:
                last_hit = str(fm.get("last_hit", "")).strip().strip('"').strip("'")
                recurrents.append((f"{category}/{name}", recurrence, last_hit))

        desc = fm.get("description", "")
        if isinstance(desc, str):
            by_category[category].append((name, desc))

    for category, items in by_category.items():
        for i, (a_name, a_desc) in enumerate(items):
            for b_name, b_desc in items[i + 1 :]:
                sim = description_similarity(a_desc, b_desc)
                if sim > 0.6:
                    duplicates.append((f"{category}/{a_name}", f"{category}/{b_name}", sim))

    print(f"# kakera Vault Audit ({today.isoformat()})")
    print()
    print(f"対象ノート: {sum(1 for _ in KNOWLEDGE.glob('**/*.md'))} 件")
    print()

    print("## タイトル品質 (主語省略 / jargon prefix の疑い)")
    if bad_titles:
        for n, reason in bad_titles:
            print(f"- {n} ({reason})")
    else:
        print("_該当なし。_")
    print()

    print("## YAML パース不能 (frontmatter 壊れ)")
    if not HAS_YAML:
        print("_PyYAML 未インストールのためスキップ。`pip install pyyaml` で有効化。_")
    elif yaml_broken:
        for n, err in yaml_broken:
            print(f"- {n}: {err}")
    else:
        print("_該当なし。_")
    print()

    print("## Orphan (どこからもリンクされていないノート)")
    if orphans:
        for o in orphans:
            print(f"- {o}")
    else:
        print("_該当なし。_")
    print()

    print("## Stale (decay 期限超過)")
    if stales:
        for n, d, days in sorted(stales, key=lambda x: -x[2]):
            print(f"- {n} ({d} / 最終 reference から {days} 日経過)")
    else:
        print("_該当なし。_")
    print()

    print("## Promotion 候補 (references が 3 件以上だが decay が permanent でない)")
    if promotions:
        for n, rc, d in promotions:
            print(f"- {n} (references {rc} / decay: {d})")
    else:
        print("_該当なし。_")
    print()

    print("## 再発罠 (recurrence ≥ 3: 根本対策候補)")
    if recurrents:
        for n, r, lh in sorted(recurrents, key=lambda x: -x[1]):
            print(f"- {n} (recurrence {r} / last_hit {lh})")
    else:
        print("_該当なし。_")
    print()

    print("## design/ 誤分類候補 (固有名詞を含むノート → project/<name>/ 検討)")
    if misclassified_design:
        for n, sigs in misclassified_design:
            print(f"- {n} (検出: {', '.join(sigs)})")
    else:
        print("_該当なし。_")
    print()

    print("## Duplicate 候補 (description が酷似)")
    if duplicates:
        for a, b, sim in sorted(duplicates, key=lambda x: -x[2]):
            print(f"- {a} <-> {b} (sim={sim:.2f})")
    else:
        print("_該当なし。_")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
