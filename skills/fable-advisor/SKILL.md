---
name: fable-advisor
description: Claude Fable advisor workflow through the local `ccf` CLI. Use for high-stakes plans, repeated failures, risky diffs, security/privacy-sensitive changes, architectural choices, or final completion checks where a skeptical second opinion should challenge assumptions before Codex continues.
---

# Fable Advisor

Use `ccf` as a stateless Claude Fable 5 advisor, not as an implementer. Send the smallest context that can change its judgment: plan, diff, failing output, assumptions, and verification already run.

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

3. Run `ccf`:
   - Plan: `ccf "Stress-test this plan. Focus on hidden assumptions, missing verification, and simpler alternatives: ..."`
   - Failure: `ccf "Diagnose why this loop is not converging. Suggest the next discriminating check: ..."`
   - Diff: `git diff | ccf "Review this diff for correctness risks, security/privacy issues, and missing tests."`
   - Done: `ccf "Challenge this completion claim. What would still make it false? ..."`

4. Integrate the advice:
   - Treat advisor output as advice, not authority.
   - If it identifies a valid gap, update the plan, code, or verification.
   - If you reject advice, state the concrete reason.

## Transcript Branch

Use a transcript only when a concrete current transcript file is known and the full history is likely to matter more than a compact packet. Prefer excerpts or summaries when possible.

```bash
ccf --transcript /path/to/session.jsonl "Review this session before I finalize. Focus on contradictions, dropped requirements, and unverified claims."
```

Do not search broadly through `~/.codex` for transcripts during normal work. If no reliable current transcript path is available, make the compact advisor packet from the visible conversation and local artifacts instead.
