# Troubleshooting notes

Post-mortems for problems that have actually happened on this machine — what the
symptom looked like, how it was diagnosed, what the root cause turned out to be,
and how to prevent a repeat.

These differ from [`docs/guides/`](../guides/): guides explain how to *use* a
tool, these explain how to *unbreak* something. Write one whenever a diagnosis
took real effort, especially when the same symptom can come from more than one
root cause.

| Note | Symptom |
|---|---|
| [`nvidia-monitor-no-signal.md`](nvidia-monitor-no-signal.md) | One of two monitors goes dark / no signal (NVIDIA dual-display) |
| [`terminal-icons-tofu.md`](terminal-icons-tofu.md) | Icons show as empty boxes in nvim / prompt / statusline, locally or over SSH |

## Writing a new note

Keep the structure that makes these useful under pressure:

1. **Triage first** — the smallest set of commands that distinguishes the
   possible causes, with a table mapping output → cause.
2. **One section per root cause** — confirm it, fix it, verify the fix, and say
   why it happened.
3. **Real evidence** — paste the actual command output from the incident, dated.
   Reconstructed examples go stale and mislead.
4. **Lessons learned** — the transferable part. What was the tell? What red
   herring wasted time? What would have caught it earlier?
