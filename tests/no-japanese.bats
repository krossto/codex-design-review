#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

# 配布物（README.ja.md と docs/ の履歴は除外）に日本語が残っていないこと
@test "no Japanese in distributed files" {
  run grep -rlE '[ぁ-んァ-ヶ一-龥]' \
    "$ROOT/README.md" \
    "$ROOT/skills" \
    "$ROOT/hooks" \
    "$ROOT/schemas" \
    "$ROOT/.claude-plugin"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
