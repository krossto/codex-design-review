# codex-design-review プラグイン実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Superpowers が書く spec/plan ドキュメントを OpenAI Codex CLI にクロスモデルレビューさせる Claude Code 個人プラグインを実装する。

**Architecture:** PostToolUse hook が対象ドキュメントの書き込みを検知し、`additionalContext` で `codex-design-review` スキルの起動を指示する。スキルは Codex 機構を1ラウンド分カプセル化したヘルパースクリプト `scripts/codex-review.sh`(`codex exec` / `codex exec resume` を read-only サンドボックスで実行し、verdict JSON と thread_id を返す)を呼び、各指摘を receiving-code-review の規律で採否判定して最大2ラウンドで収束させる。Codex 機構はスタブで API 消費ゼロにテストでき、hook は bats でテストできる。モデル判断(指摘の採否・エスカレーション)は SKILL.md の散文に残す。

**Tech Stack:** bash, jq, OpenAI Codex CLI 0.138.0, bats-core(テスト), Claude Code plugin(hooks + skill)。

---

## 実機検証で確定した事実(spec §9 の回答)

実装中これらを蒸し返さないこと。`codex-cli 0.138.0` で 2026-06-10 に検証済み。

1. **thread_id 取得**: `codex exec --json` の JSONL 先頭付近に `{"type":"thread.started","thread_id":"<UUID>"}` が出る。この `thread_id` が resume 用 ID。`session_id` というフィールドは存在しない。
2. **resume のフラグ**: `codex exec resume <UUID> [OPTIONS] [PROMPT]`。`--output-schema` と `-o` は **使える**(verdict JSON が `-o` ファイルに書かれる)。ただし resume には **`-s`/`--sandbox` フラグが無い** → サンドボックスは `-c sandbox_mode="read-only"` で指定する。`-C`/`--cd` も無い → プロジェクトルートを cwd にして実行する。よって spec §6 の「resume で -o が機能しない場合のフォールバック」タスクは不要。
3. **MCP バグ(#15451)**: このユーザーの codex config に MCP サーバー設定が無いため非再現。`--output-schema`+`-o` は正常動作。防御的に `-c mcp_servers="{}"` を付けて MCP 無効を保証する。
4. **CODEX_HOME**: 認証情報は `~/.config/codex/auth.json` にあるが codex の既定 CODEX_HOME は `~/.codex`。`CODEX_HOME` 未設定だと `codex login status` が "Not logged in" になり 401 で失敗する。スクリプトは `CODEX_HOME` 未設定かつ `~/.config/codex/auth.json` が存在すれば `CODEX_HOME=~/.config/codex` を export する。
5. **per-project 有効化**: `enabledPlugins` は **ユーザーレベル** `~/.claude/settings.json` で管理され、プロジェクト単位の自動 enablement は効かない。よって hook はプロジェクト内 marker ファイル `$CLAUDE_PROJECT_DIR/.claude/codex-design-review.enabled` の存在で自己ゲートする(spec §4.6 フォールバックが本筋)。
6. **install 手順**: local marketplace 登録 → `/plugin install` → `~/.claude/settings.json` の `enabledPlugins` に `"codex-design-review@<marketplace>": true` を追加。
7. **環境変数**: hook には `${CLAUDE_PLUGIN_ROOT}`(プラグインルート)と `${CLAUDE_PROJECT_DIR}`(プロジェクトルート)が渡る。PostToolUse の stdin JSON には `tool_input.file_path` が含まれる。
8. **plugin.json**: 必須は `name`。`description`/`version`/`author`/`homepage` 等は任意。
9. **PostToolUse の additionalContext 出力形**: `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<text>"}}`。

---

## ファイル構成

各ファイルの責務を先に確定する(spec §3.1 を実機知見で微修正: テスト可能性のため Codex 機構を `scripts/codex-review.sh` に抽出。SKILL.md はこのスクリプトを呼び出すオーケストレーションに専念する)。

| パス | 責務 |
|---|---|
| `.claude-plugin/plugin.json` | プラグインマニフェスト |
| `hooks/hooks.json` | PostToolUse hook 定義(matcher + command) |
| `hooks/on-design-doc-written.sh` | トリガー判定スクリプト。判定と additionalContext 注入のみ。重い処理は一切しない |
| `scripts/codex-review.sh` | Codex 機構を1ラウンド分カプセル化。`round1`(exec)/`round2`(resume)、CODEX_HOME 解決、read-only 強制、verdict 検証。`CDR_CODEX_BIN` で codex バイナリ差し替え可能 |
| `scripts/convergence.sh` | 収束判定の決定論ロジック。round1/round2 の verdict と decisions を受け、converged/escalate と争点 id を返す(モデル非依存・テスト可能) |
| `skills/codex-design-review/SKILL.md` | レビューループ手順(本体・散文)。codex-review.sh を呼び、指摘採否を判定し収束させる |
| `skills/codex-design-review/reviewer-prompt-spec.md` | spec 用レビュアープロンプト雛形 |
| `skills/codex-design-review/reviewer-prompt-plan.md` | plan 用レビュアープロンプト雛形 |
| `schemas/verdict-schema.json` | Codex 構造化出力スキーマ(JSON Schema) |
| `tests/codex-stub.sh` | `codex` バイナリのスタブ。シナリオを env で切替え canned verdict を出力 |
| `tests/hook.bats` | hook 判定テスト |
| `tests/codex-review.bats` | codex-review.sh のテスト(スタブ使用) |
| `tests/convergence.bats` | convergence.sh のテスト(spec §7 の3シナリオ) |
| `tests/schema.bats` | verdict-schema.json / plugin.json / hooks.json の妥当性テスト |
| `README.md` | 導入・有効化手順 |

---

## Task 1: リポジトリ scaffolding とテスト基盤

**Files:**
- Create: `.gitignore`
- Create: `.claude-plugin/plugin.json`
- Create: `tests/schema.bats`

- [ ] **Step 1: bats-core をインストール(未導入なら)**

Run:
```bash
command -v bats || npm install -g bats
bats --version
```
Expected: `Bats 1.x.x`(npm global prefix は `~/.npm-global` でユーザー書込み可。sudo 不要)

- [ ] **Step 2: .gitignore を作成**

Create `.gitignore`:
```gitignore
# 一時ファイル(レビュー実行時の verdict / events)
/tmp-cdr/
*.log
# ローカルの有効化マーカー(プロジェクト側に置くものなのでこのリポには不要)
.claude/codex-design-review.enabled
.claude/.codex-design-review.lock
```

- [ ] **Step 3: plugin.json の妥当性テストを書く(失敗する)**

Create `tests/schema.bats`:
```bash
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "plugin.json is valid JSON" {
  run jq empty "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
}

@test "plugin.json has name codex-design-review" {
  run jq -r '.name' "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "codex-design-review" ]
}
```

- [ ] **Step 4: テストが失敗することを確認**

Run: `bats tests/schema.bats`
Expected: FAIL(`.claude-plugin/plugin.json` が存在しない)

- [ ] **Step 5: plugin.json を作成**

Create `.claude-plugin/plugin.json`:
```json
{
  "name": "codex-design-review",
  "version": "0.1.0",
  "description": "Cross-model review of Superpowers spec/plan documents by OpenAI Codex CLI",
  "author": {
    "name": "krossto"
  },
  "keywords": ["superpowers", "code-review", "codex", "cross-model"]
}
```

- [ ] **Step 6: テストが通ることを確認**

Run: `bats tests/schema.bats`
Expected: PASS(2 tests)

- [ ] **Step 7: Commit**

```bash
git add .gitignore .claude-plugin/plugin.json tests/schema.bats
git commit -m "feat: plugin manifest and test harness scaffolding"
```

---

## Task 2: verdict スキーマ

**Files:**
- Create: `schemas/verdict-schema.json`
- Modify: `tests/schema.bats`

- [ ] **Step 1: スキーマの妥当性テストを追記(失敗する)**

`tests/schema.bats` の末尾に追記:
```bash
@test "verdict-schema.json is valid JSON" {
  run jq empty "$ROOT/schemas/verdict-schema.json"
  [ "$status" -eq 0 ]
}

@test "verdict-schema requires verdict and findings" {
  run jq -r '.required | sort | join(",")' "$ROOT/schemas/verdict-schema.json"
  [ "$output" = "findings,verdict" ]
}

@test "verdict-schema is strict (additionalProperties false)" {
  run jq -r '.additionalProperties' "$ROOT/schemas/verdict-schema.json"
  [ "$output" = "false" ]
}

@test "a sample verdict conforms structurally" {
  sample='{"verdict":{"overall":"revise","confidence":0.8,"summary":"x"},"findings":[{"id":"F1","severity":"important","section":"§4","issue":"i","why":"w","suggestion":"s"}]}'
  run bash -c "echo '$sample' | jq -e '.verdict.overall and .findings[0].suggestion'"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bats tests/schema.bats`
Expected: FAIL(`schemas/verdict-schema.json` 不在)

- [ ] **Step 3: verdict-schema.json を作成**

Create `schemas/verdict-schema.json`(OpenAI 構造化出力の strict 仕様: 全 object に `additionalProperties:false` と全プロパティを `required`):
```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["verdict", "findings"],
  "properties": {
    "verdict": {
      "type": "object",
      "additionalProperties": false,
      "required": ["overall", "confidence", "summary"],
      "properties": {
        "overall": {
          "type": "string",
          "enum": ["approved", "revise"],
          "description": "approved = 重大な指摘なし。revise = 対応すべき指摘あり"
        },
        "confidence": {
          "type": "number",
          "description": "0.0-1.0。レビュー全体の確信度"
        },
        "summary": {
          "type": "string",
          "description": "全体講評(短文)"
        }
      }
    },
    "findings": {
      "type": "array",
      "description": "actionable な指摘のみ。各指摘に具体的な修正案を必ず添える",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "severity", "section", "issue", "why", "suggestion"],
        "properties": {
          "id": {"type": "string", "description": "F1, F2, ... の連番"},
          "severity": {"type": "string", "enum": ["critical", "important", "minor"]},
          "section": {"type": "string", "description": "対象セクション名/見出し"},
          "issue": {"type": "string", "description": "何が問題か"},
          "why": {"type": "string", "description": "なぜ問題か"},
          "suggestion": {"type": "string", "description": "具体的な修正案"}
        }
      }
    }
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `bats tests/schema.bats`
Expected: PASS(6 tests)

- [ ] **Step 5: Commit**

```bash
git add schemas/verdict-schema.json tests/schema.bats
git commit -m "feat: add Codex verdict JSON schema"
```

---

## Task 3: トリガー判定 hook スクリプト

**Files:**
- Create: `hooks/on-design-doc-written.sh`
- Create: `tests/hook.bats`

判定仕様(spec §4.2 + 実機知見 §5):
1. stdin JSON の `tool_input.file_path` が `*/docs/superpowers/specs/*.md` または `*/docs/superpowers/plans/*.md` にマッチするか。
2. `$CLAUDE_PROJECT_DIR/.claude/codex-design-review.enabled`(marker)が存在するか。無ければ即 exit 0(per-project ゲート)。
3. `$CLAUDE_PROJECT_DIR/.claude/.codex-design-review.lock` が存在し、かつ 60 分以内なら exit 0(ループ中の再発火抑止)。古い lock は無視。
4. 全条件成立時のみ additionalContext を出力。
5. **いかなるエラーでも exit 0**(Write/Edit 本体を妨げない)。

- [ ] **Step 1: hook テストを書く(失敗する)**

Create `tests/hook.bats`:
```bash
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."
HOOK="$ROOT/hooks/on-design-doc-written.sh"

setup() {
  PROJ="$(mktemp -d)"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/superpowers/specs" "$PROJ/docs/superpowers/plans"
  export CLAUDE_PROJECT_DIR="$PROJ"
}

teardown() {
  rm -rf "$PROJ"
}

# 入力JSONを組み立てて hook に流す
run_hook() {
  local fp="$1"
  echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$fp\"}}" | bash "$HOOK"
}

@test "spec path with marker present -> injects additionalContext" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("codex-design-review")'
}

@test "plan path with marker present -> injects" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/docs/superpowers/plans/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext'
}

@test "no marker -> silent exit 0, no output" {
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-target path -> silent exit 0" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/src/main.py"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "README under docs but not specs/plans -> no inject" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run run_hook "$PROJ/docs/superpowers/README.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fresh lock present -> suppressed" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  touch "$PROJ/.claude/.codex-design-review.lock"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stale lock (>60min) -> not suppressed" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  touch "$PROJ/.claude/.codex-design-review.lock"
  touch -d "90 minutes ago" "$PROJ/.claude/.codex-design-review.lock"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext'
}

@test "malformed stdin -> exit 0, no crash" {
  touch "$PROJ/.claude/codex-design-review.enabled"
  run bash -c "echo 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bats tests/hook.bats`
Expected: FAIL(`hooks/on-design-doc-written.sh` 不在)

- [ ] **Step 3: hook スクリプトを実装**

Create `hooks/on-design-doc-written.sh`:
```bash
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
```

- [ ] **Step 4: 実行権限を付与**

Run: `chmod +x hooks/on-design-doc-written.sh`

- [ ] **Step 5: テストが通ることを確認**

Run: `bats tests/hook.bats`
Expected: PASS(8 tests)

- [ ] **Step 6: Commit**

```bash
git add hooks/on-design-doc-written.sh tests/hook.bats
git commit -m "feat: PostToolUse trigger hook with per-project gate and re-fire lock"
```

---

## Task 4: hooks.json 配線

**Files:**
- Create: `hooks/hooks.json`
- Modify: `tests/schema.bats`

- [ ] **Step 1: hooks.json の妥当性テストを追記(失敗する)**

`tests/schema.bats` の末尾に追記:
```bash
@test "hooks.json is valid JSON" {
  run jq empty "$ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
}

@test "hooks.json registers a PostToolUse hook" {
  run jq -e '.hooks.PostToolUse[0].hooks[0].command' "$ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
}

@test "hooks.json matcher targets Write/Edit tools" {
  run jq -r '.hooks.PostToolUse[0].matcher' "$ROOT/hooks/hooks.json"
  [ "$output" = "Write|Edit|MultiEdit" ]
}

@test "hooks.json command references on-design-doc-written.sh via CLAUDE_PLUGIN_ROOT" {
  run jq -r '.hooks.PostToolUse[0].hooks[0].command' "$ROOT/hooks/hooks.json"
  [[ "$output" == *'${CLAUDE_PLUGIN_ROOT}'* ]]
  [[ "$output" == *"on-design-doc-written.sh"* ]]
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bats tests/schema.bats`
Expected: FAIL(`hooks/hooks.json` 不在)

- [ ] **Step 3: hooks.json を作成**

Create `hooks/hooks.json`:
```json
{
  "description": "codex-design-review: detect spec/plan writes and trigger the cross-model review skill",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/on-design-doc-written.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `bats tests/schema.bats`
Expected: PASS(10 tests)

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json tests/schema.bats
git commit -m "feat: wire PostToolUse hook in hooks.json"
```

---

## Task 5: Codex 機構ヘルパー `codex-review.sh` とスタブ

**Files:**
- Create: `scripts/codex-review.sh`
- Create: `tests/codex-stub.sh`
- Create: `tests/codex-review.bats`

`codex-review.sh` の契約:
- 使い方: `codex-review.sh round1 <project_root> <schema_path> <prompt_file> <out_dir>` / `codex-review.sh round2 <project_root> <thread_id> <schema_path> <prompt_file> <out_dir>`
  (round2 も **schema_path を取り**、resume に `--output-schema` を渡す。実機検証 §2 で resume も `--output-schema`/`-o` を honor すると確認済み。)
- `<prompt_file>` の中身をプロンプトとして渡す(長文を引数に詰めない)。
- read-only を**常に**強制(round1 は `-s read-only`、round2 は `-c sandbox_mode="read-only"`)。MCP は `-c mcp_servers="{}"` で無効化。
- CODEX_HOME 未設定かつ `~/.config/codex/auth.json` があれば export。
- thread_id は **JSONL を jq で**読んで取得(`grep` 依存にしない。空白入り JSONL でも壊れないため)。
- 成功時、stdout に2行を出力: 1行目 `VERDICT=<path>`(verdict JSON のパス)、2行目 `THREAD=<thread_id>`。verdict ファイルは `<out_dir>/verdict.json`、events は `<out_dir>/events.jsonl`。
- codex バイナリは `${CDR_CODEX_BIN:-codex}`。
- verdict JSON が不正(jq で `.verdict.overall` が取れない)なら exit 2。codex 自体が非0なら exit 3。
- verdict 検証時、`.verdict.confidence` が 0.0-1.0 の範囲外なら警告を stderr に出す(schema 側で `minimum`/`maximum` を縛ると OpenAI structured output が未対応キーワードで弾く恐れがあるため、範囲チェックはコード側で行う)。

- [ ] **Step 1: codex スタブを作成(テスト用の差し替えバイナリ)**

Create `tests/codex-stub.sh`:
```bash
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
```

Run: `chmod +x tests/codex-stub.sh`

- [ ] **Step 2: codex-review.sh のテストを書く(失敗する)**

Create `tests/codex-review.bats`:
```bash
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
```

- [ ] **Step 3: テストが失敗することを確認**

Run: `bats tests/codex-review.bats`
Expected: FAIL(`scripts/codex-review.sh` 不在)

- [ ] **Step 4: codex-review.sh を実装**

Create `scripts/codex-review.sh`:
```bash
#!/usr/bin/env bash
# Codex 機構を1ラウンド分カプセル化するヘルパー。
# read-only を常に強制し、verdict JSON のパスと thread_id を stdout に返す。
#
# 使い方:
#   codex-review.sh round1 <project_root> <schema_path> <prompt_file> <out_dir>
#   codex-review.sh round2 <project_root> <thread_id>   <prompt_file> <out_dir>
#
# 出力(stdout):
#   VERDICT=<out_dir>/verdict.json
#   THREAD=<thread_id>
# 終了コード: 0=成功 / 2=verdict 不正 / 3=codex 異常終了 / 4=引数不正

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

mkdir -p "$out_dir"
verdict="$out_dir/verdict.json"
events="$out_dir/events.jsonl"
prompt="$(cat "$prompt_file")"
codex_bin="${CDR_CODEX_BIN:-codex}"

# --- CODEX_HOME 解決(実機知見 §4) ---
if [ -z "${CODEX_HOME:-}" ] && [ -f "$HOME/.config/codex/auth.json" ]; then
  export CODEX_HOME="$HOME/.config/codex"
fi

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
```

- [ ] **Step 5: 実行権限を付与**

Run: `chmod +x scripts/codex-review.sh`

- [ ] **Step 6: テストが通ることを確認**

Run: `bats tests/codex-review.bats`
Expected: PASS(8 tests)

- [ ] **Step 7: Commit**

```bash
git add scripts/codex-review.sh tests/codex-stub.sh tests/codex-review.bats
git commit -m "feat: codex-review.sh helper with read-only enforcement and stub-based tests"
```

---

## Task 6: 収束判定ロジック `convergence.sh`

spec §7 が求める「approved / revise→approved / 2ラウンド不一致」の3シナリオを **API 消費ゼロかつモデル非依存**で検証できるよう、収束判定(ループ制御の中核)を決定論スクリプトに抽出する。指摘の採否判断そのものはモデル(SKILL.md)が行い、その結果(各 finding への accept/reject/hold)を JSON で渡す。

**Files:**
- Create: `scripts/convergence.sh`
- Create: `tests/convergence.bats`

`convergence.sh` の契約:
- 使い方: `convergence.sh <r1_verdict> <r1_decisions> <r2_verdict> <r2_decisions>`
- `<rN_decisions>`: `{"F1":"reject","F2":"accept"}` 形式の JSON(その指摘への Claude の判断)。
- 出力(stdout): 1行目 `RESULT=converged` か `RESULT=escalate`、2行目 `UNRESOLVED=<カンマ区切り finding id>`(escalate 時のみ非空)。
- 規則:
  1. `r2_verdict.overall == "approved"` → converged。
  2. それ以外で、**r1 で reject した指摘のうち r2 で Codex が再提示した id** = 争点。争点が無ければ converged、あれば escalate(その id 群を返す)。

- [ ] **Step 1: convergence のテストを書く(失敗する)**

Create `tests/convergence.bats`:
```bash
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `bats tests/convergence.bats`
Expected: FAIL(`scripts/convergence.sh` 不在)

- [ ] **Step 3: convergence.sh を実装**

Create `scripts/convergence.sh`:
```bash
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
```

- [ ] **Step 4: 実行権限を付与**

Run: `chmod +x scripts/convergence.sh`

- [ ] **Step 5: テストが通ることを確認**

Run: `bats tests/convergence.bats`
Expected: PASS(4 tests)

- [ ] **Step 6: Commit**

```bash
git add scripts/convergence.sh tests/convergence.bats
git commit -m "feat: deterministic convergence logic with 3-scenario tests (spec §7)"
```

---

## Task 7: レビュアープロンプト雛形

**Files:**
- Create: `skills/codex-design-review/reviewer-prompt-spec.md`
- Create: `skills/codex-design-review/reviewer-prompt-plan.md`

これらはプロンプト本文の雛形(散文)。SKILL.md が対象パスを差し込んで prompt_file に書き出す。テスト対象外(手動受け入れで検証)。

- [ ] **Step 1: spec 用プロンプトを作成**

Create `skills/codex-design-review/reviewer-prompt-spec.md`:
```markdown
あなたは、別の AI エージェント(Claude)が作成した**設計文書(spec)**のレビュアーです。
誠実かつ、やや批判的ではあるが建設的に振る舞ってください。迎合は不要です。

## まず文脈を取得せよ
このリポジトリは read-only で探索できます。判断の前に次を読むこと:
- AGENTS.md / CLAUDE.md / README(あれば)
- 対象 spec が参照する関連コード・既存設計

一般論ではなく、**このプロジェクトの現実**に基づく指摘のみを行うこと。

## レビュー対象
{{TARGET_PATH}}
(関連参照先: {{REFERENCES}})

## 観点
- 完全性: TBD / placeholder / 未決事項が残っていないか
- 内部整合性: 矛盾する記述、定義されず使われる用語・前提
- 曖昧さ: 複数解釈できる仕様、測定不能な要件
- 過剰設計(YAGNI): 要求に対し不要な複雑さ・抽象化
- 実現可能性: 技術的に成立しない前提、未検証の依存
- 見落とされたリスク・エッジケース

## 出力
- 指定された JSON Schema(verdict)に厳密に従うこと。
- 指摘は **actionable なものだけ**。各指摘には `suggestion` として**具体的な修正案を必ず添える**こと。
- 重大な問題が無ければ `overall: "approved"`、findings は空配列にせよ。
```

- [ ] **Step 2: plan 用プロンプトを作成**

Create `skills/codex-design-review/reviewer-prompt-plan.md`:
```markdown
あなたは、別の AI エージェント(Claude)が作成した**実装プラン(plan)**のレビュアーです。
誠実かつ、やや批判的ではあるが建設的に振る舞ってください。迎合は不要です。

## まず文脈を取得せよ
このリポジトリは read-only で探索できます。判断の前に次を読むこと:
- AGENTS.md / CLAUDE.md / README(あれば)
- 対応する spec(`docs/superpowers/specs/**`)と、プランが触れる既存コード

一般論ではなく、**このプロジェクトの現実**に基づく指摘のみを行うこと。

## レビュー対象
{{TARGET_PATH}}
(対応 spec / 関連参照先: {{REFERENCES}})

## 観点
- spec との整合: 過不足、スコープクリープ、spec にない独断
- タスク分解の妥当性: bite-sized か、依存順序は正しいか
- TDD 手順の有無: 各タスクに失敗するテスト→実装→検証のサイクルがあるか
- 検証ステップの有無: 各タスクに実行コマンドと期待結果が書かれているか
- placeholder: TBD / 「適切に処理」等のごまかしが無いか

## 出力
- 指定された JSON Schema(verdict)に厳密に従うこと。
- 指摘は **actionable なものだけ**。各指摘には `suggestion` として**具体的な修正案を必ず添える**こと。
- 重大な問題が無ければ `overall: "approved"`、findings は空配列にせよ。
```

- [ ] **Step 3: Commit**

```bash
git add skills/codex-design-review/reviewer-prompt-spec.md skills/codex-design-review/reviewer-prompt-plan.md
git commit -m "feat: spec and plan reviewer prompt templates"
```

---

## Task 8: SKILL.md(レビューループ本体)

**Files:**
- Create: `skills/codex-design-review/SKILL.md`

レビューループのオーケストレーション(散文)。codex-review.sh を呼び、各指摘を receiving-code-review の規律で採否判定し、最大2ラウンドで収束させ、未解決論点はユーザーに三択を提示する。

- [ ] **Step 1: SKILL.md を作成**

Create `skills/codex-design-review/SKILL.md`:
````markdown
---
name: codex-design-review
description: Use when a Superpowers spec or plan document under docs/superpowers/{specs,plans} has just been written or edited, to get an independent cross-model review from OpenAI Codex. Triggered automatically by the codex-design-review PostToolUse hook. Runs a bounded 2-round review loop, judges each finding with technical rigor, and escalates unresolved disagreements to the user.
---

# Codex Design Review(クロスモデルレビューループ)

別モデル(OpenAI Codex)に spec/plan を独立レビューさせ、指摘を技術的に吟味して反映する。
Claude と Codex は訓練系統が異なるため、自己レビューでは見えないミスを拾える。

**この skill を起動したら、まず TodoWrite に下記チェックリストを登録すること。**

## 0. スキップ判定(最初に必ず行う)

直前の編集が **typo 修正・体裁調整など設計内容に実質的変更が無い**ものなら、レビューを**スキップ**し、その旨を一言ユーザーに報告して通常フローへ戻る(例: 「軽微な編集のためクロスモデルレビューはスキップしました」)。判断はあなたに委ねるが、**スキップ時も必ず報告**すること(黙殺禁止)。

実質的な設計変更・新規作成ならレビューを実行する。

## 前処理

1. **対象を特定**: トリガーが渡した「対象ドキュメント種別(spec/plan)」と「対象パス」を確認。プロジェクトルートは `$CLAUDE_PROJECT_DIR`。
2. **ロック作成**(再発火抑止): `touch "$CLAUDE_PROJECT_DIR/.claude/.codex-design-review.lock"`。
   このロックは**必ず最後に削除**する。途中でエラーになっても削除すること(下記「完了処理」)。
3. **作業ディレクトリ**: `mkdir -p "$CLAUDE_PROJECT_DIR/tmp-cdr"` と、レビュー記録用に `mkdir -p "$CLAUDE_PROJECT_DIR/docs/superpowers/reviews"`。
4. **実行 ID**: `uuid=$(uuidgen)`。出力先 `out1="$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-r1"`。

## Round 1

5. **プロンプト生成**: 種別に応じて `reviewer-prompt-spec.md` か `reviewer-prompt-plan.md` を読み、`{{TARGET_PATH}}` を対象パスに、`{{REFERENCES}}` をあなたが把握している関連参照(対応 spec のパス等)に置換し、`$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-prompt.md` に書き出す。
6. **Codex 実行**(read-only・バックグラウンド・最大15分)。Bash を `run_in_background: true` で:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/codex-review.sh" round1 \
     "$CLAUDE_PROJECT_DIR" \
     "$CLAUDE_PLUGIN_ROOT/schemas/verdict-schema.json" \
     "$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-prompt.md" \
     "$out1"
   ```
   完了を待つ。15分を超えたらジョブを停止し、ユーザーに報告してスキップ(完了処理へ)。
7. **結果取得**: stdout の `VERDICT=` から verdict パス、`THREAD=` から thread_id を取得。
   - スクリプトが exit 2(verdict 不正)→ フォーマット注意を添えて**1回だけ**再実行。再失敗ならユーザーに報告してスキップ。
   - exit 3(codex 異常: CLI 不在・認証切れ等)→ レビューをスキップし、理由をユーザーに通知して通常フロー続行。
8. **指摘の吟味**: `findings` を列挙し、**各指摘を superpowers:receiving-code-review の規律で技術的に検証**する。迎合せず、このコードベースの現実に照らして **採用(accept)/ 拒否(reject)/ 保留(hold)** を理由付きで決める。
   - 判断結果を機械可読な **decisions JSON**(`{"F1":"reject","F2":"accept",...}`)として `$out1/decisions.json` に書き出す(収束判定 convergence.sh に渡すため)。
9. **判断ドキュメント出力**: `docs/superpowers/reviews/YYYY-MM-DD-<topic>-codex-round1.md` を書く(フォーマットは下記、人間向け)。
10. **採用分を反映**: 採用(accept)した指摘を対象 spec/plan に反映する。

## Round 2

11. **再レビュー**(resume)。`out2="$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-r2"`。round2 用プロンプトを生成: 「判断ドキュメント(<round1 のパス>)の拒否理由を読み、納得なら取り下げ、納得できなければ理由を添えて再主張せよ。**Round 1 の指摘を再主張する場合は、元の finding id をそのまま維持すること**(収束判定が id で同一論点を照合するため)。更新済みドキュメント: <対象パス>」を `tmp-cdr/$uuid-prompt2.md` に書き出し:
    ```bash
    bash "$CLAUDE_PLUGIN_ROOT/scripts/codex-review.sh" round2 \
      "$CLAUDE_PROJECT_DIR" \
      "<round1 で取得した thread_id>" \
      "$CLAUDE_PLUGIN_ROOT/schemas/verdict-schema.json" \
      "$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-prompt2.md" \
      "$out2"
    ```
    `run_in_background: true`、完了待ち。
12. **同様に吟味**し、`$out2/decisions.json` と判断ドキュメント `...-codex-round2.md` を出力。採用分を反映。

## 収束判定

決定論的な収束判定は **convergence.sh** に委譲する(モデルの吟味結果=decisions.json を入力にする):

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/convergence.sh" \
  "$out1/verdict.json" "$out1/decisions.json" \
  "$out2/verdict.json" "$out2/decisions.json"
```

- 出力 `RESULT=converged` → **完了**(下記「完了処理」へ)。
- 出力 `RESULT=escalate` → `UNRESOLVED=` に挙がった**争点(Claude が拒否し Codex が再主張した指摘)だけ**を抜き出し、`AskUserQuestion` で三択を提示:
  1. Codex 案を採用
  2. Claude 案を維持
  3. 保留(ドキュメントに保留として記録)
  ユーザー裁定を判断ドキュメントに追記してから完了処理へ。
- **ラウンド上限は 2 で固定**。

## 完了処理(必ず実行)

- **ロック削除**: `rm -f "$CLAUDE_PROJECT_DIR/.claude/.codex-design-review.lock"`。エラーで中断する場合も削除すること。
- **一時ファイル削除**: `rm -rf "$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid"*`。
- **完了サマリ**をユーザーへ出力: 指摘数 / 採用 / 拒否 / 保留 の件数と、判断ドキュメントのパス。
- 通常フローへ復帰。

## 判断ドキュメントのフォーマット

```markdown
# Codex レビュー判断: <対象ドキュメント名> (round N)

- 対象: <対象パス>
- ラウンド: N
- Codex thread_id: <thread_id>
- overall: <approved|revise>  / confidence: <0.0-1.0>
- 講評: <summary>

| ID | 深刻度 | 指摘(要約) | 判断 | 理由 |
|---|---|---|---|---|
| F1 | important | … | 採用 / 拒否 / 保留 / ユーザー裁定 | … |
```

## 安全・運用の不変条件

- Codex は**常に read-only**(codex-review.sh が強制)。`--dangerously-*` は使用禁止。
- 1 ドキュメントあたり Codex 呼び出しは**最大 2 回**。それ以上は構造的に発生しない。
- codex CLI が無い / 認証切れ / タイムアウト → **ブロックせずスキップ**し、必ずユーザーに報告。
````

- [ ] **Step 2: SKILL.md が読めることを軽く確認**

Run: `head -5 skills/codex-design-review/SKILL.md`
Expected: frontmatter の `name: codex-design-review` が見える

- [ ] **Step 3: Commit**

```bash
git add skills/codex-design-review/SKILL.md
git commit -m "feat: codex-design-review SKILL.md review loop"
```

---

## Task 9: README(導入・有効化手順)

**Files:**
- Create: `README.md`

- [ ] **Step 1: README を作成**

Create `README.md`:
```markdown
# codex-design-review

Superpowers が作成する spec / plan ドキュメントを OpenAI Codex CLI に
クロスモデルレビューさせる Claude Code 個人プラグイン。

## 仕組み

1. PostToolUse hook が `docs/superpowers/{specs,plans}/**/*.md` への書き込みを検知。
2. プロジェクトに有効化マーカーがあれば `codex-design-review` スキルの起動を指示。
3. スキルが Codex を read-only で最大2ラウンド実行し、指摘を吟味・反映。

## 前提

- OpenAI Codex CLI 0.138.0+ が認証済み(`codex login status` が "Logged in")。
  認証情報が `~/.config/codex` にある場合、スキルは自動で `CODEX_HOME` を解決する。
- `jq`, `uuidgen` が利用可能。

## 導入

1. ローカル marketplace に登録し、インストール(初回のみ):
   ```
   /plugin marketplace add <このリポジトリのパス または URL>
   /plugin install codex-design-review
   ```
2. ユーザー設定 `~/.claude/settings.json` の `enabledPlugins` に追加:
   ```json
   { "enabledPlugins": { "codex-design-review@<marketplace-name>": true } }
   ```

## プロジェクトでの有効化

レビューを有効にしたいプロジェクトで、マーカーファイルを置いてコミットする:

```
mkdir -p .claude
touch .claude/codex-design-review.enabled
git add .claude/codex-design-review.enabled
git commit -m "chore: enable codex-design-review"
```

マーカーが無いプロジェクトでは hook は即終了し、何もしない。

## テスト

```
bats tests/
```

## スコープ外(YAGNI)

実装コード/テストコードのレビュー、複数レビュアー、他モデル対応、CI 統合、
ラウンド数・観点のプロジェクト別カスタマイズ。
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install and enablement instructions"
```

---

## Task 10: 全テスト実行と受け入れテスト(手動・実 API 1回)

**Files:** なし(検証のみ)

- [ ] **Step 1: 全 bats テストを実行**

Run: `bats tests/`
Expected: 全テスト PASS(schema 10 + hook 8 + codex-review 8 + convergence 4 = 30 tests 前後)

- [ ] **Step 2: 受け入れテスト用サンドボックスを用意**

Run:
```bash
SBX="$(mktemp -d)/sandbox-proj"
mkdir -p "$SBX/.claude" "$SBX/docs/superpowers/specs"
touch "$SBX/.claude/codex-design-review.enabled"
git -C "$SBX" init -q
echo "sandbox at: $SBX"
```

- [ ] **Step 3: hook を手動発火させて additionalContext が出ることを確認**

Run:
```bash
export CLAUDE_PROJECT_DIR="$SBX"
echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SBX/docs/superpowers/specs/2026-06-10-test.md\"}}" \
  | bash hooks/on-design-doc-written.sh
```
Expected: `hookSpecificOutput.additionalContext` を含む JSON が出力される

- [ ] **Step 4: codex-review.sh を実 Codex で1回実行(実 API)**

サンドボックスに短い spec を書き、**実 reviewer prompt template に対象パスを差し込んで** round1 を実行(本番経路の検証):
```bash
TGT="$SBX/docs/superpowers/specs/2026-06-10-test.md"
cat > "$TGT" <<'EOF'
# テスト spec
ボタンを押すと TODO が増える。永続化は未定(TBD)。エラー処理は適切に行う。
EOF
# 実テンプレートのプレースホルダを差し替えてプロンプトを生成
sed -e "s#{{TARGET_PATH}}#$TGT#" -e "s#{{REFERENCES}}#(なし)#" \
  skills/codex-design-review/reviewer-prompt-spec.md > /tmp/cdr-accept-prompt.md
bash scripts/codex-review.sh round1 "$SBX" \
  "$PWD/schemas/verdict-schema.json" \
  /tmp/cdr-accept-prompt.md \
  "$SBX/tmp-cdr/accept-r1"
echo "--- verdict ---"
cat "$SBX/tmp-cdr/accept-r1/verdict.json" | jq .
```
Expected: `VERDICT=` と `THREAD=` が出力され、verdict.json が schema 準拠(TBD / 「適切に」を指摘するはず)。`overall` は `revise`。

- [ ] **Step 5: resume(round2)を実 Codex で1回実行**

```bash
TID=$(jq -rR 'fromjson? | select(.type=="thread.started") | .thread_id' "$SBX/tmp-cdr/accept-r1/events.jsonl" | head -1)
echo "指摘は了解した。承認なら approved を返せ。" > /tmp/cdr-accept-prompt2.md
bash scripts/codex-review.sh round2 "$SBX" "$TID" \
  "$PWD/schemas/verdict-schema.json" \
  /tmp/cdr-accept-prompt2.md \
  "$SBX/tmp-cdr/accept-r2"
cat "$SBX/tmp-cdr/accept-r2/verdict.json" | jq .
```
Expected: resume が成功し verdict.json が出力される(read-only が守られていること)。

- [ ] **Step 6: 後片付け**

Run:
```bash
rm -rf "$SBX" /tmp/cdr-accept-prompt*.md
```

- [ ] **Step 7: 受け入れ結果を記録してコミット(任意)**

受け入れテストが通ったことを確認したら完了。コード変更が無ければコミット不要。

---

## 自己レビュー結果(spec との突き合わせ)

- spec §2 確定事項 1-7: すべてプランに反映(レビュー対象 spec/plan のみ=Task 7-8、プロジェクト単位=Task 3 marker、エスカレーション三択=Task 8、独立性=プロンプトに思考履歴を渡さない設計、文脈取得=Codex 自身が `-C`+read-only 探索、トリガー=exec+resume=Task 5、配布=個人プラグイン=Task 1)。
- spec §4.1-4.6: plugin.json=T1、hook=T3/T4、skill=T8、プロンプト=T7、verdict/判断ドキュメント=T2/T8、有効化=T3/T9。
- spec §5 安全要件: read-only 強制=T5(round1 `-s`/round2 `-c sandbox_mode`)、MCP 無効=T5(`-c mcp_servers="{}"`)、タイムアウト 15分=T8、コスト最大2回=T8。
- spec §6 エラー処理: CLI 不在/認証切れ=T5 exit 3 → T8 スキップ、verdict 不正=T5 exit 2 → T8 1回再実行、hook 内エラー=T3 常に exit 0、タイムアウト=T8。**resume の -o フォールバックは実機検証で不要と判明したため除外**(プラン冒頭の確定事実 2)。session id 取得不能時の新規 exec 代替は、実機で thread_id が安定取得できたため通常パスに含めない(取得失敗時は round2 をスキップ扱い)。
- spec §7 テスト戦略: Codex スタブ=T5、**3シナリオ(approved/revise→approved/2ラウンド不一致)の収束判定は convergence.sh で決定論的に検証=T6**(`tests/convergence.bats`)、hook bats=T3、受け入れ=T10。モデルによる指摘採否そのものは本質的にテスト不能なため、判断結果(decisions JSON)を入力とする収束ロジックのみを切り出してテストする。
- spec §9 検証事項: 全項目をプラン作成前に実機検証済み(冒頭「実機検証で確定した事実」)。
- **Codex round1 レビュー(2026-06-10)反映**: F1(round2 に `--output-schema` 追加)、F2(convergence.sh 抽出=T6)、F3(thread_id を jq で抽出)、F4(confidence 範囲はコード側検証)、F5(受け入れテストで実 prompt template 使用)を採用済み。判断ドキュメント: `docs/superpowers/reviews/2026-06-10-codex-design-review-plan-codex-round1.md`。
````

