#!/usr/bin/env bash
# codex CLI のスタブ。実 API を消費せず codex-review.sh をテストする。
# シナリオは環境変数 CDR_STUB_SCENARIO で切替え:
#   approved        : round1 で approved
#   revise          : round1 で revise(指摘1件)
#   revise_approved : round1 revise / round2(resume) approved
#   unresolved      : round1 revise / round2 も revise(同一論点再主張)
#   badjson         : 不正な verdict を出力
#   badconfidence   : confidence が範囲外(1.5)の有効 verdict を出力
# 引数から -o の値(出力先)と resume か否かを判定する。

set -euo pipefail

mode="exec"
out=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    resume) mode="resume" ;;
    -o) out="${args[$((i+1))]}" ;;
  esac
done

scenario="${CDR_STUB_SCENARIO:-approved}"
thread_id="00000000-0000-7000-8000-000000000001"

# JSONL イベントを stdout に(実 codex 同様 thread.started を含める)
# CDR_STUB_SPACED=1 のとき空白入り JSON を出す(F3: jq 抽出が空白に強いことの回帰テスト用)
if [ "${CDR_STUB_SPACED:-0}" = "1" ]; then
  printf '%s\n' "{ \"type\": \"thread.started\", \"thread_id\": \"$thread_id\" }"
else
  printf '%s\n' "{\"type\":\"thread.started\",\"thread_id\":\"$thread_id\"}"
fi
printf '%s\n' '{"type":"turn.started"}'

# verdict 本文を決定
revise='{"verdict":{"overall":"revise","confidence":0.8,"summary":"issues found"},"findings":[{"id":"F1","severity":"important","section":"§4","issue":"i","why":"w","suggestion":"s"}]}'
approved='{"verdict":{"overall":"approved","confidence":0.9,"summary":"ok"},"findings":[]}'
badconf='{"verdict":{"overall":"approved","confidence":1.5,"summary":"ok"},"findings":[]}'

verdict=""
case "$scenario" in
  approved) verdict="$approved" ;;
  revise) verdict="$revise" ;;
  revise_approved) [ "$mode" = "resume" ] && verdict="$approved" || verdict="$revise" ;;
  unresolved) verdict="$revise" ;;
  badjson) verdict='{not valid json' ;;
  badconfidence) verdict="$badconf" ;;
  *) verdict="$approved" ;;
esac

if [ -n "$out" ]; then
  printf '%s' "$verdict" > "$out"
fi
printf '%s\n' '{"type":"turn.completed"}'
exit 0
