# 一般配布対応リファクタ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** codex-design-review プラグインを一般配布レディにする — 起動を Claude Code ネイティブ scope に一本化（フラグ廃止）、配布物を英語統一（日本語 README 別建て）、skill 名短縮、Superpowers ソフト依存の明示＋フォールバック。

**Architecture:** 既存プラグイン（skill + PostToolUse hook + scripts + schema + tests）の振る舞い・体裁を整える。コアのレビュー機構（codex-review.sh / convergence.sh / `/tmp` 作業ディレクトリ）は無改修。skill ディレクトリ改名を最初に行い、以降の編集は新パスを対象にする。

**Tech Stack:** Bash（hook）、bats（テスト）、JSON（manifest/schema）、Markdown（SKILL/README/prompts）。

**Spec:** `docs/superpowers/specs/2026-06-11-general-distribution-readiness-design.md`

---

## File Structure

| ファイル | 操作 | 責務 |
|---|---|---|
| `skills/review/SKILL.md` | Rename + Modify | 旧 `skills/codex-design-review/SKILL.md`。frontmatter `name: review`、英語化、フラグ記述削除、B フォールバック |
| `skills/review/reviewer-prompt-{spec,plan}.md` | Rename + Modify | 英語化 |
| `hooks/on-design-doc-written.sh` | Modify | マーカー判定削除、additionalContext 英語化＋新呼び出し名 |
| `schemas/verdict-schema.json` | Modify | `description` 英語化 |
| `.claude-plugin/plugin.json` | Modify | description に Superpowers 前提を明記（author 維持） |
| `.claude-plugin/marketplace.json` | Modify | plugin/marketplace description 更新（owner/author 維持） |
| `README.md` | Modify | 英語へ書き直し。scope ベース導入（local 第一）・user スコープ注意・Superpowers 前提 |
| `README.ja.md` | Create | 日本語版 README |
| `tests/hook.bats` | Modify | マーカー前提を除去、英語 additionalContext・新呼び出し名に整合 |
| `tests/skill-structure.bats` | Create | skill 改名の検証（F4） |
| `tests/no-japanese.bats` | Create | 配布物の日本語残存監査（C/F2） |

不変（無改修）: `scripts/codex-review.sh`, `scripts/convergence.sh`, `tests/{schema,convergence,codex-review}.bats`（パス参照があれば是正のみ）。

---

## Task 1: skill ディレクトリ改名（A）＋ 構造検証テスト（F4）

**Files:**
- Rename: `skills/codex-design-review/` → `skills/review/`（配下ごと）
- Modify: `skills/review/SKILL.md`（frontmatter `name`）
- Create: `tests/skill-structure.bats`

- [ ] **Step 1: 構造検証テストを書く（失敗するはず）**

`tests/skill-structure.bats` を作成:

```bash
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "new skill dir exists with SKILL.md" {
  [ -f "$ROOT/skills/review/SKILL.md" ]
}

@test "SKILL.md frontmatter name is review" {
  run grep -E '^name:[[:space:]]*review[[:space:]]*$' "$ROOT/skills/review/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "reviewer prompts exist under new dir" {
  [ -f "$ROOT/skills/review/reviewer-prompt-spec.md" ]
  [ -f "$ROOT/skills/review/reviewer-prompt-plan.md" ]
}

@test "old skill dir no longer exists" {
  [ ! -d "$ROOT/skills/codex-design-review" ]
}
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bats tests/skill-structure.bats`
Expected: FAIL（旧 dir が存在し新 dir が無いため）

- [ ] **Step 3: ディレクトリを改名し frontmatter を更新**

```bash
git mv skills/codex-design-review skills/review
```
`skills/review/SKILL.md` の frontmatter `name:` を `review` に変更（`name: codex-design-review` → `name: review`）。`description:` はこの Task では変更しない。

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bats tests/skill-structure.bats`
Expected: PASS（4 テスト）

- [ ] **Step 5: Commit**

```bash
git add -A skills tests/skill-structure.bats
git commit -m "refactor: rename skill dir to review (/codex-design-review:review)"
```

---

## Task 2: hook のフラグ廃止（D）＋ 英語化＋新呼び出し名（A/C）

**Files:**
- Modify: `hooks/on-design-doc-written.sh`
- Modify: `tests/hook.bats`

- [ ] **Step 1: hook.bats を新挙動に書き換える（失敗するはず）**

`tests/hook.bats` を以下で全置換:

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

run_hook() {
  local fp="$1"
  echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$fp\"}}" | bash "$HOOK"
}

@test "spec path -> injects additionalContext" {
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("/codex-design-review:review")'
}

@test "plan path -> injects" {
  run run_hook "$PROJ/docs/superpowers/plans/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext'
}

@test "non-target path -> silent exit 0" {
  run run_hook "$PROJ/src/main.py"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "README under docs but not specs/plans -> no inject" {
  run run_hook "$PROJ/docs/superpowers/README.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fresh lock present -> suppressed" {
  touch "$PROJ/.claude/.codex-design-review.lock"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stale lock (>60min) -> not suppressed" {
  touch "$PROJ/.claude/.codex-design-review.lock"
  touch -d "90 minutes ago" "$PROJ/.claude/.codex-design-review.lock"
  run run_hook "$PROJ/docs/superpowers/specs/2026-06-10-foo.md"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext'
}

@test "malformed stdin -> exit 0, no crash" {
  run bash -c "echo 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}
```

（変更点: 全テストから `.enabled` の touch を除去、「no marker」テストを削除、spec テストの assertion を `/codex-design-review:review` に。）

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bats tests/hook.bats`
Expected: FAIL（現 hook はまだマーカー判定があり、未マーカーで `[ -z "$output" ]` 側に倒れる／additionalContext が旧文言のため `/codex-design-review:review` を含まない）

- [ ] **Step 3: hook を修正**

`hooks/on-design-doc-written.sh` を編集:
1. マーカー判定ブロックを**削除**:
   ```bash
   # --- 2. per-project 有効化マーカー ---
   [ -f "$proj/.claude/codex-design-review.enabled" ] || exit 0
   ```
2. additionalContext を英語＋新呼び出し名に置換。`ctx="..."` の行を:
   ```bash
   ctx="Launch the codex-design-review review skill (/codex-design-review:review) and run the review loop. Document kind: ${doc_kind}. Target path: ${file_path}. This is an automatic trigger fired on a write to a ${doc_kind} document."
   ```
3. ファイル冒頭・各セクションのコメントを英語化（例: `# PostToolUse hook: detect writes to spec/plan docs and instruct launching the codex-design-review review skill via additionalContext.` 等）。ロジック（パス判定・lock 判定・jq 出力）は変えない。

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bats tests/hook.bats`
Expected: PASS（7 テスト）

- [ ] **Step 5: Commit**

```bash
git add hooks/on-design-doc-written.sh tests/hook.bats
git commit -m "feat: drop enable-marker gate; English hook context; new skill invocation"
```

---

## Task 3: SKILL.md のフラグ記述削除（D）＋ B フォールバック ＋ 英語化（C）

**Files:**
- Modify: `skills/review/SKILL.md`

- [ ] **Step 1: フラグ記述を削除**

前処理から有効化マーカー作成の記述（`touch "$CLAUDE_PROJECT_DIR/.claude/codex-design-review.enabled"` 系）を削除。完了処理からマーカー削除（`rm -f ....enabled`）の記述を削除。ロック作成/削除（`.codex-design-review.lock`）の記述は**残す**。

- [ ] **Step 2: receiving-code-review をフォールバック付きに**

指摘吟味の記述（現状「superpowers:receiving-code-review の規律で技術的に検証」）を、フォールバック付きへ書き換える。英語で:
> Examine each finding with the rigor of the `superpowers:receiving-code-review` skill if it is available. If that skill is not present, fall back to a general review discipline: do not be sycophantic, judge each finding on technical merits against the reality of this codebase, and decide accept / reject / hold with reasons.

- [ ] **Step 3: 本文全体を英語化**

`skills/review/SKILL.md` 本文（frontmatter `description` は既に英語、本文の日本語を英語へ）を翻訳。**保持すべき不変要素**:
- frontmatter `name: review`（Task 1 で設定済み）。
- 手順の構造・番号・チェックリスト・コードブロック（bash 呼び出し、パス `$work/...`、`codex-review.sh round1/round2` 引数）は**そのまま**。
- 既存の不変条件（read-only 強制、最大2ラウンド、codex 不在時スキップ、`/tmp` 作業ディレクトリ解決と空ガード cleanup）。
- 判断ドキュメントのフォーマット表（`docs/superpowers/reviews/...`）。

- [ ] **Step 4: 旧記述が消えたことを確認**

Run: `grep -nE 'codex-design-review\.enabled|有効化マーカー|touch .*\.enabled' skills/review/SKILL.md`
Expected: 出力なし（0 件）

Run: `grep -n 'receiving-code-review' skills/review/SKILL.md`
Expected: フォールバック文を含む英語の記述がヒット

- [ ] **Step 5: Commit**

```bash
git add skills/review/SKILL.md
git commit -m "refactor: English SKILL body, drop marker steps, add receiving-code-review fallback"
```

---

## Task 4: reviewer プロンプトの英語化（C）

**Files:**
- Modify: `skills/review/reviewer-prompt-spec.md`
- Modify: `skills/review/reviewer-prompt-plan.md`

- [ ] **Step 1: 両プロンプトを英語化**

日本語の指示文を英語へ翻訳。**保持すべき不変要素**:
- プレースホルダ `{{TARGET_PATH}}` / `{{REFERENCES}}` をそのまま残す（SKILL がこれを置換するため）。
- 観点リスト（completeness / consistency / ambiguity / YAGNI / feasibility / missed risks）の意味。
- 「verdict JSON Schema に厳密に従う」「actionable な指摘＋具体的 suggestion を必ず添える」「重大な問題が無ければ overall: approved・findings 空配列」という出力規約。
- read-only でリポジトリを探索し、一般論でなくこのプロジェクトの現実に基づけ、という前提。

- [ ] **Step 2: プレースホルダ保持を確認**

Run: `grep -c '{{TARGET_PATH}}\|{{REFERENCES}}' skills/review/reviewer-prompt-spec.md skills/review/reviewer-prompt-plan.md`
Expected: 各ファイルで `{{TARGET_PATH}}` と `{{REFERENCES}}` が残存

- [ ] **Step 3: Commit**

```bash
git add skills/review/reviewer-prompt-spec.md skills/review/reviewer-prompt-plan.md
git commit -m "refactor: English reviewer prompts"
```

---

## Task 5: verdict-schema.json の description 英語化（C/F2）

**Files:**
- Modify: `schemas/verdict-schema.json`

- [ ] **Step 1: description を英語化**

各 `description` の日本語を英語へ置換（**キー・型・構造は変えない**）:
- `"approved = 重大な指摘なし。revise = 対応すべき指摘あり"` → `"approved = no significant findings. revise = there are findings to address"`
- `"0.0-1.0。レビュー全体の確信度"` → `"0.0-1.0. Overall confidence of the review"`
- `"全体講評(短文)"` → `"Brief overall summary"`
- `"actionable な指摘のみ。各指摘に具体的な修正案を必ず添える"` → `"Actionable findings only. Each must include a concrete suggestion"`
- `"F1, F2, ... の連番"` → `"Sequential id: F1, F2, ..."`
- `"対象セクション名/見出し"` → `"Target section name / heading"`
- `"何が問題か"` → `"What is the problem"`
- `"なぜ問題か"` → `"Why it is a problem"`
- `"具体的な修正案"` → `"Concrete suggested fix"`

- [ ] **Step 2: JSON 妥当性とスキーマテストを確認**

Run: `jq empty schemas/verdict-schema.json && bats tests/schema.bats`
Expected: jq エラーなし、schema.bats 全 PASS

- [ ] **Step 3: Commit**

```bash
git add schemas/verdict-schema.json
git commit -m "refactor: English schema descriptions"
```

---

## Task 6: マニフェストの description 更新（B/F3）

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: plugin.json の description を更新**

`description` を Superpowers 前提を含む英語へ:
```json
"description": "Cross-model review of design documents by OpenAI Codex CLI. Built for the Superpowers spec/plan workflow (documents under docs/superpowers/{specs,plans}); Superpowers is recommended but not required.",
```
`author.name`（`krossto`）は**変更しない**。

- [ ] **Step 2: marketplace.json の description を更新**

plugin エントリの `description` を plugin.json と同一文言に更新。marketplace 直下の `description`（`"Local marketplace for codex-design-review plugin"`）は変更不要。`owner.name` / `author.name`（`krossto`）は**変更しない**。

- [ ] **Step 3: JSON 妥当性を確認**

Run: `jq empty .claude-plugin/plugin.json .claude-plugin/marketplace.json && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs: note Superpowers soft-dependency in manifests"
```

---

## Task 7: README 英語化 ＋ 日本語版（C/E/B）＋ 日本語監査

**Files:**
- Modify: `README.md`
- Create: `README.ja.md`
- Create: `tests/no-japanese.bats`

- [ ] **Step 1: 日本語残存監査テストを書く（後で通す）**

`tests/no-japanese.bats` を作成:

```bash
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

# 配布物（README.ja.md と docs/ の履歴は除く）に日本語が残っていないこと
@test "no Japanese in distributed files" {
  run grep -rlED '[ぁ-んァ-ヶ一-龥]' \
    "$ROOT/README.md" \
    "$ROOT/skills" \
    "$ROOT/hooks" \
    "$ROOT/schemas" \
    "$ROOT/.claude-plugin"
  [ -z "$output" ]
}
```

（`README.ja.md` と `docs/` は対象外。意図的な日本語のため。）

- [ ] **Step 2: README.md を英語へ書き直す**

英語で次を含める:
- 概要 / 仕組み（hook が spec/plan の書き込みを検知 → review skill 起動 → Codex を read-only で最大2ラウンド）。
- 前提: OpenAI Codex CLI 認証済み、`jq`。Superpowers ワークフロー（spec/plan を `docs/superpowers/{specs,plans}` に作る運用）が前提だが必須ではない旨。
- **導入（scope ベース）**: marketplace 追加 → `/plugin install codex-design-review@<marketplace>` を **local スコープ第一推奨**（`/plugin` UI でスコープ選択、または `--scope local`）。project スコープを「チームで共有したい場合」として併記。
- **重要な注意**: local スコープのゲートを効かせるには **user スコープで有効化しないこと**（`~/.claude/settings.json` の `enabledPlugins` に入れない。入れると全プロジェクトで hook がロードされる）。
- 呼び出し名 `/codex-design-review:review`。
- **マーカーによる有効化の節は含めない**（廃止済み）。
- テスト: `bats tests/`。
- 冒頭に「日本語版は [README.ja.md](./README.ja.md)」リンク。

- [ ] **Step 3: README.ja.md を作成**

README.md の内容を日本語で記述。冒頭に「English: [README.md](./README.md)」リンク。

- [ ] **Step 4: 監査テストを実行して通過を確認**

Run: `bats tests/no-japanese.bats`
Expected: PASS（README.md・skills・hooks・schemas・.claude-plugin に日本語が残っていない。残っていれば該当ファイルを英語化して再実行）

- [ ] **Step 5: Commit**

```bash
git add README.md README.ja.md tests/no-japanese.bats
git commit -m "docs: English README + Japanese README.ja.md + Japanese-residue audit"
```

---

## Task 8: 全体回帰 ＋ F1 実機検証（D/E 成立条件）＋ 仕上げ

**Files:**
- 変更なし（検証）。必要なら user スコープ dangling エントリ整理（手動）。

- [ ] **Step 1: 全 bats スイートのグリーン確認**

Run: `for f in tests/*.bats; do bats "$f"; done`
Expected: 全 PASS（hook / skill-structure / no-japanese / schema / convergence / codex-review）。`codex-review.bats` 等が旧 skill パスを参照していれば是正してから再実行。

- [ ] **Step 2: 日本語残存の最終スイープ**

Run: `grep -rlED '[ぁ-んァ-ヶ一-龥]' README.md skills hooks schemas .claude-plugin`
Expected: 出力なし。

- [ ] **Step 3: F1 実機検証 — local スコープのプロジェクト単位ゲート（手動・対話）**

> これは Claude Code のランタイム挙動の確認のため**手動・対話的**に行う（自動テスト不可）。事前調査で「local スコープは per-project でゲートされる」強い証拠（このプロジェクトで `claude plugin list` が disabled 表示）は得ているが、最終確認として実施する。

事前条件:
- user スコープで本プラグインを**有効化しない**。既存の dangling エントリ `"codex-design-review@codex-design-review"`（マーケット名誤りで現状は空振り）が `~/.claude/settings.json` に残っていれば、混乱回避のため削除する。

手順（観察を記録）:
1. テスト用 project A に local スコープでインストール（`/plugin install codex-design-review@<marketplace> --scope local` を A の中で実行、または `/plugin` UI で Local 選択）。project B は未導入のまま。
2. A で `docs/superpowers/specs/verify.md` に実質的な内容を書く → review skill 起動（additionalContext 注入）を**観察**。
3. B で同じ書き込み → **何も起きない**ことを観察。
4. project スコープ（`.claude/settings.json`・コミット）でも 1〜3 を再確認。

合否:
- A でのみ発火・B で非発火なら **D/E 成立 → 完了**。
- もし B でも発火する/A で発火しない等、想定外なら **フラグ廃止を見送り**、spec §3.1 のフォールバック（hook 冒頭で `.claude/settings*.json` の enablement を読む自己ゲート、または marker 復活）を別タスクで実装する。

- [ ] **Step 4: 検証結果を記録**

`docs/superpowers/reviews/2026-06-11-scope-gating-verification.md`（新規）に、上記 1〜4 の観察結果（発火/非発火）と合否を1ページで記録し commit。

```bash
git add docs/superpowers/reviews/2026-06-11-scope-gating-verification.md
git commit -m "docs: record scope-gating runtime verification (F1)"
```

---

## Self-Review メモ

- **Spec coverage:** A→Task1、D(hook)→Task2、D(SKILL)+B(fallback)+C(SKILL)→Task3、C(prompts)→Task4、C/F2(schema)→Task5、B/F3(manifests)→Task6、C/E/README+JA+日本語監査→Task7、F1検証+F4回帰+F5(履歴不更新は各タスクが現行ファイルのみ対象)→Task8。全項目にタスク対応あり。
- **F5（docs 更新範囲）:** 各タスクは現行ファイル（SKILL/hook/schema/manifest/README）のみ対象。過去 `docs/superpowers/{specs,plans,reviews}` は触れない（no-japanese 監査も `docs/` を対象外）。
- **Placeholder scan:** 翻訳タスク（Task3/4/7）は全文事前訳を載せず「保持すべき不変要素＋構造保存」を明示。機械的変更（hook/schema/manifest/test/frontmatter）は exact 文字列を記載。
- **命名整合:** skill 名 `review`、呼び出し `/codex-design-review:review`、新パス `skills/review/` を全タスクで統一。
