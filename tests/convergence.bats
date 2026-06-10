#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."
CONV="$ROOT/scripts/convergence.sh"

setup() {
  D="$(mktemp -d)"
}
teardown() {
  rm -rf "$D"
}

mkverdict() {  # $1=file $2=overall $3=findings-json
  echo "{\"verdict\":{\"overall\":\"$2\",\"confidence\":0.8,\"summary\":\"s\"},\"findings\":$3}" > "$1"
}

@test "scenario approved: r2 approved -> converged" {
  mkverdict "$D/r1v" revise '[{"id":"F1","severity":"minor","section":"s","issue":"i","why":"w","suggestion":"x"}]'
  echo '{"F1":"accept"}' > "$D/r1d"
  mkverdict "$D/r2v" approved '[]'
  echo '{}' > "$D/r2d"
  run bash "$CONV" "$D/r1v" "$D/r1d" "$D/r2v" "$D/r2d"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^RESULT=converged$"
}

@test "scenario revise->approved: r1 revise accepted, r2 approved -> converged" {
  mkverdict "$D/r1v" revise '[{"id":"F1","severity":"important","section":"s","issue":"i","why":"w","suggestion":"x"}]'
  echo '{"F1":"accept"}' > "$D/r1d"
  mkverdict "$D/r2v" approved '[]'
  echo '{}' > "$D/r2d"
  run bash "$CONV" "$D/r1v" "$D/r1d" "$D/r2v" "$D/r2d"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^RESULT=converged$"
  echo "$output" | grep -q "^UNRESOLVED=$"
}

@test "scenario unresolved: r1 reject, r2 re-asserts same id -> escalate" {
  mkverdict "$D/r1v" revise '[{"id":"F1","severity":"important","section":"s","issue":"i","why":"w","suggestion":"x"}]'
  echo '{"F1":"reject"}' > "$D/r1d"
  mkverdict "$D/r2v" revise '[{"id":"F1","severity":"important","section":"s","issue":"i","why":"w","suggestion":"x"}]'
  echo '{"F1":"reject"}' > "$D/r2d"
  run bash "$CONV" "$D/r1v" "$D/r1d" "$D/r2v" "$D/r2d"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^RESULT=escalate$"
  echo "$output" | grep -q "^UNRESOLVED=.*F1"
}

@test "r2 revise but rejected finding was dropped by Codex -> converged" {
  mkverdict "$D/r1v" revise '[{"id":"F1","severity":"minor","section":"s","issue":"i","why":"w","suggestion":"x"}]'
  echo '{"F1":"reject"}' > "$D/r1d"
  # r2 は別の新指摘 F2 のみ(F1 は取り下げられた)。F2 は争点ではない(r1 で reject していない)
  mkverdict "$D/r2v" revise '[{"id":"F2","severity":"minor","section":"s","issue":"i","why":"w","suggestion":"x"}]'
  echo '{"F2":"accept"}' > "$D/r2d"
  run bash "$CONV" "$D/r1v" "$D/r1d" "$D/r2v" "$D/r2d"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^RESULT=converged$"
}
