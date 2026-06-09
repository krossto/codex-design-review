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

@test "verdict-schema.json is valid JSON" {
  run jq empty "$ROOT/schemas/verdict-schema.json"
  [ "$status" -eq 0 ]
}

@test "verdict-schema requires verdict and findings" {
  run jq -r '.required | sort | join(",")' "$ROOT/schemas/verdict-schema.json"
  [ "$output" = "findings,verdict" ]
}

@test "verdict-schema is strict (additionalProperties false)" {
  run jq -r '.additionalProperties' "$ROOT/schemas/verdict-schema.json"
  [ "$output" = "false" ]
}

@test "a sample verdict conforms structurally" {
  sample='{"verdict":{"overall":"revise","confidence":0.8,"summary":"x"},"findings":[{"id":"F1","severity":"important","section":"§4","issue":"i","why":"w","suggestion":"s"}]}'
  run bash -c "echo '$sample' | jq -e '.verdict.overall and .findings[0].suggestion'"
  [ "$status" -eq 0 ]
}
