# 一般配布対応リファクタ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** codex-design-review プラグインを一般配布レディにする — 起動を Claude Code ネイティブ scope に一本化（フラグ廃止）、配布物を英語統一（日本語 README 別建て）、skill 名短縮、Superpowers ソフト依存の明示＋フォールバック。

**Architecture:** 既存プラグイン（skill + PostToolUse hook + scripts + schema + tests）の振る舞い・体裁を整える。コアのレビュー機構（codex-review.sh / convergence.sh / `/tmp` 作業ディレクトリ）は無改修。**フラグ廃止は spec の条件付き判断に従い、破壊的変更の前に Task 1 の preflight ゲートで scope ゲーティングを実機確認する。**

**Tech Stack:** Bash（hook）、bats（テスト）、JSON（manifest/schema）、Markdown（SKILL/README/prompts）。

**Spec:** `docs/superpowers/specs/2026-06-11-general-distribution-readiness-design.md`

---

## File Structure

| ファイル | 操作 | 責務 |
|---|---|---|
| `skills/review/SKILL.md` | Rename + Modify | 旧 `skills/codex-design-review/SKILL.md`。frontmatter `name: review`、英語化、フラグ記述削除、B フォールバック |
| `skills/review/reviewer-prompt-{spec,plan}.md` | Rename + Modify | 英語化（プレースホルダ保持） |
| `hooks/on-design-doc-written.sh` | Modify | マーカー判定削除（preflight 合格時）、additionalContext 英語化＋新呼び出し名 |
| `schemas/verdict-schema.json` | Modify | `description` 英語化 |
| `.claude-plugin/plugin.json` | Modify | description に Superpowers 前提を明記（author 維持） |
| `.claude-plugin/marketplace.json` | Modify | plugin description 更新（owner/author 維持） |
| `README.md` | Modify | 英語へ書き直し。scope ベース導入（local 第一）・user スコープ注意・Superpowers 前提 |
| `README.ja.md` | Create | 日本語版 README |
| `tests/hook.bats` | Modify | マーカー前提を除去、英語 additionalContext・新呼び出し名に整合 |
| `tests/skill-structure.bats` | Create | skill 改名の検証＋prompt プレースホルダ（F4） |
| `tests/no-japanese.bats` | Create | 配布物の日本語残存監査（C/F2、Task 2 で赤設置→Task 8 で緑） |
| `tests/manifest.bats` | Create | manifest description が Superpowers ソフト依存を明記している検証（B/F2） |

不変（無改修）: `scripts/codex-review.sh`, `scripts/convergence.sh`, `tests/{schema,convergence,codex-review}.bats`（パス参照があれば是正のみ）。

---

## Task 1: F1 preflight ゲート（BLOCKING・手動）— scope ゲーティングの実機確認

spec はフラグ廃止を「scope ベースで per-project に hook がロードされる」ことの**実機確認成功を条件**にしている。**破壊的変更（Task 3 以降のフラグ廃止）の前に**ここで確認する。マーカーをまだ消していない現状の plugin を使い、**マーカーを差別化要因から外す**ことで scope ゲーティングだけを切り分ける。

**Files:** 変更なし（手動検証 + 結果記録）

- [ ] **Step 1: 事前条件を整える**

- 本プラグインを **user スコープで有効化しない**。`~/.claude/settings.json` の `enabledPlugins` に dangling エントリ `"codex-design-review@codex-design-review": true`（マーケット名誤りで現状空振り）が残っていれば削除する。
- テスト用に project A（導入する）と project B（導入しない）を用意。

- [ ] **Step 2: scope ゲーティングを切り分け検証**

1. project A に現行プラグインを **local スコープ**で導入（`/plugin install codex-design-review@<marketplace> --scope local` を A の中で、または `/plugin` UI で Local）。B には導入しない。
2. **マーカーを A と B の両方に作成**: 各プロジェクトで `mkdir -p .claude && touch .claude/codex-design-review.enabled`（マーカーを差別化要因から外す）。
3. A で `docs/superpowers/specs/verify.md` に実質的内容を書く → review skill 起動（additionalContext 注入）を**観察**。
4. B で同じ書き込み → **何も起きない**ことを観察（マーカーはあるが plugin/hook が B にロードされないはず）。

- [ ] **Step 3: 合否判定とブランチ選択**

- **A 発火 / B 非発火** → scope ゲーティング成立。**Task 3・4・8 を「通常版（フラグ廃止）」で実施**。
- **B でも発火 / A で非発火など想定外** → scope ゲーティング不成立。**Task 3・4・8 を「フォールバック版（自己ゲート維持）」で実施**（各タスクの「フォールバック」節を参照）。
- 参考（事前調査の所見）: 本リポジトリで `claude plugin list` を実行すると codex-design-review は disabled 表示で、local スコープ有効化が他プロジェクトへ漏れていない＝per-project ゲートの強い証拠は既に得ている。本 preflight はその最終確認。

- [ ] **Step 4: 結果を記録**

`docs/superpowers/reviews/2026-06-11-scope-gating-verification.md`（新規）に観察結果（A/B の発火有無）と採用ブランチ（通常版/フォールバック版）を記録し commit。

```bash
git add docs/superpowers/reviews/2026-06-11-scope-gating-verification.md
git commit -m "docs: record scope-gating preflight (F1) result"
```

> 検証後、Step 2 で作ったテスト用マーカー/設定は掃除する。

---

## Task 2: skill 改名（A）＋ 監査テスト前倒し設置（F2/F4）

**Files:**
- Rename: `skills/codex-design-review/` → `skills/review/`
- Modify: `skills/review/SKILL.md`（frontmatter `name`）
- Create: `tests/skill-structure.bats` / `tests/no-japanese.bats` / `tests/manifest.bats`

- [ ] **Step 1: 構造＋プレースホルダ検証テストを書く**

`tests/skill-structure.bats`:

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

@test "spec prompt exists and keeps placeholders" {
  [ -f "$ROOT/skills/review/reviewer-prompt-spec.md" ]
  run grep -c '{{TARGET_PATH}}' "$ROOT/skills/review/reviewer-prompt-spec.md"
  [ "$output" -ge 1 ]
  run grep -c '{{REFERENCES}}' "$ROOT/skills/review/reviewer-prompt-spec.md"
  [ "$output" -ge 1 ]
}

@test "plan prompt exists and keeps placeholders" {
  [ -f "$ROOT/skills/review/reviewer-prompt-plan.md" ]
  run grep -c '{{TARGET_PATH}}' "$ROOT/skills/review/reviewer-prompt-plan.md"
  [ "$output" -ge 1 ]
  run grep -c '{{REFERENCES}}' "$ROOT/skills/review/reviewer-prompt-plan.md"
  [ "$output" -ge 1 ]
}

@test "old skill dir no longer exists" {
  [ ! -d "$ROOT/skills/codex-design-review" ]
}
```

- [ ] **Step 2: 日本語残存監査テストを書く（赤ガード・Task 8 まで赤の想定）**

`tests/no-japanese.bats`（`-D` を使わない。`grep -rlE` で日本語ファイルを列挙し、無マッチ＝status 1・空出力を期待）:

```bash
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

# 配布物（README.ja.md と docs/ の履歴は除外）に日本語が残っていないこと
@test "no Japanese in distributed files" {
  run grep -rlE '[ぁ-んァ-ヶ一-龥]' \
    "$ROOT/README.md" \
    "$ROOT/skills" \
    "$ROOT/hooks" \
    "$ROOT/schemas" \
    "$ROOT/.claude-plugin"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
```

- [ ] **Step 3: manifest description 検証テストを書く（赤ガード・Task 7 で緑）**

`tests/manifest.bats`:

```bash
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "plugin.json is valid JSON" {
  run jq empty "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
}

@test "marketplace.json is valid JSON" {
  run jq empty "$ROOT/.claude-plugin/marketplace.json"
  [ "$status" -eq 0 ]
}

@test "plugin.json description notes Superpowers soft dependency" {
  run jq -r '.description' "$ROOT/.claude-plugin/plugin.json"
  echo "$output" | grep -q 'Superpowers'
  echo "$output" | grep -qi 'not required'
}

@test "marketplace plugin entry description notes Superpowers" {
  run jq -r '.plugins[0].description' "$ROOT/.claude-plugin/marketplace.json"
  echo "$output" | grep -q 'Superpowers'
}
```

- [ ] **Step 4: テストを実行して状態を確認**

Run: `bats tests/skill-structure.bats tests/no-japanese.bats tests/manifest.bats`
Expected: 全テスト FAIL/赤（旧 dir が存在、日本語残存、manifest に Superpowers 記述なし）。これがこれ以降のタスクの到達目標。

- [ ] **Step 5: ディレクトリを改名し frontmatter を更新**

```bash
git mv skills/codex-design-review skills/review
```
`skills/review/SKILL.md` の frontmatter `name: codex-design-review` → `name: review`。

- [ ] **Step 6: skill-structure を通過確認**

Run: `bats tests/skill-structure.bats`
Expected: PASS（5 テスト）。no-japanese / manifest はまだ赤でよい。

- [ ] **Step 7: Commit**

```bash
git add -A skills tests/skill-structure.bats tests/no-japanese.bats tests/manifest.bats
git commit -m "refactor: rename skill dir to review; add structure/i18n/manifest guard tests"
```

---

## Task 3: hook のフラグ廃止（D）＋ 英語化＋新呼び出し名（A/C）

> **Task 1 preflight が「通常版」のときのみフラグ廃止を行う。** 「フォールバック版」の場合は末尾の【フォールバック】に従う。

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

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bats tests/hook.bats`
Expected: FAIL（現 hook はマーカー判定があり未マーカーで沈黙、additionalContext も旧文言）

- [ ] **Step 3: hook を修正**

`hooks/on-design-doc-written.sh`:
1. マーカー判定ブロックを**削除**:
   ```bash
   # --- 2. per-project 有効化マーカー ---
   [ -f "$proj/.claude/codex-design-review.enabled" ] || exit 0
   ```
2. additionalContext を英語＋新呼び出し名へ:
   ```bash
   ctx="Launch the codex-design-review review skill (/codex-design-review:review) and run the review loop. Document kind: ${doc_kind}. Target path: ${file_path}. This is an automatic trigger fired on a write to a ${doc_kind} document."
   ```
3. ファイル冒頭・各セクションのコメントを英語化（ロジックは不変）。

- [ ] **Step 4: テストを実行して通過を確認**

Run: `bats tests/hook.bats`
Expected: PASS（7 テスト）

- [ ] **Step 5: Commit**

```bash
git add hooks/on-design-doc-written.sh tests/hook.bats
git commit -m "feat: drop enable-marker gate; English hook context; new skill invocation"
```

**【フォールバック版（preflight 不成立時）】**
- マーカー判定は**削除しない**。代わりに、より堅い自己ゲートとして hook 冒頭で `$CLAUDE_PROJECT_DIR/.claude/settings.local.json` または `.claude/settings.json` の `enabledPlugins` に本プラグイン（`codex-design-review@<marketplace>`）が `true` であるかを `jq` で読み、無ければ `exit 0` する方式を実装（マーカー方式は後方互換として併存可）。hook.bats は「enabledPlugins に有効化エントリがある settings.local.json を置いた場合のみ発火」を検証するテストへ調整。additionalContext 英語化・新呼び出し名は通常版と同じ。

---

## Task 4: SKILL.md のフラグ記述削除（D）＋ B フォールバック ＋ 英語化（C）

> フラグ記述削除は Task 1 preflight「通常版」時。「フォールバック版」では削除せず自己ゲートの説明に置換。

**Files:**
- Modify: `skills/review/SKILL.md`

- [ ] **Step 1: フラグ記述を削除（通常版）**

前処理から有効化マーカー作成（`touch ....enabled`）、完了処理からマーカー削除（`rm -f ....enabled`）の記述を削除。ロック作成/削除（`.codex-design-review.lock`）は**残す**。
（フォールバック版: マーカー/自己ゲートの記述を残し、英語化のみ行う。）

- [ ] **Step 2: receiving-code-review をフォールバック付きに**

指摘吟味の記述を英語で、フォールバック付きへ:
> Examine each finding with the rigor of the `superpowers:receiving-code-review` skill if it is available. If that skill is not present, fall back to a general review discipline: do not be sycophantic, judge each finding on technical merits against the reality of this codebase, and decide accept / reject / hold with reasons.

- [ ] **Step 3: 本文全体を英語化**

`skills/review/SKILL.md` 本文を英語へ翻訳。**保持すべき不変要素**:
- frontmatter `name: review`。
- 手順構造・番号・チェックリスト・コードブロック（`$work/...` パス、`codex-review.sh round1/round2` 引数）はそのまま。
- 不変条件（read-only 強制、最大2ラウンド、codex 不在時スキップ、`/tmp` 作業ディレクトリ解決＋空ガード cleanup）。
- 判断ドキュメントのフォーマット表（`docs/superpowers/reviews/...`）。

- [ ] **Step 4: 旧記述が消えたことを確認**

Run: `grep -nE 'codex-design-review\.enabled|有効化マーカー|touch .*\.enabled' skills/review/SKILL.md`
Expected: 出力なし（通常版）。
Run: `grep -n 'receiving-code-review' skills/review/SKILL.md`
Expected: 英語のフォールバック文がヒット

- [ ] **Step 5: Commit**

```bash
git add skills/review/SKILL.md
git commit -m "refactor: English SKILL body, drop marker steps, add receiving-code-review fallback"
```

---

## Task 5: reviewer プロンプトの英語化（C）

**Files:**
- Modify: `skills/review/reviewer-prompt-spec.md`
- Modify: `skills/review/reviewer-prompt-plan.md`

- [ ] **Step 1: 両プロンプトを英語化**

**保持すべき不変要素**:
- プレースホルダ `{{TARGET_PATH}}` / `{{REFERENCES}}` をそのまま残す（skill-structure.bats が検証）。
- 観点リスト（completeness / consistency / ambiguity / YAGNI / feasibility / missed risks）の意味。
- 出力規約（verdict JSON Schema 厳守、actionable な指摘＋具体的 suggestion 必須、重大な問題が無ければ overall: approved・findings 空配列）。
- read-only でリポジトリ探索、一般論でなくこのプロジェクトの現実に基づく、という前提。

- [ ] **Step 2: プレースホルダ保持と英語化を確認**

Run: `bats tests/skill-structure.bats`
Expected: PASS（プレースホルダ保持テストを含む）
Run: `grep -lE '[ぁ-んァ-ヶ一-龥]' skills/review/reviewer-prompt-spec.md skills/review/reviewer-prompt-plan.md`
Expected: 出力なし（両ファイルに日本語が残っていない）

- [ ] **Step 3: Commit**

```bash
git add skills/review/reviewer-prompt-spec.md skills/review/reviewer-prompt-plan.md
git commit -m "refactor: English reviewer prompts"
```

---

## Task 6: verdict-schema.json の description 英語化（C/F2）

**Files:**
- Modify: `schemas/verdict-schema.json`

- [ ] **Step 1: description を英語化（キー・型・構造は不変）**

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

## Task 7: マニフェストの description 更新（B/F3）

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: plugin.json の description を更新**

```json
"description": "Cross-model review of design documents by OpenAI Codex CLI. Built for the Superpowers spec/plan workflow (documents under docs/superpowers/{specs,plans}); Superpowers is recommended but not required.",
```
`author.name`（`krossto`）は変更しない。

- [ ] **Step 2: marketplace.json の plugin description を更新**

plugin エントリの `description` を plugin.json と同一文言に。marketplace 直下の `description` は変更不要。`owner.name`/`author.name`（`krossto`）は変更しない。

- [ ] **Step 3: manifest テストを通過確認**

Run: `bats tests/manifest.bats`
Expected: PASS（4 テスト。description が `Superpowers` と `not required` を含む）

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs: note Superpowers soft-dependency in manifests"
```

---

## Task 8: README 英語化 ＋ 日本語版（C/E/B）

**Files:**
- Modify: `README.md`
- Create: `README.ja.md`

- [ ] **Step 1: README.md を英語へ書き直す**

英語で次を含める:
- 概要 / 仕組み（hook が spec/plan 書き込みを検知 → review skill 起動 → Codex を read-only で最大2ラウンド）。
- 前提: OpenAI Codex CLI 認証済み、`jq`。Superpowers ワークフロー（spec/plan を `docs/superpowers/{specs,plans}` に作る運用）が前提だが必須ではない旨。
- **導入（scope ベース）**: marketplace 追加 → `/plugin install codex-design-review@<marketplace>` を **local スコープ第一推奨**（`/plugin` UI または `--scope local`）。project スコープを「チーム共有したい場合」として併記。
- **重要な注意**: local スコープのゲートを効かせるには **user スコープで有効化しないこと**（`~/.claude/settings.json` の `enabledPlugins` に入れない）。
- 呼び出し名 `/codex-design-review:review`。マーカー有効化の節は**含めない**（通常版）。フォールバック版採用時のみ自己ゲート設定を記載。
- テスト: `bats tests/`。
- 冒頭に「日本語版は [README.ja.md](./README.ja.md)」リンク。

- [ ] **Step 2: README.ja.md を作成**

README.md の内容を日本語で。冒頭に「English: [README.md](./README.md)」リンク。

- [ ] **Step 3: 日本語残存監査を通過確認**

Run: `bats tests/no-japanese.bats`
Expected: PASS（README.md・skills・hooks・schemas・.claude-plugin に日本語残存なし。残っていれば該当を英語化して再実行）

- [ ] **Step 4: Commit**

```bash
git add README.md README.ja.md
git commit -m "docs: English README + Japanese README.ja.md"
```

---

## Task 9: 全体回帰 ＋ F1 最終再確認 ＋ 仕上げ

**Files:** 変更なし（検証）

- [ ] **Step 1: 全 bats スイートのグリーン確認**

Run: `for f in tests/*.bats; do bats "$f"; done`
Expected: 全 PASS（hook / skill-structure / no-japanese / manifest / schema / convergence / codex-review）。`codex-review.bats` 等が旧 skill パスを参照していれば是正してから再実行。

- [ ] **Step 2: 日本語残存の最終スイープ**

Run: `grep -rlE '[ぁ-んァ-ヶ一-龥]' README.md skills hooks schemas .claude-plugin`
Expected: 出力なし（status 1）。

- [ ] **Step 3: F1 最終再確認（通常版のみ）**

Task 1 preflight で得た結論を、英語化・フラグ廃止後の実体で最終確認: 改修後プラグインを local スコープで project A に再導入し、A で spec 書き込み → `/codex-design-review:review` 起動、B では非発火、を再観察。Task 1 の記録ファイルに「最終確認: 合格」を追記。
（フォールバック版採用時は、自己ゲートが settings 有効化に従うことを確認。）

- [ ] **Step 4: 記録を更新して commit**

```bash
git add docs/superpowers/reviews/2026-06-11-scope-gating-verification.md
git commit -m "docs: record final scope-gating verification (F1)"
```

---

## Self-Review メモ

- **Spec coverage:** A→Task2、D(hook)→Task3、D(SKILL)+B(fallback)+C(SKILL)→Task4、C(prompts)→Task5、C/F2(schema)→Task6、B/F3(manifests)→Task7、C/E(README+JA)→Task8、F1検証→Task1(preflight)+Task9(最終)、F4(構造)→Task2、F5(履歴不更新)→各タスクは現行ファイルのみ対象。全項目にタスク対応あり。
- **Codex round1 反映:** F1（preflight ゲートを Task1 へ前倒し・条件付き＋フォールバック明記）、F2（no-japanese/manifest テストを Task2 で前倒し赤設置）、F3（`grep -rlED`→`grep -rlE`＋status 判定）。
- **Placeholder scan:** 翻訳タスク（Task4/5/8）は「保持すべき不変要素＋構造保存」を明示。機械的変更（hook/schema/manifest/test/frontmatter）は exact 文字列。
- **命名整合:** skill 名 `review`、呼び出し `/codex-design-review:review`、新パス `skills/review/` で統一。
