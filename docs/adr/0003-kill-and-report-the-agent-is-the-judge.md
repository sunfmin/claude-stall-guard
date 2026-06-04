# Kill and report — the agent is the judge

On a stall verdict the watchdog probes the group for blocked-at evidence, kills the whole process group (SIGTERM, then SIGKILL), prints the stall report, and exits 99. It never remediates — no auto-answering, no advisory mode, no suspend-for-inspection. The kill is forced by the execution model: the Bash tool is synchronous, so a report is only delivered when the command exits, and exiting requires killing the group (SIGSTOP would leak frozen groups nobody can resume). Remediation is deliberately out of scope: the agent reading the report is the judge — it can retry with `yes |`, widen the idle window with a `STALL_GUARD_IDLE=` prefix, or hand back to the human — and dissolution means the prompt usually no longer exists to auto-answer anyway.

## Consequences

- Exit 99, not `timeout(1)`'s 124 (a stall is an inactivity verdict, not a fixed-duration cutoff) and not 137 (which must stay reserved for "child died of SIGKILL", passed through as 128+signal).
- A child that legitimately exits 99 is misread by the code alone; the stall report text is the authoritative signal.
- Feature requests of the form "stall-guard should answer the prompt" are out of scope by design.
