#!/usr/bin/env bash
# 収束判定(決定論ロジック・モデル非依存)。
# 使い方: convergence.sh <r1_verdict> <r1_decisions> <r2_verdict> <r2_decisions>
#   <rN_decisions>: {"F1":"reject","F2":"accept",...} の JSON
# 出力(stdout):
#   RESULT=converged | escalate
#   UNRESOLVED=<カンマ区切り finding id>(escalate のときのみ非空)
#
# 前提: Round 2 で同一論点を再主張する際は元の finding id が維持される
#   (SKILL.md step 11 の round2 プロンプトでそれを Codex に明示している)。
#   この id 安定性により id 照合で「同一論点の2ラウンド未解決」を判定できる。

set -uo pipefail
[ "$#" -eq 4 ] || { echo "usage: convergence.sh <r1_verdict> <r1_dec> <r2_verdict> <r2_dec>" >&2; exit 2; }
r1v="$1"; r1d="$2"; r2v="$3"; r2d="$4"

overall2="$(jq -r '.verdict.overall' "$r2v" 2>/dev/null)"
if [ "$overall2" = "approved" ]; then
  echo "RESULT=converged"
  echo "UNRESOLVED="
  exit 0
fi

# r1 で reject した id 群
rejected="$(jq -r 'to_entries[] | select(.value=="reject") | .key' "$r1d" 2>/dev/null)"
# r2 で Codex が再提示した id 群
reasserted="$(jq -r '.findings[].id' "$r2v" 2>/dev/null)"

# 争点 = rejected ∩ reasserted
contested=""
for id in $reasserted; do
  if printf '%s\n' $rejected | grep -qx "$id"; then
    contested="${contested:+$contested,}$id"
  fi
done

if [ -z "$contested" ]; then
  echo "RESULT=converged"
  echo "UNRESOLVED="
else
  echo "RESULT=escalate"
  echo "UNRESOLVED=$contested"
fi
exit 0
