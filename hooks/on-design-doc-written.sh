#!/usr/bin/env bash
# PostToolUse hook: spec/plan ドキュメントの書き込みを検知し
# codex-design-review スキルの起動を additionalContext で指示する。
# 判定と注入のみ。Codex 実行などの重い処理は一切しない。
# フェイルセーフ: いかなるエラーでも exit 0(Write/Edit 本体を妨げない)。

set +e

# --- 入力読み取り(失敗しても黙って抜ける) ---
input="$(cat 2>/dev/null)" || exit 0
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -n "$file_path" ] || exit 0

# --- 1. 対象パス判定 ---
case "$file_path" in
  */docs/superpowers/specs/*.md) doc_kind="spec" ;;
  */docs/superpowers/plans/*.md) doc_kind="plan" ;;
  *) exit 0 ;;
esac

# --- プロジェクトルート ---
proj="${CLAUDE_PROJECT_DIR:-}"
[ -n "$proj" ] || exit 0

# --- 2. per-project 有効化マーカー ---
[ -f "$proj/.claude/codex-design-review.enabled" ] || exit 0

# --- 3. ループ中の再発火抑止(60分以内の lock のみ有効) ---
lock="$proj/.claude/.codex-design-review.lock"
if [ -f "$lock" ]; then
  # lock が 60分(3600秒)より新しければ抑止
  now="$(date +%s)"
  mtime="$(date -r "$lock" +%s 2>/dev/null || echo 0)"
  age=$(( now - mtime ))
  if [ "$age" -lt 3600 ]; then
    exit 0
  fi
fi

# --- 4. additionalContext を出力 ---
ctx="codex-design-review スキルを起動し、レビューループを実行せよ。対象ドキュメント種別: ${doc_kind}。対象パス: ${file_path}。これは ${doc_kind} ドキュメントへの書き込みを検知した自動トリガーである。"

jq -n --arg ctx "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'

exit 0
