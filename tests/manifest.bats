#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "plugin.json is valid JSON" {
  run jq empty "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
}

@test "marketplace.json is valid JSON" {
  run jq empty "$ROOT/.claude-plugin/marketplace.json"
  [ "$status" -eq 0 ]
}

@test "plugin.json description notes Superpowers soft dependency" {
  run jq -r '.description' "$ROOT/.claude-plugin/plugin.json"
  echo "$output" | grep -q 'Superpowers'
  echo "$output" | grep -qi 'not required'
}

@test "marketplace plugin entry description notes Superpowers" {
  run jq -r '.plugins[0].description' "$ROOT/.claude-plugin/marketplace.json"
  echo "$output" | grep -q 'Superpowers'
}
