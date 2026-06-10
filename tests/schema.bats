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

@test "hooks.json is valid JSON" {
  run jq empty "$ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
}

@test "hooks.json registers a PostToolUse hook" {
  run jq -e '.hooks.PostToolUse[0].hooks[0].command' "$ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
}

@test "hooks.json matcher targets Write/Edit tools" {
  run jq -r '.hooks.PostToolUse[0].matcher' "$ROOT/hooks/hooks.json"
  [ "$output" = "Write|Edit|MultiEdit" ]
}

@test "hooks.json command references on-design-doc-written.sh via CLAUDE_PLUGIN_ROOT" {
  run jq -r '.hooks.PostToolUse[0].hooks[0].command' "$ROOT/hooks/hooks.json"
  [[ "$output" == *'${CLAUDE_PLUGIN_ROOT}'* ]]
  [[ "$output" == *"on-design-doc-written.sh"* ]]
}
