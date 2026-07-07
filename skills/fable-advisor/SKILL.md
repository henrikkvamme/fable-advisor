---
name: fable-advisor
description: Claude Fable advisor workflow through the local `fable-advisor` CLI. Use for high-stakes plans, repeated failures, risky diffs, security/privacy-sensitive changes, architectural choices, or final completion checks where a skeptical second opinion should challenge assumptions before the coding agent continues.
---

# Fable Advisor

Use `fable-advisor` as a stateless Claude Fable 5 advisor, not as an implementer. Send the smallest context that can change its judgment: plan, diff, failing output, assumptions, and verification already run.

## Advisor Loop

1. Pick the branch:
   - **Plan**: before implementing an ambiguous, risky, expensive, or architectural plan.
   - **Failure**: after repeated errors, flaky tests, confusing logs, or a debugging loop that is not converging.
   - **Diff**: before finalizing non-trivial code changes.
   - **Done**: before claiming completion when correctness, security, data loss, or user trust matters.

2. Build a compact advisor packet:
   - State the decision or claim Codex is about to make.
   - Include relevant code, diff, errors, commands, and test results.
   - Say what has already been verified.
   - Ask for risks, missing checks, false assumptions, and simpler alternatives.

3. Run `fable-advisor`:
   - Plan: `fable-advisor --no-stdin "Stress-test this plan. Focus on hidden assumptions, missing verification, and simpler alternatives: ..."`
   - Failure: `fable-advisor --no-stdin "Diagnose why this loop is not converging. Suggest the next discriminating check: ..."`
   - Diff: `git diff | fable-advisor --stdin "Review this diff for correctness risks, security/privacy issues, and missing tests."`
   - Done: `fable-advisor --no-stdin "Challenge this completion claim. What would still make it false? ..."`

The CLI does not read stdin unless `--stdin` is provided. Use `--stdin` whenever context is intentionally piped. `--no-stdin` is accepted for prompt-only calls, but plain prompt-only invocations are also safe.

If the CLI returns `API Error: Unable to connect to API (ConnectionRefused)` inside a sandboxed Codex session, rerun the same advisor command with network escalation. If the packet contains private repo, VPS, or secret-adjacent details, sanitize it first or ask the user before sending it to the external advisor.

4. Integrate the advice:
   - Treat advisor output as advice, not authority.
   - If it identifies a valid gap, update the plan, code, or verification.
   - If you reject advice, state the concrete reason.

## Transcript Branch

Use a transcript only when a concrete current transcript file is known and the full history is likely to matter more than a compact packet. Prefer excerpts or summaries when possible.

```bash
fable-advisor --no-stdin --transcript /path/to/session.jsonl "Review this session before I finalize. Focus on contradictions, dropped requirements, and unverified claims."
```

Do not search broadly through agent session directories during normal work. If no reliable current transcript path is available, make the compact advisor packet from the visible conversation and local artifacts instead.
