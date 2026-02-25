#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.claude-env"
SOURCE_LINE='source "${HOME}/.claude-env/claude-env.sh"'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing claude-env..."

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/claude-env.sh" "$INSTALL_DIR/claude-env.sh"
echo "  Copied claude-env.sh to $INSTALL_DIR/"

add_source_line() {
  local rc_file="$1"
  if [[ -f "$rc_file" ]] && grep -qF 'claude-env/claude-env.sh' "$rc_file"; then
    echo "  $rc_file already sources claude-env — skipped"
    return
  fi
  printf '\n# claude-env\n%s\n' "$SOURCE_LINE" >> "$rc_file"
  echo "  Added source line to $rc_file"
}

# Add source line to any existing shell rc files
[[ -f "${HOME}/.bashrc" ]] && add_source_line "${HOME}/.bashrc"
[[ -f "${HOME}/.zshrc" ]]  && add_source_line "${HOME}/.zshrc"

if [[ ! -f "${HOME}/.bashrc" ]] && [[ ! -f "${HOME}/.zshrc" ]]; then
  echo "  Warning: No .bashrc or .zshrc found."
  echo "  Add this to your shell config: $SOURCE_LINE"
fi

echo ""
echo "Done! Restart your shell or run:"
echo "  source ${INSTALL_DIR}/claude-env.sh"
