#!/usr/bin/env bash
# zcron installer — puts the CLI on PATH; optionally links the ZCode skill.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
AGENTS_SKILLS="${HOME}/.agents/skills"
ZCODE_SKILLS="${HOME}/.zcode/skills"

mkdir -p "$BIN_DIR"
install -m 755 "$SRC/zcron" "$BIN_DIR/zcron"
echo "✓ CLI  → $BIN_DIR/zcron"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "⚠ $BIN_DIR 不在 PATH 里,请在 shell 配置里加: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

if [ "${1:-}" = "--with-skill" ]; then
  mkdir -p "$AGENTS_SKILLS"
  ln -sfn "$SRC" "$AGENTS_SKILLS/zcron"
  echo "✓ 技能 → $AGENTS_SKILLS/zcron"
  if [ -d "$ZCODE_SKILLS" ]; then
    ln -sfn ../../.agents/skills/zcron "$ZCODE_SKILLS/zcron"
    echo "✓ 技能 → $ZCODE_SKILLS/zcron (软链)"
  fi
  echo "技能已可用:会话里说『用 zcron 批量建自动化』即可触发。"
fi

echo "下一步: zcron doctor"
