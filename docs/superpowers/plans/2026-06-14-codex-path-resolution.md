# Codex 実行パス / CODEX_HOME 解決の堅牢化 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** codex 実行ファイルと `CODEX_HOME` の解決を、テスト可能なヘルパー `scripts/resolve-codex.sh` に切り出し、PATH 最小化や keyring 認証でも主要パスをフォールバックで確実に確認する。

**Architecture:** 副作用のない source 専用ヘルパーに 2 関数（`cdr_resolve_codex_bin` / `cdr_resolve_codex_home`）を定義。`scripts/codex-review.sh` が引数パース直後（`mkdir`/`cat` より前）にこれを source し、実行ファイル不在なら fail-fast で exit 3。bats で各分岐を hermetic に検証する。

**Tech Stack:** bash（`#!/usr/bin/env bash`、配列・パラメータ展開・builtin 中心）、bats（既存テスト資産）、jq。

**設計の出典:** `docs/superpowers/specs/2026-06-14-codex-path-resolution-design.md`。

---

## ファイル構成

| ファイル | 役割 |
|---|---|
| `scripts/resolve-codex.sh` | **新規**。`cdr_resolve_codex_bin`（実行ファイル解決）/ `cdr_resolve_codex_home`（CODEX_HOME 解決）の 2 関数を定義。関数定義のみ・副作用なし |
| `tests/resolve-codex.bats` | **新規**。両関数 + 統合 preflight の単体テスト |
| `scripts/codex-review.sh` | **改修**。35 行目・37-40 行目の解決処理を削除し、引数パース直後に source＋preflight＋home 解決を集約。ヘッダの exit コード説明を更新 |
| `README.md` / `README.ja.md` | **改修**。前提条件（解決動作）の記述を一般化し `CDR_CODEX_BIN` を案内 |

---

## Task 1: `cdr_resolve_codex_bin`（実行ファイル解決）

**Files:**
- Create: `tests/resolve-codex.bats`
- Create: `scripts/resolve-codex.sh`

- [ ] **Step 1: 失敗するテストを書く（bin 解決の4ケース）**

`tests/resolve-codex.bats` を新規作成:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bats tests/resolve-codex.bats`
Expected: FAIL（`scripts/resolve-codex.sh` が存在せず source できない）

- [ ] **Step 3: `cdr_resolve_codex_bin` を実装**

`scripts/resolve-codex.sh` を新規作成:

```bash
#!/usr/bin/env bash
# Codex 実行ファイルと CODEX_HOME を解決するヘルパー（source 専用）。
# 関数定義のみ。副作用を持たない（set 等で親シェルの挙動を変えない）。
# 設計: docs/superpowers/specs/2026-06-14-codex-path-resolution-design.md

# codex 実行ファイルを解決して stdout に出力。見つかれば 0、無ければ非0。
cdr_resolve_codex_bin() {
  # 1. 明示オーバーライド（検証せずそのまま使用＝後方互換）
  if [ -n "${CDR_CODEX_BIN:-}" ]; then
    printf '%s\n' "$CDR_CODEX_BIN"
    return 0
  fi
  # 2. PATH 上の codex
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi
  # 3. 候補を順に確認（最初の実行可能ファイル）。npm は PATH 上にある場合のみ。
  local cand prefix
  local -a candidates=()
  prefix="$(npm prefix -g 2>/dev/null)"
  [ -n "$prefix" ] && candidates+=("$prefix/bin/codex")
  candidates+=(
    "$HOME/.npm-global/bin/codex"
    "/usr/local/bin/codex"
    "/opt/homebrew/bin/codex"
  )
  for cand in "${candidates[@]}"; do
    if [ -x "$cand" ]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}
```

- [ ] **Step 4: テストを実行して成功を確認（bin の4ケース）**

Run: `bats tests/resolve-codex.bats`
Expected: bin の 5 テストが PASS（home/統合はまだ未追加）

- [ ] **Step 5: コミット**

```bash
git add scripts/resolve-codex.sh tests/resolve-codex.bats
git commit -m "feat: add cdr_resolve_codex_bin with layered fallbacks"
```

---

## Task 2: `cdr_resolve_codex_home`（CODEX_HOME 解決・2 パス方式）

**Files:**
- Modify: `tests/resolve-codex.bats`（home テストを追記）
- Modify: `scripts/resolve-codex.sh`（関数を追記）

- [ ] **Step 1: 失敗するテストを書く（home 解決の7ケース）**

`tests/resolve-codex.bats` の末尾に追記:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bats tests/resolve-codex.bats`
Expected: home の 7 テストが FAIL（`cdr_resolve_codex_home: command not found`）。bin の 4 テストは PASS のまま。

- [ ] **Step 3: `cdr_resolve_codex_home` を実装**

`scripts/resolve-codex.sh` の末尾（`cdr_resolve_codex_bin` の後）に追記:

```bash
# CODEX_HOME を必要時のみ export する。常に 0 を返す（設定不在はエラーにしない）。
cdr_resolve_codex_home() {
  # 既存設定は尊重（上書きしない）
  if [ -n "${CODEX_HOME:-}" ]; then
    return 0
  fi
  local d
  # パス1: auth.json 優先（実ファイル認証の最強シグナル）
  for d in "$HOME/.codex" "$HOME/.config/codex"; do
    if [ -f "$d/auth.json" ]; then
      export CODEX_HOME="$d"
      return 0
    fi
  done
  # パス2: config.toml フォールバック（keyring 認証で auth.json が無いケース）
  for d in "$HOME/.codex" "$HOME/.config/codex"; do
    if [ -f "$d/config.toml" ]; then
      export CODEX_HOME="$d"
      return 0
    fi
  done
  # どちらも無ければ未設定のまま（Codex 既定 ~/.codex ＋ keyring に委譲）
  return 0
}
```

- [ ] **Step 4: テストを実行して成功を確認（bin 5 + home 7 = 12 ケース）**

Run: `bats tests/resolve-codex.bats`
Expected: 12 テスト全て PASS

- [ ] **Step 5: コミット**

```bash
git add scripts/resolve-codex.sh tests/resolve-codex.bats
git commit -m "feat: add cdr_resolve_codex_home two-pass CODEX_HOME detection"
```

---

## Task 3: `codex-review.sh` への統合（preflight 前倒し）

**Files:**
- Modify: `tests/resolve-codex.bats`（統合 preflight テストを追記）
- Modify: `scripts/codex-review.sh:12`（ヘッダの exit コード説明）, `scripts/codex-review.sh:31-40`（解決処理の集約）

- [ ] **Step 1: 失敗する統合テストを書く**

`tests/resolve-codex.bats` の末尾に追記:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bats tests/resolve-codex.bats -f integration`
Expected: FAIL。現行 `codex-review.sh` は `mkdir`/`cat` 後に bare `codex` を実行して失敗するため、exit は 3 でも出力は `codex exited with ...` であり `codex CLI not found` を含まない（メッセージ assert で落ちる）。

- [ ] **Step 3: `codex-review.sh` を改修**

まずヘッダの終了コード説明を更新する。`scripts/codex-review.sh:12` を以下に置換:

```bash
# 終了コード: 0=成功 / 2=verdict 不正 / 3=codex 異常終了・実行ファイル未検出(preflight) / 4=引数不正
```

次に、引数パース（`esac`）の直後・`mkdir -p "$out_dir"` の前に解決処理を集約する。現状の `codex_bin="${CDR_CODEX_BIN:-codex}"`（35 行目）と CODEX_HOME ブロック（37-40 行目）を**削除**し、`esac` の次行から以下を挿入する:

```bash
# --- codex 実行ファイル / CODEX_HOME の解決（mkdir/cat より前に preflight） ---
src="${BASH_SOURCE[0]}"
case "$src" in */*) SCRIPT_DIR="${src%/*}";; *) SCRIPT_DIR=".";; esac
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd -P)"
# shellcheck source=resolve-codex.sh
. "$SCRIPT_DIR/resolve-codex.sh"

codex_bin="$(cdr_resolve_codex_bin)" || {
  err "codex CLI not found (PATH / npm global bin / common locations). Install: 'npm i -g @openai/codex', or set CDR_CODEX_BIN."
  exit 3
}

cdr_resolve_codex_home   # CODEX_HOME を必要時のみ export
```

改修後の `codex-review.sh` 冒頭〜解決部の並びは次のとおり（`mkdir`/`verdict`/`events`/`prompt` は解決処理の**後**に残す）:

```bash
case "$cmd" in
  round1) ... ;;
  round2) ... ;;
  *) err "usage: round1|round2 ..."; exit 4 ;;
esac

# --- 解決（preflight） ---
src="${BASH_SOURCE[0]}"
case "$src" in */*) SCRIPT_DIR="${src%/*}";; *) SCRIPT_DIR=".";; esac
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd -P)"
# shellcheck source=resolve-codex.sh
. "$SCRIPT_DIR/resolve-codex.sh"
codex_bin="$(cdr_resolve_codex_bin)" || {
  err "codex CLI not found (PATH / npm global bin / common locations). Install: 'npm i -g @openai/codex', or set CDR_CODEX_BIN."
  exit 3
}
cdr_resolve_codex_home

# --- 作業ファイル準備 ---
mkdir -p "$out_dir"
verdict="$out_dir/verdict.json"
events="$out_dir/events.jsonl"
prompt="$(cat "$prompt_file")"
```

- [ ] **Step 4: テストを実行して成功を確認（統合 + 既存回帰）**

Run: `bats tests/resolve-codex.bats`
Expected: 13 テスト全て PASS

Run: `bats tests/codex-review.bats`
Expected: 既存テスト全て PASS（`CDR_CODEX_BIN` スタブを使うため preflight 即通過、reorder の影響なし）

- [ ] **Step 5: コミット**

```bash
git add scripts/codex-review.sh tests/resolve-codex.bats
git commit -m "feat: resolve codex bin/home via helper with fail-fast preflight"
```

---

## Task 4: README の前提条件を更新（両言語）

**Files:**
- Modify: `README.md:15`
- Modify: `README.ja.md:15`

- [ ] **Step 1: `README.md` の前提条件を更新**

`README.md:15` の行を以下に置換:

```markdown
- OpenAI Codex CLI installed and authenticated (`codex login status` shows "Logged in"). The skill resolves the `codex` executable automatically (PATH, then the npm global bin via `npm prefix -g`, then common install locations) and resolves `CODEX_HOME` automatically (checking `~/.codex` and `~/.config/codex`). If `codex` is managed by nvm/asdf/Volta and isn't on the hook's PATH, set `CDR_CODEX_BIN` to its full path.
```

- [ ] **Step 2: `README.ja.md` の前提条件を更新**

`README.ja.md:15` の行を以下に置換:

```markdown
- OpenAI Codex CLI がインストール済みで認証済み（`codex login status` が "Logged in" を表示）。スキルは `codex` 実行ファイル（PATH → `npm prefix -g` の npm グローバル bin → 一般的な導入場所）と `CODEX_HOME`（`~/.codex` / `~/.config/codex` を確認）を自動解決する。`codex` を nvm/asdf/Volta 管理下に置きフックの PATH に乗らない場合は、`CDR_CODEX_BIN` にフルパスを設定する。
```

- [ ] **Step 3: 日本語ガードと整合を確認**

Run: `grep -lE '[ぁ-んァ-ヶ一-龥]' README.md && echo "WARN: Japanese in README.md" || echo "OK: README.md English-only"`
Expected: `OK: README.md English-only`

- [ ] **Step 4: コミット**

```bash
git add README.md README.ja.md
git commit -m "docs: describe generalized codex bin/CODEX_HOME resolution"
```

---

## Task 5: 最終検証と PR

**Files:** （変更なし・検証のみ）

- [ ] **Step 1: 全 bats スイートを実行**

Run: `bats tests/`
Expected:
- `resolve-codex.bats`（13）/ `codex-review.bats` / `convergence.bats` / `hook.bats` / `schema.bats` / `no-japanese.bats` / `skill-structure.bats` … PASS
- **`manifest.bats` … 2 ケース FAIL は既知の既存失敗**（削除済み `.claude-plugin/marketplace.json` を参照。本タスク範囲外。spec §7）。それ以外の新規・既存失敗が無いことを確認する。

- [ ] **Step 2: 解決ロジックを実機スモーク確認**

Run:
```bash
( unset CDR_CODEX_BIN; PATH="/usr/bin:/bin" bash -c '. scripts/resolve-codex.sh; cdr_resolve_codex_bin; echo "rc=$?"' )
```
Expected: `npm prefix -g` 経由で解決された codex のパス（例: `$(npm prefix -g)/bin/codex`）が出力され `rc=0`。

- [ ] **Step 3: push して PR を作成**

```bash
git push -u origin feat/codex-path-resolution
gh pr create --base main --head feat/codex-path-resolution \
  --title "feat: harden codex bin/CODEX_HOME resolution" \
  --body "Extract codex executable + CODEX_HOME resolution into a testable scripts/resolve-codex.sh helper. Adds layered bin fallback (PATH -> npm global prefix -> common dirs) with fail-fast exit 3, and a two-pass CODEX_HOME detector (auth.json priority, config.toml fallback for keyring). Spec: docs/superpowers/specs/2026-06-14-codex-path-resolution-design.md (Codex-reviewed, converged). Note: tests/manifest.bats has a pre-existing unrelated failure (deleted marketplace.json), out of scope. 🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## スコープ外（YAGNI）

- Windows 対応（`%USERPROFILE%\.codex` 等）。
- `CODEX_HOME` 値の妥当性検証・空ディレクトリ警告。
- nvm/asdf/Volta のバージョン glob 自動探索（`CDR_CODEX_BIN` で代替）。
- 既存 `tests/manifest.bats`（削除済み `marketplace.json`）の修正 — Task 1 系の後続として別途。
