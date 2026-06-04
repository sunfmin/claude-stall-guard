#!/usr/bin/env python3
"""PreToolUse hook: transparently wrap Bash tool commands with stall-guard.

Reads the hook JSON on stdin; if the Bash command should be guarded, emits
hookSpecificOutput.updatedInput with the wrapped command (requires Claude
Code >= 2.1.152). Exiting silently with no output means "no change".
"""
import json
import os
import re
import shlex
import sys

# Cheap, never-interactive commands: not worth the wrapper noise.
# Only skipped when the WHOLE command is one simple cheap command — a cheap
# prefix must not exempt what follows it (`echo hi && ./slow.sh`).
SKIP_RE = re.compile(
    r'^(?:ls|pwd|echo|printf|which|whoami|date|true|false|'
    r'git\s+(?:status|log|diff|show|branch|remote|rev-parse)\b)'
)
SHELL_OPS_RE = re.compile(r'[|&;<>`$(\n]')

# `STALL_GUARD_IDLE=120 cmd` style prefixes must configure the guard itself,
# so hoist them out of the child command.
ENV_PREFIX_RE = re.compile(r'^((?:STALL_GUARD_[A-Z_]+=\S+\s+)+)(.*)$', re.S)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if data.get('tool_name') != 'Bash':
        return
    ti = data.get('tool_input') or {}
    cmd = (ti.get('command') or '').strip()

    if not cmd:
        return
    if ti.get('run_in_background'):           # servers/watchers idle by design
        return
    if os.environ.get('STALL_GUARD_DISABLE') == '1':
        return
    if 'stall-guard' in cmd:                  # already wrapped / self-test
        return
    # sudo via GUI askpass legitimately sits quiet while the user reads the dialog
    if re.search(r'\bsudo\b', cmd):
        return
    if SKIP_RE.match(cmd) and not SHELL_OPS_RE.search(cmd):
        return

    guard = os.path.join(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))),
        'bin', 'stall-guard')
    if not os.access(guard, os.X_OK):
        return

    prefix = ''
    m = ENV_PREFIX_RE.match(cmd)
    if m:
        prefix, cmd = m.group(1), m.group(2)

    wrapped = f'{prefix}{shlex.quote(guard)} -c {shlex.quote(cmd)}'
    json.dump({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'updatedInput': {**ti, 'command': wrapped},
        }
    }, sys.stdout)


if __name__ == '__main__':
    main()
