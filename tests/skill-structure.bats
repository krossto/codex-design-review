#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "new skill dir exists with SKILL.md" {
  [ -f "$ROOT/skills/review/SKILL.md" ]
}

@test "SKILL.md frontmatter name is review" {
  run grep -E '^name:[[:space:]]*review[[:space:]]*$' "$ROOT/skills/review/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "spec prompt exists and keeps placeholders" {
  [ -f "$ROOT/skills/review/reviewer-prompt-spec.md" ]
  run grep -c '{{TARGET_PATH}}' "$ROOT/skills/review/reviewer-prompt-spec.md"
  [ "$output" -ge 1 ]
  run grep -c '{{REFERENCES}}' "$ROOT/skills/review/reviewer-prompt-spec.md"
  [ "$output" -ge 1 ]
}

@test "plan prompt exists and keeps placeholders" {
  [ -f "$ROOT/skills/review/reviewer-prompt-plan.md" ]
  run grep -c '{{TARGET_PATH}}' "$ROOT/skills/review/reviewer-prompt-plan.md"
  [ "$output" -ge 1 ]
  run grep -c '{{REFERENCES}}' "$ROOT/skills/review/reviewer-prompt-plan.md"
  [ "$output" -ge 1 ]
}

@test "old skill dir no longer exists" {
  [ ! -d "$ROOT/skills/codex-design-review" ]
}
