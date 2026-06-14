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

# --- home 解決（直接呼び出して $CODEX_HOME を検査。run はサブシェルで export が伝播しないため使わない） ---

@test "home: CODEX_HOME 設定済みは尊重（上書きしない）" {
  HOME="$TMP/home"
  mkdir -p "$HOME/.codex"; : > "$HOME/.codex/auth.json"
  export CODEX_HOME="$TMP/preset"
  cdr_resolve_codex_home
  [ "$CODEX_HOME" = "$TMP/preset" ]
}

@test "home: 未設定で ~/.codex/auth.json → ~/.codex（パス1）" {
  HOME="$TMP/home"; unset CODEX_HOME
  mkdir -p "$HOME/.codex"; : > "$HOME/.codex/auth.json"
  cdr_resolve_codex_home
  [ "$CODEX_HOME" = "$HOME/.codex" ]
}

@test "home: 未設定で ~/.codex に config.toml のみ（keyring）→ ~/.codex（パス2）" {
  HOME="$TMP/home"; unset CODEX_HOME
  mkdir -p "$HOME/.codex"; : > "$HOME/.codex/config.toml"
  cdr_resolve_codex_home
  [ "$CODEX_HOME" = "$HOME/.codex" ]
}

@test "home: 未設定で ~/.config/codex/auth.json のみ → ~/.config/codex（パス1）" {
  HOME="$TMP/home"; unset CODEX_HOME
  mkdir -p "$HOME/.config/codex"; : > "$HOME/.config/codex/auth.json"
  cdr_resolve_codex_home
  [ "$CODEX_HOME" = "$HOME/.config/codex" ]
}

@test "home: 未設定で両方に auth.json → ~/.codex 優先（パス1の順序）" {
  HOME="$TMP/home"; unset CODEX_HOME
  mkdir -p "$HOME/.codex" "$HOME/.config/codex"
  : > "$HOME/.codex/auth.json"; : > "$HOME/.config/codex/auth.json"
  cdr_resolve_codex_home
  [ "$CODEX_HOME" = "$HOME/.codex" ]
}

@test "home: 未設定でどちらにも何も無し → 未設定のまま" {
  HOME="$TMP/home"; unset CODEX_HOME
  mkdir -p "$HOME/.codex" "$HOME/.config/codex"
  cdr_resolve_codex_home
  [ -z "${CODEX_HOME:-}" ]
}

@test "home: 実機回帰 — ~/.codex は config.toml のみ・~/.config/codex に auth.json → ~/.config/codex" {
  HOME="$TMP/home"; unset CODEX_HOME
  mkdir -p "$HOME/.codex" "$HOME/.config/codex"
  : > "$HOME/.codex/config.toml"
  : > "$HOME/.config/codex/auth.json"
  cdr_resolve_codex_home
  [ "$CODEX_HOME" = "$HOME/.config/codex" ]
}

# --- 統合: codex-review.sh の preflight ---

@test "integration: codex 未解決なら preflight で exit 3 ＋ 案内メッセージ" {
  skip_if_common_codex_exists
  mkdir -p "$TMP/home" "$TMP/emptybin"
  # 事前条件: この PATH/HOME では codex も npm も解決できない
  run env -i HOME="$TMP/home" PATH="$TMP/emptybin" /bin/bash -c 'command -v codex || command -v npm'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  # preflight 実行（round1 は引数5個必須。prompt/out は preflight 後に読まれるためダミーで可）
  run env -i HOME="$TMP/home" PATH="$TMP/emptybin" /bin/bash \
    "$ROOT/scripts/codex-review.sh" round1 \
    "$ROOT" "$ROOT/schemas/verdict-schema.json" "$TMP/prompt.md" "$TMP/out"
  [ "$status" -eq 3 ]
  [[ "$output" == *"codex CLI not found"* ]]
}
