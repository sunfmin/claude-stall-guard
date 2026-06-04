# Dissolve prompts instead of detecting them

The original design ran the child under a PTY and tried to *detect* interactive prompts (prompt regexes, a separate `--prompt-idle` threshold). But a PTY makes commands more interactive than their real execution environment — Claude Code's Bash tool is non-interactive, nobody can type an answer — so the PTY was manufacturing the very hangs we were detecting. We dropped the PTY and harden stdio instead: `stdin=/dev/null`, own session (no controlling terminal), piped stdout/stderr. Prompts then dissolve themselves — stdin reads hit EOF, `/dev/tty` opens fail fast, pagers and wizards never start (`isatty()` is false) — and the watchdog only has to catch what remains: genuine hangs.

## Consequences

- A guarded command gets exactly its CI semantics: its own documented non-interactive behavior. A tool that does something destructive on EOF is broken in every CI pipeline; we don't owe it protection.
- EOF *is* an answer. Under the old design a prompt was killed unanswered; under dissolution a tool may fall through to its default. Accepted: the behavior is the tool's own, and visible in the output.
- Legitimately TTY-requiring commands (`docker exec -it`, TUIs, keyboard-interactive auth) fail fast instead of working. In scope this is correct — the tool's scope is commands run by an agent that cannot type.
- The entire prompt-detection apparatus (regexes, `--prompt-idle`, `STALL_GUARD_PROMPT_IDLE`) is gone; there is one threshold, the idle window.
