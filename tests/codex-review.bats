#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."
REVIEW="$ROOT/scripts/codex-review.sh"
SCHEMA="$ROOT/schemas/verdict-schema.json"

setup() {
  OUT="$(mktemp -d)"
  PROMPT="$(mktemp)"
  echo "review prompt body" > "$PROMPT"
  export CDR_CODEX_BIN="$ROOT/tests/codex-stub.sh"
}

teardown() {
  rm -rf "$OUT" "$PROMPT"
}

@test "round1 approved -> emits VERDICT and THREAD, verdict overall approved" {
  export CDR_STUB_SCENARIO=approved
  run bash "$REVIEW" round1 "$ROOT" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^VERDICT=$OUT/verdict.json$"
  echo "$output" | grep -q "^THREAD=00000000-0000-7000-8000-000000000001$"
  run jq -r '.verdict.overall' "$OUT/verdict.json"
  [ "$output" = "approved" ]
}

@test "round1 revise -> verdict overall revise with 1 finding" {
  export CDR_STUB_SCENARIO=revise
  run bash "$REVIEW" round1 "$ROOT" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 0 ]
  run jq -r '.findings | length' "$OUT/verdict.json"
  [ "$output" = "1" ]
}

@test "round2 (resume) approved -> success" {
  export CDR_STUB_SCENARIO=revise_approved
  run bash "$REVIEW" round2 "$ROOT" "00000000-0000-7000-8000-000000000001" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 0 ]
  run jq -r '.verdict.overall' "$OUT/verdict.json"
  [ "$output" = "approved" ]
}

@test "badjson verdict -> exit 2" {
  export CDR_STUB_SCENARIO=badjson
  run bash "$REVIEW" round1 "$ROOT" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 2 ]
}

@test "thread_id is extracted from spaced JSONL (F3 regression)" {
  export CDR_STUB_SCENARIO=approved
  export CDR_STUB_SPACED=1
  run bash "$REVIEW" round1 "$ROOT" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^THREAD=00000000-0000-7000-8000-000000000001$"
}

@test "out-of-range confidence warns but does not discard verdict (R2-F2)" {
  # confidence は収束判定に使わない助言的メタデータ。範囲外でも有効な
  # findings を捨てない方針。警告は stderr に出すが exit 0 で成功扱い。
  export CDR_STUB_SCENARIO=badconfidence
  # bats の run は既定で stdout+stderr を $output に統合する
  run bash "$REVIEW" round1 "$ROOT" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "VERDICT=$OUT/verdict.json"
  echo "$output" | grep -qi "confidence out of range"
}

@test "round1 passes read-only sandbox flag to codex" {
  # スタブを wrapper で包んで渡された引数を記録する
  ARGLOG="$OUT/args.txt"
  cat > "$OUT/spy.sh" <<SPY
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGLOG"
exec "$ROOT/tests/codex-stub.sh" "\$@"
SPY
  chmod +x "$OUT/spy.sh"
  export CDR_CODEX_BIN="$OUT/spy.sh"
  export CDR_STUB_SCENARIO=approved
  run bash "$REVIEW" round1 "$ROOT" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "read-only" "$ARGLOG"
}

@test "round2 passes sandbox_mode=read-only via -c (resume has no -s)" {
  ARGLOG="$OUT/args.txt"
  cat > "$OUT/spy.sh" <<SPY
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGLOG"
exec "$ROOT/tests/codex-stub.sh" "\$@"
SPY
  chmod +x "$OUT/spy.sh"
  export CDR_CODEX_BIN="$OUT/spy.sh"
  export CDR_STUB_SCENARIO=revise_approved
  run bash "$REVIEW" round2 "$ROOT" "00000000-0000-7000-8000-000000000001" "$SCHEMA" "$PROMPT" "$OUT"
  [ "$status" -eq 0 ]
  grep -q "sandbox_mode=read-only" "$ARGLOG"
  # resume には -s フラグを使っていないこと
  ! grep -qx -- "-s" "$ARGLOG"
  # resume も --output-schema を渡していること(F1)
  grep -qx -- "--output-schema" "$ARGLOG"
}
