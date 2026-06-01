#!/bin/bash
# SessionStart hook: kakera の想起 / コーチ / 保存トリガーを session 開始時に context へ注入する。
# 単一ソースは AGENTS.md。<!-- kakera-inject:start --> .. <!-- kakera-inject:end --> で囲った
# 領域のみを抜粋するので、手書きで CLAUDE.md にコピーしてドリフトする事故が起きない。
# ~/.claude/settings.json の hooks.SessionStart から呼ばれ、stdout の JSON が context に載る。
set -u

# $0 が symlink (install.sh は vault/hooks/ から repo へ symlink する) でも repo を辿れるように解決
SRC="$0"
while [ -L "$SRC" ]; do
  TARGET="$(readlink "$SRC")"
  case "$TARGET" in
    /*) SRC="$TARGET" ;;
    *) SRC="$(cd "$(dirname "$SRC")" && pwd)/$TARGET" ;;
  esac
done
REPO_DIR="$(cd "$(dirname "$SRC")/.." && pwd)"
AGENTS="$REPO_DIR/AGENTS.md"

[ -f "$AGENTS" ] || exit 0

# Vault パス解決 (on-session-end.sh と同じ順序: env → 既知候補の config → default)
resolve_kakera_home() {
  if [ -n "${KAKERA_HOME:-}" ]; then printf '%s' "$KAKERA_HOME"; return; fi
  local candidate cfg p
  for candidate in "$HOME/Obsidian/kakera" "$HOME/kakera" "$HOME/.kakera"; do
    cfg="$candidate/.kakera-config.toml"
    if [ -f "$cfg" ]; then
      p=$(grep -E '^[[:space:]]*path[[:space:]]*=' "$cfg" | head -1 \
            | sed -E 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')
      if [ -n "$p" ] && [ -d "$p" ]; then printf '%s' "$p"; return; fi
      printf '%s' "$candidate"; return
    fi
  done
  printf '%s' "$HOME/kakera"
}
KAKERA_HOME="$(resolve_kakera_home)"

# INDEX が無い (未 init) なら注入しない
[ -f "$KAKERA_HOME/INDEX.md" ] || exit 0

# marker で囲った領域だけ抜粋
EXCERPT=$(awk '
  /<!-- kakera-inject:start -->/ { f=1; next }
  /<!-- kakera-inject:end -->/   { f=0; print ""; next }
  f
' "$AGENTS")

[ -n "$EXCERPT" ] || exit 0

CONTEXT="# kakera 長期記憶 (session 開始時に自動注入)
Vault: ${KAKERA_HOME} / 索引: ${KAKERA_HOME}/INDEX.md
下記は記憶の想起・コーチ・保存の発火条件。dev flow の観測点で従う。

${EXCERPT}"

# SessionStart hook は hookSpecificOutput.additionalContext を context に追加する
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$CONTEXT" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  # jq 不在時のフォールバック: SessionStart は素の stdout も context に取り込む
  printf '%s\n' "$CONTEXT"
fi
exit 0
