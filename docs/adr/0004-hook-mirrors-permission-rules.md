# The hook mirrors permission rules against the original command

Claude Code evaluates permission rules against the *rewritten* command (verified empirically, 2026-06: an allow rule for the original command stops matching once the hook wraps it; a deny rule on the original degrades to a confirmation prompt). So enabling the hook silently breaks every Bash allowlist entry the user has and defangs their deny rules. We make the hook permission-aware: it reads the standard settings files (user, project, local), conservatively re-implements the documented Bash rule matching against the *original* command, and emits the decision alongside the rewrite — deny → `permissionDecision: "deny"`, allow → `"allow"` + `updatedInput` (verified to run promptless), ask or *any uncertainty* → wrap with no decision, which falls back to the normal confirmation prompt showing the wrapped command.

## Considered options

- **Accept the breakage** — rejected: a tool whose pitch is removing friction must not silently add a permission prompt to every wrapped command.
- **Tell users to allowlist the wrapper path** — rejected outright: the hook wraps nearly everything, so `Bash(…stall-guard:*)` auto-approves nearly everything; it voids the permission system.
- **Wait for upstream** — kept as the exit strategy, not the fix (see consequences).

## Consequences

- The mirror is a strict, conservative subset of Claude Code's matcher: exact rules, prefix (`:*`) rules with the documented word-boundary semantics, compound commands split on `&&` `||` `;` `|` `|&` `&` and newlines with every part required to match. Unknown syntax, parse doubt, or any exception → abstain. The failure direction is always "one extra prompt", never "one extra allow".
- Rule sources the hook cannot see (CLI `--allowedTools`, session-scoped always-allow) still prompt. Accepted friction.
- Maintaining a replica matcher carries divergence risk; it must stay a subset, and needs its own tests.
- User deny rules regain their teeth (today the rewrite degrades deny to ask).
- This ADR is superseded the day Claude Code supports transparent wrappers in rule matching (it already strips `timeout`/`nice`/`nohup`/`time`/`stdbuf`) or offers original-input permission evaluation for `updatedInput` — upstream feature request: anthropics/claude-code#65393; when it lands, delete the mirror.
