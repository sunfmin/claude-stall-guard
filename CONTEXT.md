# claude-stall-guard

A watchdog that lets Claude Code sense when a shell command is genuinely stuck — rather than waiting out the harness timeout — and gathers evidence about *where* it is stuck before killing it.

## Language

**Hang** (挂死):
The ground-truth condition: a process that will not make progress without outside intervention (dead peer, deadlock, a read on an fd that never delivers). Not directly observable.
_Avoid_: stuck, frozen, deadlock (deadlock is one *cause* of a hang, not a synonym)

**Stall**:
The verdict the watchdog renders: no observable progress for the idle window. A stall is *evidence of* a hang, not the hang itself.
_Avoid_: hang, timeout (a timeout is a fixed total-duration cutoff; a stall is an inactivity verdict)

**False kill** (误杀):
A stall verdict rendered against a process that was not hanging — e.g. a legitimate zero-output, zero-CPU, zero-traffic wait (a timer, an external human event) that outlasts the idle window.

**Missed hang**:
A genuine hang the watchdog fails to call, because something keeps forging progress signals — a perpetual spinner forging output, background heartbeat traffic forging network progress, a livelock forging CPU progress. An *accepted* failure mode, not a bug: missed hangs are backstopped by the harness's own timeout.

**Progress**:
Any observable forward signal from the guarded process group: new output, CPU time advancing, or traffic counters moving. Any single signal vetoes a stall verdict.
_Avoid_: activity, liveness

**Idle window**:
The continuous span with no progress that must elapse before the watchdog renders a stall verdict.
_Avoid_: timeout, deadline

**Dissolution** (消解):
Denying a prompt the terminal it needs, so it resolves itself (EOF, fast failure, non-interactive mode) instead of waiting. The layer that runs before detection: most would-be hangs never happen, and what remains for the watchdog are genuine hangs.
_Avoid_: prompt detection, prompt handling (both imply the prompt is allowed to exist)

**Stall report**:
The evidence package delivered with a stall verdict: the last output plus the blocked-at evidence. The report is the real signal to the judge; the exit code is just a mechanical hint.

**Blocked-at evidence**:
The OS-level answer to "what is each process in the group blocked on," gathered while the group is still alive. Facts from the kernel, not guesses from output text.
_Avoid_: diagnosis, hint

**Judge**:
Whoever decides what to do after a stall report — retry non-interactively, widen the idle window, or hand back to the human. The agent (Claude) is the judge; the watchdog only renders verdicts and ships evidence, it never remediates.

## Hook

**Guarded command**:
A Bash tool command the hook has rewritten to run under the watchdog. Anything else is an *unguarded* command — it behaves exactly as if the tool were not installed.

**Fail open**:
The hook's guarding rule: any doubt, any error, any unsupported case → the command runs unguarded. Guarding is opportunistic, never load-bearing.

**Permission mirror**:
The hook's conservative replica of the user's permission rules, evaluated against the *original* command so that guarding leaves the permission experience unchanged. When unsure, the mirror abstains — the user gets asked. It never allows on doubt.
_Avoid_: permission bypass, auto-approve

**Transparency**:
The wrapper invariant: a guarded command must behave exactly as it would unguarded — same interpreter dialect, same environment, same exit codes, same permission experience — with stall detection as the *only* observable difference. A transparency violation (shell-dialect drift, allowlist breakage) is a bug, not a trade-off.
