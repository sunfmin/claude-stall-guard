#!/bin/bash
# install.sh — install / uninstall stall-guard globally for Claude Code.
#
#   bash install.sh              install or update (idempotent)
#   bash install.sh --uninstall  remove everything it installed
#
# Layout after install:
#   ~/.local/share/claude-stall-guard/bin/stall-guard      (the watchdog)
#   ~/.local/share/claude-stall-guard/hooks/pretooluse.py  (the hook; finds the
#                                       guard via its own relative path, so the
#                                       two are always a matched pair)
#   ~/.local/bin/stall-guard     -> symlink, for manual use
#   ~/.claude/settings.json      <- one PreToolUse entry merged in
#
# settings.json is MERGED, never overwritten: only our own entry (recognized by
# the substring "claude-stall-guard") is added/refreshed/removed; every other
# hook and setting is left untouched. A timestamped backup is written next to
# the file before any change.
set -euo pipefail
cd "$(dirname "$0")"

SHARE="$HOME/.local/share/claude-stall-guard"
BIN_LINK="$HOME/.local/bin/stall-guard"
SETTINGS="$HOME/.claude/settings.json"
# $HOME stays unexpanded in settings.json; Claude Code runs hooks via the shell.
HOOK_CMD='"$HOME"/.local/share/claude-stall-guard/hooks/pretooluse.py'

merge_settings() {  # merge_settings <install|uninstall>
  python3 - "$SETTINGS" "$HOOK_CMD" "$1" <<'PY'
import json, os, sys, time

path, hook_cmd, mode = sys.argv[1:4]
MARK = 'claude-stall-guard'

old = None
if os.path.exists(path):
    with open(path) as f:
        old = f.read()

if mode == 'uninstall' and old is None:
    print('settings: no settings.json — nothing to remove')
    sys.exit(0)

try:
    data = json.loads(old) if old and old.strip() else {}
except ValueError:
    sys.exit(f'error: {path} is not valid JSON — fix or move it, then re-run')
if not isinstance(data, dict):
    sys.exit(f'error: {path} is not a JSON object — fix or move it, then re-run')

hooks = data.setdefault('hooks', {})
pre = hooks.setdefault('PreToolUse', [])
ours = [h for g in pre for h in (g.get('hooks') or [])
        if MARK in (h.get('command') or '')]

if mode == 'install':
    if ours:
        for h in ours:
            h['command'] = hook_cmd
        print('settings: hook entry already present (refreshed)')
    else:
        pre.append({'matcher': 'Bash',
                    'hooks': [{'type': 'command', 'command': hook_cmd}]})
        print('settings: hook entry added')
else:
    for g in pre:
        g['hooks'] = [h for h in (g.get('hooks') or [])
                      if MARK not in (h.get('command') or '')]
    pre[:] = [g for g in pre if g.get('hooks')]
    print('settings: hook entry removed' if ours
          else 'settings: hook entry not found')

if not hooks.get('PreToolUse'):
    hooks.pop('PreToolUse', None)
if not data.get('hooks'):
    data.pop('hooks', None)

new = json.dumps(data, indent=2) + '\n'
if new != (old or ''):
    if old is not None:
        bak = path + '.bak-' + time.strftime('%Y%m%d-%H%M%S')
        with open(bak, 'w') as f:
            f.write(old)
        print(f'settings: backup -> {bak}')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(new)
PY
}

if [ "${1:-}" = "--uninstall" ]; then
  merge_settings uninstall
  if [ -L "$BIN_LINK" ] && [[ "$(readlink "$BIN_LINK")" == "$SHARE"* ]]; then
    rm -f "$BIN_LINK"
    echo "removed $BIN_LINK"
  fi
  if [ -d "$SHARE" ]; then
    rm -rf "$SHARE"
    echo "removed $SHARE"
  fi
  echo "uninstalled. (already-running claude sessions keep the old hook until restarted)"
  exit 0
fi

[ -f bin/stall-guard ] && [ -f hooks/pretooluse.py ] \
  || { echo "error: run from a claude-stall-guard checkout" >&2; exit 1; }

mkdir -p "$SHARE/bin" "$SHARE/hooks" "$(dirname "$BIN_LINK")"
cp bin/stall-guard "$SHARE/bin/stall-guard"
cp hooks/pretooluse.py "$SHARE/hooks/pretooluse.py"
chmod +x "$SHARE/bin/stall-guard" "$SHARE/hooks/pretooluse.py"
ln -sf "$SHARE/bin/stall-guard" "$BIN_LINK"
echo "installed -> $SHARE"
echo "symlinked -> $BIN_LINK"

merge_settings install

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "note: ~/.local/bin is not on PATH (only affects manual use; the hook uses an absolute path)" ;;
esac
echo "done. new claude sessions are guarded; restart any session that should pick it up."
echo "uninstall: bash install.sh --uninstall"
