---
name: review
description: Use when a Superpowers spec or plan document under docs/superpowers/{specs,plans} has just been written or edited, to get an independent cross-model review from OpenAI Codex. Triggered automatically by the codex-design-review PostToolUse hook. Runs a bounded 2-round review loop, judges each finding with technical rigor, and escalates unresolved disagreements to the user.
---

# Codex Design Review (Cross-Model Review Loop)

Have a separate model (OpenAI Codex) independently review a spec or plan, then evaluate each finding with technical rigor and apply accepted changes. Because Claude and Codex come from different training lineages, this process surfaces mistakes that self-review would miss.

**When this skill is invoked, immediately register the checklist below in TodoWrite.**

## 0. Skip Check (always do this first)

If the preceding edit was a **typo fix, formatting adjustment, or other change with no substantive design impact**, **skip** the review, report that fact to the user in one line, and return to the normal flow (e.g. "Minor edit — cross-model review skipped"). The judgment is yours, but **always report even when skipping** (silent discard is not allowed).

If the change is a substantive design modification or a new document, proceed with the review.

## Preprocessing

1. **Identify the target**: Confirm the "document type (spec/plan)" and "target path" passed by the trigger. The project root is `$CLAUDE_PROJECT_DIR`.
2. **Create lock** (re-fire suppression): `touch "$CLAUDE_PROJECT_DIR/.claude/.codex-design-review.lock"`.
   This lock **must be deleted at the end** — delete it even if an error aborts the run (see "Completion" below).
3. **Resolve work directory**: Allocate a work directory `$work` exactly once in the OS temp area (respecting `TMPDIR`). If that fails, fall back automatically to `.claude/tmp-cdr/`. Use this path for all rounds.
   ```bash
   work=""
   work="$(mktemp -d "${TMPDIR:-/tmp}/codex-design-review-XXXXXX" 2>/dev/null)" || true
   if [ -z "$work" ]; then
     mkdir -p "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr" \
       && work="$(mktemp -d "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr/run-XXXXXX" 2>/dev/null)" || true
   fi
   [ -n "$work" ] || { echo "ERROR=could not create codex-design-review work dir"; exit 1; }
   echo "WORK=$work"
   ```
   - Use the path printed as `WORK=` as `$work` for all subsequent steps.
   - **If `ERROR=` (exit 1) is returned** (neither `/tmp` nor `.claude/` is writable), no work directory is available: **delete the lock, skip the review, report the reason to the user**, and return to the normal flow (perform only the lock deletion from "Completion" below; `$work` is empty so no temp-file cleanup is needed).
   - Also create the review records directory: `mkdir -p "$CLAUDE_PROJECT_DIR/docs/superpowers/reviews"`.
4. **Set output path**: `out1="$work/r1"`.

## Round 1

5. **Generate prompt**: Read `reviewer-prompt-spec.md` or `reviewer-prompt-plan.md` depending on document type. Substitute `{{TARGET_PATH}}` with the target path and `{{REFERENCES}}` with the related references you know (e.g. the path of the corresponding spec). Write the result to `$work/prompt.md`.
6. **Run Codex** (read-only, background, max 15 minutes). Use Bash with `run_in_background: true`:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/codex-review.sh" round1 \
     "$CLAUDE_PROJECT_DIR" \
     "$CLAUDE_PLUGIN_ROOT/schemas/verdict-schema.json" \
     "$work/prompt.md" \
     "$out1"
   ```
   Wait for completion. If it exceeds 15 minutes, stop the job, report to the user, and skip (go to Completion).
7. **Read results**: Extract the verdict path from `VERDICT=` and the thread ID from `THREAD=` in stdout.
   - If the script exits with code 2 (invalid verdict) → note the format issue and **retry exactly once**. If it fails again, report to the user and skip.
   - If the script exits with code 3 (Codex error: CLI missing, authentication expired, etc.) → skip the review, notify the user, and continue the normal flow.
8. **Evaluate findings**: List the `findings` and examine each finding with the rigor of the `superpowers:receiving-code-review` skill if it is available. If that skill is not present, fall back to a general review discipline: do not be sycophantic, judge each finding on its technical merits against the reality of this codebase, and decide accept / reject / hold with reasons.
   - Write the decisions as machine-readable **decisions JSON** (`{"F1":"reject","F2":"accept",...}`) to `$out1/decisions.json` (passed to `convergence.sh` for convergence checking).
9. **Write judgment document**: Write `docs/superpowers/reviews/YYYY-MM-DD-<topic>-codex-round1.md` (format below; human-readable).
10. **Apply accepted findings**: Apply all accepted (accept) findings to the target spec/plan.

## Round 2

11. **Re-review** (resume). `out2="$work/r2"`. Generate the round 2 prompt: "Read the rejection reasons in the judgment document (<round 1 path>). If convinced, withdraw the finding; if not, re-assert with reasons. **When re-asserting a Round 1 finding, keep the original finding id unchanged** (convergence checking matches topics by id). Updated document: <target path>". Write it to `$work/prompt2.md`:
    ```bash
    bash "$CLAUDE_PLUGIN_ROOT/scripts/codex-review.sh" round2 \
      "$CLAUDE_PROJECT_DIR" \
      "<thread_id obtained in round1>" \
      "$CLAUDE_PLUGIN_ROOT/schemas/verdict-schema.json" \
      "$work/prompt2.md" \
      "$out2"
    ```
    Use `run_in_background: true`; wait for completion.
12. **Evaluate findings the same way**, write `$out2/decisions.json` and judgment document `...-codex-round2.md`. Apply accepted findings.

## Convergence Check

Delegate deterministic convergence checking to **convergence.sh** (taking the model's evaluation results — decisions.json — as input):

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/convergence.sh" \
  "$out1/verdict.json" "$out1/decisions.json" \
  "$out2/verdict.json" "$out2/decisions.json"
```

- Output `RESULT=converged` → **done** (go to Completion below).
- Output `RESULT=escalate` → extract only the **disputed points** listed in `UNRESOLVED=` (findings that Claude rejected but Codex re-asserted) and present a three-way choice via `AskUserQuestion`:
  1. Adopt the Codex proposal
  2. Keep the Claude position
  3. Hold (record as held in the judgment document)
  Append the user's ruling to the judgment document, then go to Completion.
- **The round limit is fixed at 2.**

## Completion (always run)

- **Delete lock**: `rm -f "$CLAUDE_PROJECT_DIR/.claude/.codex-design-review.lock"`. Delete this even if aborting due to an error.
- **Delete temp files**: `[ -n "${work:-}" ] && rm -rf -- "$work"` (the guard makes this a no-op when `$work` is empty).
- **Output completion summary** to the user: count of findings / accepted / rejected / held, and the path(s) of the judgment document(s).
- Return to normal flow.

## Judgment Document Format

```markdown
# Codex Review Judgment: <target document name> (round N)

- Target: <target path>
- Round: N
- Codex thread_id: <thread_id>
- overall: <approved|revise>  / confidence: <0.0-1.0>
- Summary: <summary>

| ID | Severity | Finding (summary) | Decision | Reason |
|---|---|---|---|---|
| F1 | important | … | accept / reject / hold / user-ruling | … |
```

## Safety and Operational Invariants

- Codex is **always read-only** (enforced by codex-review.sh). `--dangerously-*` flags are forbidden.
- Codex is called **at most 2 times** per document. The structure prevents any more.
- Codex CLI missing / authentication expired / timeout → **skip without blocking**; always report to the user.
