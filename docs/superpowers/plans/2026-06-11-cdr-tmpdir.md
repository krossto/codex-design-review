# CDR 作業ディレクトリ `/tmp` 化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** codex-design-review skill の Codex 中継用一時ファイルを、対象プロジェクトのルート `tmp-cdr/` ではなく OS 一時領域（`/tmp`、`TMPDIR` 尊重）に置き、失敗時のみ `.claude/tmp-cdr/` へ自動フォールバックする。

**Architecture:** 振る舞いを決めるのは `skills/codex-design-review/SKILL.md`（オーケストレータ Claude への markdown 指示）。前処理で作業ディレクトリ `$work` を1回だけ解決し、以降そのパスをリテラルで再利用。`uuid` は `mktemp -d` のユニーク性で代替して廃止。`scripts/codex-review.sh` は out_dir を引数で受けるだけなので無改修。`uuidgen` が不要になるため `README.md` の前提条件も更新。

**Tech Stack:** Bash（`mktemp`）、bats（既存テストの回帰確認）、markdown。

**Spec:** `docs/superpowers/specs/2026-06-11-cdr-tmpdir-design.md`

---

## File Structure

| ファイル | 操作 | 責務 |
|---|---|---|
| `skills/codex-design-review/SKILL.md` | Modify | 作業ディレクトリ解決・全ラウンドのパス・後始末・両方失敗時スキップ |
| `README.md` | Modify | 前提条件から `uuidgen` を削除 |
| `tests/*.bats` | 無改修（回帰確認のみ） | 既存挙動が壊れていないことの確認 |

---

## Task 1: 作業ディレクトリ解決スニペットを単体検証する（TDD カーネル）

SKILL.md に埋め込む §3.2 の解決コマンドを、本体に入れる前にシェル単体で 3 経路検証する。これが本変更の唯一のロジックらしいロジック。

**Files:**
- 検証のみ（ファイル変更なし）。確定したスニペットを Task 2 で SKILL.md に転記する。

- [ ] **Step 1: 正常系 — `/tmp` 経路で WORK= が返ることを確認**

検証対象スニペット（このまま実行）:

```bash
CLAUDE_PROJECT_DIR="$PWD"
work=""
work="$(mktemp -d "${TMPDIR:-/tmp}/codex-design-review-XXXXXX" 2>/dev/null)" || true
if [ -z "$work" ]; then
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr" \
    && work="$(mktemp -d "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr/run-XXXXXX" 2>/dev/null)" || true
fi
[ -n "$work" ] || { echo "ERROR=could not create codex-design-review work dir"; exit 1; }
echo "WORK=$work"
[ -n "${work:-}" ] && rm -rf -- "$work"   # 検証後の掃除
```

Run: 上記を `bash -c` で実行。
Expected: `WORK=/tmp/codex-design-review-XXXXXX`（`/tmp` 配下）が1行出力される。

- [ ] **Step 2: フォールバック系 — TMPDIR が書けないとき .claude/tmp-cdr へ落ちる**

Run:

```bash
CLAUDE_PROJECT_DIR="$PWD"
TMPDIR="/nonexistent-dir-cdr-test"
work=""
work="$(mktemp -d "${TMPDIR:-/tmp}/codex-design-review-XXXXXX" 2>/dev/null)" || true
if [ -z "$work" ]; then
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr" \
    && work="$(mktemp -d "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr/run-XXXXXX" 2>/dev/null)" || true
fi
[ -n "$work" ] || { echo "ERROR=could not create codex-design-review work dir"; exit 1; }
echo "WORK=$work"
[ -n "${work:-}" ] && rm -rf -- "$work"
```

Expected: `WORK=<repo>/.claude/tmp-cdr/run-XXXXXX` が出力される（`.claude/tmp-cdr/` 配下に落ちる）。
注意: 実行後 `.claude/tmp-cdr/` ディレクトリ自体は残るが空。Task 5 で `git status` に出ないこと（`.claude/` 配下）を確認する。

- [ ] **Step 3: 両方失敗系 — ERROR= と exit 1 を確認**

Run:

```bash
CLAUDE_PROJECT_DIR="/nonexistent-proj-cdr-test"
TMPDIR="/nonexistent-dir-cdr-test"
work=""
work="$(mktemp -d "${TMPDIR:-/tmp}/codex-design-review-XXXXXX" 2>/dev/null)" || true
if [ -z "$work" ]; then
  mkdir -p "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr" 2>/dev/null \
    && work="$(mktemp -d "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr/run-XXXXXX" 2>/dev/null)" || true
fi
[ -n "$work" ] || { echo "ERROR=could not create codex-design-review work dir"; exit 1; }
echo "WORK=$work"
echo "rc=$?"
```

Expected: `ERROR=could not create codex-design-review work dir` が出力され、終了コードが 1（`WORK=` は出力されない）。

> 注: SKILL.md 本体では fallback の `mkdir -p` に `2>/dev/null` は付けない（通常はエラーを見せたい）。両方失敗系の検証用に Step 3 だけ `2>/dev/null` を付けてノイズを抑えている。本体スニペットは Step 1 のものを正とする。

---

## Task 2: SKILL.md の前処理・実行 ID を書き換える

**Files:**
- Modify: `skills/codex-design-review/SKILL.md`（「## 前処理」3〜4）

- [ ] **Step 1: 「3. 作業ディレクトリ」を解決スニペットに置換**

置換前（現行 line 24 付近）:

```markdown
3. **作業ディレクトリ**: `mkdir -p "$CLAUDE_PROJECT_DIR/tmp-cdr"` と、レビュー記録用に `mkdir -p "$CLAUDE_PROJECT_DIR/docs/superpowers/reviews"`。
4. **実行 ID**: `uuid=$(uuidgen)`。出力先 `out1="$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-r1"`。
```

置換後:

````markdown
3. **作業ディレクトリ解決**: OS の一時領域に作業ディレクトリ `$work` を1回だけ確保する（`TMPDIR` 尊重）。失敗したら `.claude/tmp-cdr/` へ自動フォールバック。以降このパスを全ラウンドで使う。
   ```bash
   work=""
   work="$(mktemp -d "${TMPDIR:-/tmp}/codex-design-review-XXXXXX" 2>/dev/null)" || true
   if [ -z "$work" ]; then
     mkdir -p "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr" \
       && work="$(mktemp -d "$CLAUDE_PROJECT_DIR/.claude/tmp-cdr/run-XXXXXX" 2>/dev/null)" || true
   fi
   [ -n "$work" ] || { echo "ERROR=could not create codex-design-review work dir"; exit 1; }
   echo "WORK=$work"
   ```
   - 出力された `WORK=` のパスを `$work` として以降リテラルで使う。
   - **`ERROR=`（exit 1）が返ったら**（`/tmp` も `.claude/` も書けない）、作業ディレクトリを確保できないので**ロックを削除してレビューをスキップし、理由をユーザーに報告**して通常フローへ戻る（下記「完了処理」のロック削除のみ実施。`$work` は空なので一時ファイル削除は不要）。
   - レビュー記録用ディレクトリも作る: `mkdir -p "$CLAUDE_PROJECT_DIR/docs/superpowers/reviews"`。
4. **出力先**: `out1="$work/r1"`。
````

- [ ] **Step 2: Round 1 の「5. プロンプト生成」のパスを置換**

置換前（line 29 付近）の末尾部分:

```markdown
…に置換し、`$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-prompt.md` に書き出す。
```

置換後:

```markdown
…に置換し、`$work/prompt.md` に書き出す。
```

- [ ] **Step 3: Round 1 の codex 呼び出し引数のパスを置換**

置換前（line 35 付近）:

```bash
     "$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-prompt.md" \
```

置換後:

```bash
     "$work/prompt.md" \
```

- [ ] **Step 4: 変更後の前処理〜Round1 を目視確認**

Run: `grep -n 'tmp-cdr\|uuid\|\$work' skills/codex-design-review/SKILL.md`
Expected: line 24/25/29/35 由来の `tmp-cdr` と `uuid` が前処理・Round1 から消え、`$work/r1` `$work/prompt.md` になっている（Round2・完了処理は Task 3 で対応するためまだ残っていてよい）。

- [ ] **Step 5: Commit**

```bash
git add skills/codex-design-review/SKILL.md
git commit -m "feat: resolve CDR work dir under /tmp (preprocess + round1)"
```

---

## Task 3: SKILL.md の Round 2・完了処理を書き換える

**Files:**
- Modify: `skills/codex-design-review/SKILL.md`（「## Round 2」11、「## 完了処理」）

- [ ] **Step 1: Round 2「11. 再レビュー」の out2 とプロンプトパスを置換**

置換前（line 49 付近）の該当箇所:

```markdown
11. **再レビュー**(resume)。`out2="$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-r2"`。round2 用プロンプトを生成: 「…更新済みドキュメント: <対象パス>」を `tmp-cdr/$uuid-prompt2.md` に書き出し:
```

置換後:

```markdown
11. **再レビュー**(resume)。`out2="$work/r2"`。round2 用プロンプトを生成: 「…更新済みドキュメント: <対象パス>」を `$work/prompt2.md` に書き出し:
```

（「…」部分の本文＝拒否理由を読んで再主張せよ等の文言は現行のまま変更しない。）

- [ ] **Step 2: Round 2 の codex 呼び出し引数のパスを置換**

置換前（line 55 付近）:

```bash
      "$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-prompt2.md" \
```

置換後:

```bash
      "$work/prompt2.md" \
```

- [ ] **Step 3: 完了処理「一時ファイル削除」を空ガード付き1行に置換**

置換前（line 82 付近）:

```markdown
- **一時ファイル削除**: `rm -rf "$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid"*`。
```

置換後:

```markdown
- **一時ファイル削除**: `[ -n "${work:-}" ] && rm -rf -- "$work"`（`$work` が空なら何もしない安全ガード）。
```

- [ ] **Step 4: SKILL.md 全体から旧表現が消えたことを確認**

Run: `grep -n 'tmp-cdr/\$uuid\|uuidgen\|\$uuid' skills/codex-design-review/SKILL.md`
Expected: 出力なし（マッチ 0 件）。

Run: `grep -n '\$work' skills/codex-design-review/SKILL.md`
Expected: 前処理・Round1・Round2・完了処理に `$work` 系パスが現れる。

- [ ] **Step 5: Commit**

```bash
git add skills/codex-design-review/SKILL.md
git commit -m "feat: use \$work for CDR round2 and cleanup, drop uuid"
```

---

## Task 4: README.md の前提条件から uuidgen を削除する

**Files:**
- Modify: `README.md`（「## 前提」line 16 付近）

- [ ] **Step 1: 依存記述を jq のみに変更**

置換前（line 16）:

```markdown
- `jq`, `uuidgen` が利用可能。
```

置換後:

```markdown
- `jq` が利用可能。
```

- [ ] **Step 2: uuidgen 参照が消えたことを確認**

Run: `grep -rn 'uuidgen' README.md skills/codex-design-review/SKILL.md`
Expected: 出力なし（マッチ 0 件）。

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: drop uuidgen prerequisite (no longer used)"
```

---

## Task 5: 回帰確認と最終検証

**Files:**
- 変更なし（検証のみ）。

- [ ] **Step 1: 既存 bats スイートがグリーンであることを確認**

Run: `bats tests/`（または `for f in tests/*.bats; do bats "$f"; done`）
Expected: 全テスト pass。`scripts/codex-review.sh` は無改修なので落ちないはず。落ちた場合は SKILL.md の編集が誤って別ファイルに波及していないか確認する。

- [ ] **Step 2: フォールバックが git を汚さないことを確認**

Run: `git status --porcelain`
Expected: `.claude/tmp-cdr/`（Task 1 Step 2 のフォールバック検証で生成され得る）が untracked として現れても、それはこのプラグインリポでは `.gitignore` の対象外だが**コミット対象にしない**。残っていれば `rm -rf .claude/tmp-cdr` で掃除し、`git status` がクリーン（コミット済み変更のみ）になることを確認する。

- [ ] **Step 3: README 整合の最終確認**

Run: `grep -n 'jq\|uuidgen' README.md`
Expected: `jq` のみ残り `uuidgen` は無い。

- [ ] **Step 4: spec §6 検証項目との突き合わせ**

`docs/superpowers/specs/2026-06-11-cdr-tmpdir-design.md` の §6（1〜4）を読み、Task 1・5 でカバーされていることを確認。未カバーがあればタスクを追加。

---

## Self-Review メモ

- **Spec coverage:** §3.2 解決→Task1/2、§3.3 固定名パス→Task2/3、§5 両方失敗スキップ＋空ガード cleanup→Task2/3、§2.6 README→Task4、§6 検証→Task1/5。全要件にタスク対応あり。
- **Placeholder scan:** TBD/TODO なし。全 step に実コマンド・置換前後の実テキストを記載。
- **Type/命名整合:** 変数は全タスクで `$work`（base ディレクトリ）で統一。固定ファイル名 `prompt.md` / `prompt2.md` / `r1` / `r2` で統一。
