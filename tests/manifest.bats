#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "plugin.json is valid JSON" {
  run jq empty "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
}

@test "plugin.json description notes Superpowers soft dependency" {
  run jq -r '.description' "$ROOT/.claude-plugin/plugin.json"
  echo "$output" | grep -q 'Superpowers'
  echo "$output" | grep -qi 'not required'
}
