#!/usr/bin/env bash
# PostToolUse hook: detects writes to spec/plan documents and
# instructs Claude to launch the codex-design-review skill via additionalContext.
# Only performs path detection and injection. No heavy processing (no Codex execution).
# Fail-safe: exits 0 on any error so it never blocks Write/Edit.

set +e

# --- Read input (exit silently on failure) ---
input="$(cat 2>/dev/null)" || exit 0
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -n "$file_path" ] || exit 0

# --- 1. Target path detection ---
case "$file_path" in
  */docs/superpowers/specs/*.md) doc_kind="spec" ;;
  */docs/superpowers/plans/*.md) doc_kind="plan" ;;
  *) exit 0 ;;
esac

# --- Project root ---
proj="${CLAUDE_PROJECT_DIR:-}"
[ -n "$proj" ] || exit 0

# --- 2. Re-trigger suppression during a loop (lock valid for 60 minutes) ---
lock="$proj/.claude/.codex-design-review.lock"
if [ -f "$lock" ]; then
  # Suppress if lock is newer than 60 minutes (3600 seconds)
  now="$(date +%s)"
  mtime="$(date -r "$lock" +%s 2>/dev/null || echo 0)"
  age=$(( now - mtime ))
  if [ "$age" -lt 3600 ]; then
    exit 0
  fi
fi

# --- 3. Output additionalContext ---
ctx="Launch the codex-design-review review skill (/codex-design-review:review) and run the review loop. Document kind: ${doc_kind}. Target path: ${file_path}. This is an automatic trigger fired on a write to a ${doc_kind} document."

jq -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'

exit 0
