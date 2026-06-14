#!/usr/bin/env bash
# Codex 機構を1ラウンド分カプセル化するヘルパー。
# read-only を常に強制し、verdict JSON のパスと thread_id を stdout に返す。
#
# 使い方:
#   codex-review.sh round1 <project_root> <schema_path> <prompt_file> <out_dir>
#   codex-review.sh round2 <project_root> <thread_id> <schema_path> <prompt_file> <out_dir>
#
# 出力(stdout):
#   VERDICT=<out_dir>/verdict.json
#   THREAD=<thread_id>
# 終了コード: 0=成功 / 2=verdict 不正 / 3=codex 異常終了・実行ファイル未検出(preflight) / 4=引数不正

set -uo pipefail

err() { echo "codex-review: $*" >&2; }

cmd="${1:-}"
case "$cmd" in
  round1)
    [ "$#" -eq 5 ] || { err "round1 needs 4 args"; exit 4; }
    proj="$2"; schema="$3"; prompt_file="$4"; out_dir="$5"
    ;;
  round2)
    [ "$#" -eq 6 ] || { err "round2 needs 5 args"; exit 4; }
    proj="$2"; thread_id_in="$3"; schema="$4"; prompt_file="$5"; out_dir="$6"
    ;;
  *) err "usage: round1|round2 ..."; exit 4 ;;
esac

# --- codex 実行ファイル / CODEX_HOME の解決（mkdir/cat より前に preflight） ---
src="${BASH_SOURCE[0]}"
case "$src" in */*) SCRIPT_DIR="${src%/*}";; *) SCRIPT_DIR=".";; esac
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd -P)" || { err "cannot resolve script dir"; exit 3; }
# shellcheck source=resolve-codex.sh
. "$SCRIPT_DIR/resolve-codex.sh" || { err "cannot load resolve-codex.sh (broken deployment?)"; exit 3; }

codex_bin="$(cdr_resolve_codex_bin)" || {
  err "codex CLI not found (PATH / npm global bin / common locations). Install: 'npm i -g @openai/codex', or set CDR_CODEX_BIN."
  exit 3
}

cdr_resolve_codex_home   # CODEX_HOME を必要時のみ export

mkdir -p "$out_dir"
verdict="$out_dir/verdict.json"
events="$out_dir/events.jsonl"
prompt="$(cat "$prompt_file")"

# --- codex 実行 ---
# 注: codex exec は positional プロンプトを与えても stdin を読みに行く。
# stdin が EOF にならない文脈(バックグラウンド実行・パイプ)では
# "Reading additional input from stdin..." で無限待ちする。
# よって両呼び出しとも </dev/null で stdin を閉じる(必須)。
if [ "$cmd" = "round1" ]; then
  "$codex_bin" exec \
    -C "$proj" \
    -s read-only \
    -c mcp_servers="{}" \
    --output-schema "$schema" \
    -o "$verdict" \
    --json \
    "$prompt" </dev/null > "$events" 2>>"$out_dir/stderr.log"
  rc=$?
else
  # resume: -s/-C なし。sandbox は -c で強制。cwd を proj に。
  # resume も --output-schema を渡す(実機検証 §2: resume も honor する)。
  ( cd "$proj" && "$codex_bin" exec resume "$thread_id_in" \
      -c sandbox_mode=read-only \
      -c mcp_servers="{}" \
      --output-schema "$schema" \
      -o "$verdict" \
      --json \
      "$prompt" </dev/null ) > "$events" 2>>"$out_dir/stderr.log"
  rc=$?
fi

if [ "$rc" -ne 0 ]; then
  err "codex exited with $rc"
  exit 3
fi

# --- thread_id を JSONL から取得(jq で堅牢に。空白/非JSON行に強い) ---
thread_id="$(jq -rR 'fromjson? | select(.type=="thread.started") | .thread_id' "$events" 2>/dev/null | head -1)"
[ -n "$thread_id" ] || thread_id="${thread_id_in:-}"

# --- verdict 検証 ---
if ! jq -e '.verdict.overall' "$verdict" >/dev/null 2>&1; then
  err "verdict JSON invalid or missing"
  exit 2
fi

# --- confidence の範囲チェック(schema では縛れないためコード側で) ---
conf="$(jq -r '.verdict.confidence // empty' "$verdict" 2>/dev/null)"
if [ -n "$conf" ] && ! jq -e -n --argjson c "$conf" '$c >= 0 and $c <= 1' >/dev/null 2>&1; then
  err "warning: confidence out of range [0,1]: $conf"
fi

echo "VERDICT=$verdict"
echo "THREAD=$thread_id"
exit 0
