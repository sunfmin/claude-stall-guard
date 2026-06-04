# Every progress signal vetoes the stall verdict

The watchdog kills the guarded process group when it renders a stall verdict, and a kill is irreversible — possibly mid-side-effect. A missed hang, by contrast, costs nothing new: the harness's own command timeout is the backstop, so missing a hang merely restores the status quo the tool was built to improve on. We therefore define progress as a disjunction — new output OR CPU time advancing OR traffic counters moving, across the whole process group — and any single signal vetoes the verdict. False kills are the failure mode to minimize, even at the price of systematically missing whole classes of hangs.

## Consequences

- Livelocks (CPU forging progress) and prompts shadowed by heartbeat/telemetry traffic (network forging progress) are *never* detected. These are accepted missed-hang classes, not bugs to fix by weakening a signal's veto.
- One threshold (`--idle`) governs the verdict; there are deliberately no per-signal thresholds or weights.
