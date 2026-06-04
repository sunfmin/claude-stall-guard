#!/bin/bash
# install.sh — script install / uninstall of stall-guard for Claude Code.
# (Prefer Homebrew: `brew install sunfmin/tap/claude-stall-guard`, then
#  `stall-guard-hook enable`. This script is the no-Homebrew alternative.)
#
#   bash install.sh              install or update (idempotent)
#   bash install.sh --uninstall  remove everything it installed
#
# One-liner (no clone needed; fetches the repo tarball itself):
#   curl -fsSL https://raw.githubusercontent.com/sunfmin/claude-stall-guard/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/sunfmin/claude-stall-guard/main/install.sh | bash -s -- --uninstall
#
# Layout after install:
#   ~/.local/share/claude-stall-guard/bin/stall-guard       (the watchdog)
#   ~/.local/share/claude-stall-guard/bin/stall-guard-hook  (settings.json merge tool)
#   ~/.local/share/claude-stall-guard/hooks/pretooluse.py   (the hook; finds the
#                                       guard via its own relative path, so the
#                                       two are always a matched pair)
#   ~/.local/bin/{stall-guard,stall-guard-hook}  -> symlinks, for manual use
#   ~/.claude/settings.json      <- one PreToolUse entry merged in by
#                                   `stall-guard-hook enable` (timestamped
#                                   backup; everything else left untouched)
set -euo pipefail
cd "$(dirname "$0")"

SHARE="$HOME/.local/share/claude-stall-guard"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"
REPO_TARBALL="https://github.com/sunfmin/claude-stall-guard/archive/refs/heads/main.tar.gz"

fetch_repo() {  # no checkout next to us (curl | bash): fetch the repo tarball
  command -v curl >/dev/null || { echo "error: need curl (or clone the repo and run install.sh there)" >&2; exit 1; }
  echo "no local checkout — fetching $REPO_TARBALL"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$REPO_TARBALL" | tar -xz -C "$TMP" --strip-components=1 \
    || { echo "error: download failed" >&2; exit 1; }
  cd "$TMP"
}

in_checkout() { [ -f bin/stall-guard ] && [ -f bin/stall-guard-hook ] && [ -f hooks/pretooluse.py ]; }

if [ "${1:-}" = "--uninstall" ]; then
  if [ -x "$SHARE/bin/stall-guard-hook" ]; then
    "$SHARE/bin/stall-guard-hook" disable
  elif in_checkout; then
    bin/stall-guard-hook disable
  else
    fetch_repo
    bin/stall-guard-hook disable
  fi
  for name in stall-guard stall-guard-hook; do
    link="$BIN_DIR/$name"
    if [ -L "$link" ] && [[ "$(readlink "$link")" == "$SHARE"* ]]; then
      rm -f "$link"
      echo "removed $link"
    fi
  done
  if [ -d "$SHARE" ]; then
    rm -rf "$SHARE"
    echo "removed $SHARE"
  fi
  echo "uninstalled. (already-running claude sessions keep the old hook until restarted)"
  exit 0
fi

in_checkout || fetch_repo

mkdir -p "$SHARE/bin" "$SHARE/hooks" "$BIN_DIR"
cp bin/stall-guard bin/stall-guard-hook "$SHARE/bin/"
cp hooks/pretooluse.py "$SHARE/hooks/pretooluse.py"
chmod +x "$SHARE/bin/stall-guard" "$SHARE/bin/stall-guard-hook" "$SHARE/hooks/pretooluse.py"
ln -sf "$SHARE/bin/stall-guard" "$BIN_DIR/stall-guard"
ln -sf "$SHARE/bin/stall-guard-hook" "$BIN_DIR/stall-guard-hook"
echo "installed -> $SHARE"
echo "symlinked -> $BIN_DIR/stall-guard, $BIN_DIR/stall-guard-hook"

"$SHARE/bin/stall-guard-hook" enable

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "note: ~/.local/bin is not on PATH (only affects manual use; the hook uses an absolute path)" ;;
esac
echo "uninstall: bash install.sh --uninstall"
