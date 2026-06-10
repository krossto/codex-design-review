#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."
HOOK="$ROOT/hooks/on-design-doc-written.sh"

setup() {
  PROJ="$(mktemp -d)"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/superpowers/specs" "$PROJ/docs/superpowers/plans"
  export CLAUDE_PROJECT_DIR="$PROJ"
}

teardown() {
  rm -rf "$PROJ"
}

# 入力JSONを組み立てて hook に流す
run_hook() {
  local fp="$1"
  echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$fp\"}}" | bash "$HOOK"
}

@test "spec path with marker present -> injects additionalContext" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("codex-design-review")'
}

@test "plan path with marker present -> injects" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/docs/superpowers/plans/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext'
}

@test "no marker -> silent exit 0, no output" {
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-target path -> silent exit 0" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/src/main.py"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "README under docs but not specs/plans -> no inject" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/docs/superpowers/README.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fresh lock present -> suppressed" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  touch "$PROJ/.claude/.codex-design-review.lock"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stale lock (>60min) -> not suppressed" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  touch "$PROJ/.claude/.codex-design-review.lock"
  touch -d "90 minutes ago" "$PROJ/.claude/.codex-design-review.lock"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext'
}

@test "malformed stdin -> exit 0, no crash" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run bash -c "echo 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}
