#!/bin/bash
# Test suite for stall-guard + the PreToolUse hook.
cd "$(dirname "$0")/.." || exit 1
GUARD=bin/stall-guard
PASS=0
FAIL=0

note() { printf '%s\n' "$*"; }

# run_case NAME EXPECTED_EXIT MUST_CONTAIN MUST_NOT_CONTAIN MAX_SECS -- guard-args...
run_case() {
  local name="$1" want_exit="$2" must="$3" must_not="$4" max_secs="$5"
  shift 6
  local t0 t1 out code elapsed ok=1 why=""
  t0=$(date +%s)
  out=$("$@" 2>&1)
  code=$?
  t1=$(date +%s)
  elapsed=$((t1 - t0))
  [ "$code" -ne "$want_exit" ] && ok=0 && why+="exit=$code want=$want_exit; "
  if [ -n "$must" ] && ! grep -qF "$must" <<<"$out"; then
    ok=0; why+="missing [$must]; "
  fi
  if [ -n "$must_not" ] && grep -qF "$must_not" <<<"$out"; then
    ok=0; why+="unexpected [$must_not]; "
  fi
  if [ "$elapsed" -gt "$max_secs" ]; then
    ok=0; why+="took ${elapsed}s > ${max_secs}s; "
  fi
  if [ "$ok" -eq 1 ]; then
    note "PASS  $name (${elapsed}s, exit $code)"
    PASS=$((PASS+1))
  else
    note "FAIL  $name — $why"
    note "──── output ────"
    printf '%s\n' "$out" | sed 's/^/      /'
    note "────────────────"
    FAIL=$((FAIL+1))
  fi
}

note "── stall-guard core ──"

run_case "yn-prompt detected fast" 99 "STALL DETECTED" "" 12 -- \
  "$GUARD" --prompt-idle 3 --idle 20 -c 'bash tests/fake-installer.sh'

run_case "password prompt detected" 99 "credential prompt" "" 12 -- \
  "$GUARD" --prompt-idle 3 --idle 20 -c 'bash tests/password-prompt.sh'

run_case "npm-init default-value prompt" 99 "STALL DETECTED" "" 12 -- \
  "$GUARD" --prompt-idle 3 --idle 20 -c 'bash tests/npm-init-style.sh'

run_case "cpu-busy silent NOT killed" 0 "done" "STALL DETECTED" 20 -- \
  "$GUARD" --prompt-idle 3 --idle 5 -c 'bash tests/quiet-worker.sh'

run_case "slow output NOT killed" 0 "finished" "STALL DETECTED" 15 -- \
  "$GUARD" --prompt-idle 3 --idle 5 -c 'bash tests/slow-echo.sh'

run_case "net-active silent NOT killed" 0 "net-done" "STALL DETECTED" 20 -- \
  "$GUARD" --prompt-idle 3 --idle 5 -c 'bash tests/net-quiet.sh'

run_case "generic silent stall (sleep)" 99 "completely idle" "" 12 -- \
  "$GUARD" --prompt-idle 3 --idle 4 -c 'sleep 60'

run_case "exit code passthrough" 7 "" "STALL DETECTED" 8 -- \
  "$GUARD" -c 'exit 7'

run_case "stdout passthrough" 0 "hello-world" "STALL DETECTED" 8 -- \
  "$GUARD" -c 'echo hello-world'

note ""
note "── PreToolUse hook ──"

hook_out() { printf '%s' "$1" | python3 hooks/pretooluse.py; }

# wraps a normal command
out=$(hook_out '{"tool_name":"Bash","tool_input":{"command":"npm init","timeout":120000}}')
if grep -q 'updatedInput' <<<"$out" && grep -q 'stall-guard' <<<"$out" \
   && grep -q '"timeout": 120000' <<<"$out"; then
  note "PASS  hook wraps npm init (keeps timeout)"; PASS=$((PASS+1))
else
  note "FAIL  hook wrap: $out"; FAIL=$((FAIL+1))
fi

# wrapped command actually runs and detects the stall (simulating the harness)
wrapped=$(hook_out '{"tool_name":"Bash","tool_input":{"command":"bash tests/fake-installer.sh"}}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["hookSpecificOutput"]["updatedInput"]["command"])')
out=$(STALL_GUARD_PROMPT_IDLE=3 bash -c "$wrapped" 2>&1); code=$?
if [ "$code" -eq 99 ] && grep -q "STALL DETECTED" <<<"$out"; then
  note "PASS  hook-wrapped command stalls correctly (exit 99)"; PASS=$((PASS+1))
else
  note "FAIL  hook-wrapped run: exit=$code out=$out"; FAIL=$((FAIL+1))
fi

# skip cases must produce NO output (= no modification)
skip_case() {
  local name="$1" json="$2"
  local out
  out=$(hook_out "$json")
  if [ -z "$out" ]; then
    note "PASS  hook skips $name"; PASS=$((PASS+1))
  else
    note "FAIL  hook should skip $name: $out"; FAIL=$((FAIL+1))
  fi
}
skip_case "run_in_background" '{"tool_name":"Bash","tool_input":{"command":"npm run dev","run_in_background":true}}'
skip_case "sudo (GUI askpass)" '{"tool_name":"Bash","tool_input":{"command":"SUDO_ASKPASS=$HOME/.local/bin/askpass sudo -A ls"}}'
skip_case "already wrapped" '{"tool_name":"Bash","tool_input":{"command":"bin/stall-guard -c ls"}}'
skip_case "cheap command (git status)" '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
skip_case "non-Bash tool" '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'

# STALL_GUARD_* env prefix is hoisted to configure the guard
out=$(hook_out '{"tool_name":"Bash","tool_input":{"command":"STALL_GUARD_IDLE=120 ./deploy.sh"}}')
if grep -qE '"command": "STALL_GUARD_IDLE=120 .*stall-guard' <<<"$out"; then
  note "PASS  hook hoists STALL_GUARD_* env prefix"; PASS=$((PASS+1))
else
  note "FAIL  env hoist: $out"; FAIL=$((FAIL+1))
fi

note ""
note "── stall-guard-hook (in a throwaway \$HOME) ──"

HOOKHOME=$(mktemp -d)
en=$(HOME="$HOOKHOME" bin/stall-guard-hook enable 2>&1)
st=$(HOME="$HOOKHOME" bin/stall-guard-hook status 2>&1)
HOME="$HOOKHOME" bin/stall-guard-hook disable >/dev/null 2>&1
st2=$(HOME="$HOOKHOME" bin/stall-guard-hook status 2>&1)
left=$(cat "$HOOKHOME/.claude/settings.json")
if grep -q 'hook entry added' <<<"$en" \
   && grep -q '^enabled: .*hooks/pretooluse.py' <<<"$st" \
   && [ "$st2" = "disabled" ] && [ "$left" = "{}" ]; then
  note "PASS  stall-guard-hook enable/status/disable round-trip"; PASS=$((PASS+1))
else
  note "FAIL  stall-guard-hook: en=$en st=$st st2=$st2 left=$left"; FAIL=$((FAIL+1))
fi
rm -rf "$HOOKHOME"

note ""
note "── install.sh (in a throwaway \$HOME) ──"

FAKEHOME=$(mktemp -d)
FAKESET="$FAKEHOME/.claude/settings.json"
ours_count() {
  python3 - "$FAKESET" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); raise SystemExit
print(sum(1 for g in d.get('hooks', {}).get('PreToolUse', [])
          for h in g.get('hooks', []) if 'claude-stall-guard' in h.get('command', '')))
PY
}

# seed a settings.json that already has a foreign hook + another setting
mkdir -p "$FAKEHOME/.claude"
printf '%s\n' '{"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/other-hook"}]}]}}' > "$FAKESET"

HOME="$FAKEHOME" bash install.sh >/dev/null 2>&1
if [ -x "$FAKEHOME/.local/share/claude-stall-guard/bin/stall-guard" ] \
   && [ -L "$FAKEHOME/.local/bin/stall-guard" ] \
   && [ "$(ours_count)" = 1 ] \
   && grep -q other-hook "$FAKESET" && grep -q '"model": "opus"' "$FAKESET" \
   && ls "$FAKEHOME/.claude/"settings.json.bak-* >/dev/null 2>&1; then
  note "PASS  install merges settings, keeps foreign hook + backup"; PASS=$((PASS+1))
else
  note "FAIL  install: $(cat "$FAKESET" 2>&1)"; FAIL=$((FAIL+1))
fi

HOME="$FAKEHOME" bash install.sh >/dev/null 2>&1
if [ "$(ours_count)" = 1 ]; then
  note "PASS  reinstall is idempotent (still one entry)"; PASS=$((PASS+1))
else
  note "FAIL  reinstall: $(ours_count) entries"; FAIL=$((FAIL+1))
fi

out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"npm init"}}' \
  | python3 "$FAKEHOME/.local/share/claude-stall-guard/hooks/pretooluse.py")
if grep -q 'claude-stall-guard/bin/stall-guard' <<<"$out"; then
  note "PASS  installed hook wraps via installed guard"; PASS=$((PASS+1))
else
  note "FAIL  installed hook: $out"; FAIL=$((FAIL+1))
fi

HOME="$FAKEHOME" bash install.sh --uninstall >/dev/null 2>&1
if [ "$(ours_count)" = 0 ] \
   && grep -q other-hook "$FAKESET" && grep -q '"model": "opus"' "$FAKESET" \
   && [ ! -e "$FAKEHOME/.local/share/claude-stall-guard" ] \
   && [ ! -e "$FAKEHOME/.local/bin/stall-guard" ]; then
  note "PASS  uninstall removes only our entry + files"; PASS=$((PASS+1))
else
  note "FAIL  uninstall: $(cat "$FAKESET" 2>&1)"; FAIL=$((FAIL+1))
fi
rm -rf "$FAKEHOME"

# curl | bash path: no checkout in cwd -> installer fetches the repo tarball.
# Simulated hermetically with a stub curl that emits a locally-built tarball.
STAGE=$(mktemp -d)
mkdir -p "$STAGE/claude-stall-guard-main" "$STAGE/fakebin" "$STAGE/empty"
cp -R bin hooks install.sh "$STAGE/claude-stall-guard-main/"
tar -czf "$STAGE/repo.tar.gz" -C "$STAGE" claude-stall-guard-main
printf '#!/bin/sh\ncat "%s"\n' "$STAGE/repo.tar.gz" > "$STAGE/fakebin/curl"
chmod +x "$STAGE/fakebin/curl"
FAKEHOME=$(mktemp -d)
FAKESET="$FAKEHOME/.claude/settings.json"
ROOT=$PWD
out=$(cd "$STAGE/empty" && HOME="$FAKEHOME" PATH="$STAGE/fakebin:$PATH" bash 2>&1 < "$ROOT/install.sh" || true)
if [ -x "$FAKEHOME/.local/share/claude-stall-guard/bin/stall-guard" ] \
   && [ "$(ours_count)" = 1 ] && grep -q 'fetching' <<<"$out"; then
  note "PASS  curl|bash install fetches tarball and installs"; PASS=$((PASS+1))
else
  note "FAIL  curl|bash install: $out"; FAIL=$((FAIL+1))
fi
rm -rf "$FAKEHOME" "$STAGE"

note ""
note "═══ $PASS passed, $FAIL failed ═══"
[ "$FAIL" -eq 0 ]
