#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "plugin.json is valid JSON" {
  run jq empty "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
}

@test "plugin.json has name codex-design-review" {
  run jq -r '.name' "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "codex-design-review" ]
}
