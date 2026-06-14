#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."
HELPER="$ROOT/scripts/resolve-codex.sh"

setup() {
  TMP="$BATS_TEST_TMPDIR"
  mkdir -p "$TMP/home" "$TMP/emptybin"
  # ヘルパーを source して関数を定義（副作用なし）
  # shellcheck source=/dev/null
  . "$HELPER"
}

# 絶対パス候補（env で制御できない）に実 codex があると、「未検出」を
# 期待するテストが解決してしまう。その場合はスキップする。
skip_if_common_codex_exists() {
  local p
  for p in /usr/local/bin/codex /opt/homebrew/bin/codex; do
    [ -x "$p" ] && skip "common codex exists at $p"
  done
  return 0
}

# --- bin 解決 ---

@test "bin: CDR_CODEX_BIN を尊重してそのまま返す" {
  CDR_CODEX_BIN="/custom/path/codex" run cdr_resolve_codex_bin
  [ "$status" -eq 0 ]
  [ "$output" = "/custom/path/codex" ]
}

@test "bin: PATH 上の codex を command -v で解決" {
  printf '#!/bin/sh\n' > "$TMP/emptybin/codex"
  chmod +x "$TMP/emptybin/codex"
  HOME="$TMP/home" PATH="$TMP/emptybin" run cdr_resolve_codex_bin
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/emptybin/codex" ]
}

@test "bin: PATH 不在・npm グローバル bin にあり → 解決" {
  # npm スタブ: prefix -g で偽 prefix を返す
  mkdir -p "$TMP/stubbin" "$TMP/npmprefix/bin"
  cat > "$TMP/stubbin/npm" <<EOF
#!/bin/sh
[ "\$1" = "prefix" ] && [ "\$2" = "-g" ] && echo "$TMP/npmprefix"
EOF
  chmod +x "$TMP/stubbin/npm"
  printf '#!/bin/sh\n' > "$TMP/npmprefix/bin/codex"
  chmod +x "$TMP/npmprefix/bin/codex"
  # PATH は stubbin のみ（スタブの shebang #!/bin/sh は絶対パスで解決され PATH 不要）。
  # 実 /usr/bin/codex が command -v で先勝ちするのを避けるため /usr/bin:/bin は含めない。
  HOME="$TMP/home" PATH="$TMP/stubbin" run cdr_resolve_codex_bin
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/npmprefix/bin/codex" ]
}

@test "bin: npm 不在・~/.npm-global/bin/codex にあり → 解決" {
  mkdir -p "$TMP/home/.npm-global/bin"
  printf '#!/bin/sh\n' > "$TMP/home/.npm-global/bin/codex"
  chmod +x "$TMP/home/.npm-global/bin/codex"
  # npm も PATH 上の codex も無し → npm prefix 候補はスキップされ、~/.npm-global 候補で解決
  HOME="$TMP/home" PATH="$TMP/emptybin" run cdr_resolve_codex_bin
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/home/.npm-global/bin/codex" ]
}

@test "bin: どこにも無ければ非0" {
  skip_if_common_codex_exists
  HOME="$TMP/home" PATH="$TMP/emptybin" run cdr_resolve_codex_bin
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
