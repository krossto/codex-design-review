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
  prefix="$(npm prefix -g 2>/dev/null)" || true
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
