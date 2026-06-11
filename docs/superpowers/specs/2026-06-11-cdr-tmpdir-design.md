# codex-design-review 作業ディレクトリの `/tmp` 化 設計書

**日付:** 2026-06-11
**ステータス:** ユーザーレビュー待ち
**次工程:** superpowers:writing-plans で実装プランを作成

## 1. 概要

codex-design-review skill が Claude Code と Codex の中継に使う一時ファイル群を、
対象プロジェクトのルート直下 `tmp-cdr/` ではなく **OS の一時領域（`/tmp`、`TMPDIR` 尊重）** に置くよう変更する。

**動機:** 現状はプラグインを有効化した *任意の対象プロジェクト* のルートに `tmp-cdr/` が毎回作成され、
そのプロジェクトの git に untracked として現れる。プラグイン自身のリポジトリは `.gitignore` 済みだが、
skill が実際に動くのは対象プロジェクト側であり、そちらは保護されない。これがプラグインによる構造的な汚染になっている。

**実現可能性の根拠:** 中継ファイル群（プロンプト・verdict・events・decisions）は
Claude Code（オーケストレータ）と Codex ホストプロセスのみが読み書きしており、
**Codex のサンドボックス内モデルは一切触らない**。
`scripts/codex-review.sh` の役割分担:

- プロンプト読み込み = スクリプトが `cat`（ホスト側）。
- レビュー対象 = `-C "$proj" -s read-only`（Codex はプロジェクトを read-only 参照するだけ）。
- verdict 書き出し = `-o "$verdict"`（Codex ホストプロセスが書く。サンドボックスが制限する「モデルが起動する子プロセスの書き込み」とは別レイヤー）。
- events = スクリプトが `> "$events"` でリダイレクト（ホスト側）。

したがって作業ディレクトリが `/tmp` でも Codex の動作は不変。実機でも `/tmp` への書き込み・読み出し・削除が通ることを確認済み。

## 2. 確定済みの設計判断

議論（2026-06-11）で確定した事項。**実装時に蒸し返さないこと。**

1. **既定の置き場所**: `mktemp -d "${TMPDIR:-/tmp}/codex-design-review-XXXXXX"`。`TMPDIR` を尊重する。
2. **フォールバック**: `/tmp` 系への作成が権限/サンドボックスで失敗した場合、**自動で** `$CLAUDE_PROJECT_DIR/.claude/tmp-cdr/run-XXXXXX` 配下にフォールバックする。**両方失敗した場合**（`.claude/` も書けない場合）は、作業ディレクトリを確保できないため、レビューをスキップしロックを削除してユーザーに報告する（既存の「codex 不在時はブロックせずスキップ」哲学と同じ）。
3. **フォールバック先の git 対策**: `.claude/` 配下に置く（ルートより目立たず、多くのプロジェクトで既に gitignore 済み）。対象プロジェクトの `.gitignore` への自動追記は **しない**。
4. **解決は1回・状態は単一パス**: 前処理で作業ディレクトリを1回だけ解決し、Claude はそのパス（`$work`）をリテラルで保持して全ラウンドで再利用する。
5. **`uuid` 廃止**: ユニーク性は `mktemp -d` が担保するため、現状の `uuid=$(uuidgen)` と `$uuid-*` 命名は不要。作業ディレクトリ内は固定名を使う。
6. **変更スコープ**: `skills/codex-design-review/SKILL.md` と `README.md` を修正 + 本 spec を新規作成。`uuid` 廃止に伴い唯一の `uuidgen` 使用箇所が消えるため、README の前提条件（`README.md:16`）から `uuidgen` を削除し `jq` のみにする。過去の plan ドキュメント（`docs/superpowers/plans/2026-06-10-codex-design-review.md`）は当時の記録として温存する。`scripts/codex-review.sh` / `convergence.sh` / `hooks/` / `tests/` は無改修。
7. **`.gitignore` の `/tmp-cdr/` 行**: 今回スコープ外として温存（無害）。

## 3. アーキテクチャ

### 3.1 影響範囲

変更は `skills/codex-design-review/SKILL.md` のみ。
`scripts/codex-review.sh` は out_dir を引数で受けて `mkdir -p` するだけなので、渡されるパスが `/tmp` 配下でもそのまま動く（無改修）。
`tests/` は独自 fixture（`$SBX/tmp-cdr/...`）を out_dir として渡しており、SKILL の選択に依存しないため無改修。

### 3.2 作業ディレクトリの解決（前処理）

前処理で次の1コマンドを実行し、`WORK=` を出力する。Claude は出力されたパスを以降リテラルで使う。

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

`ERROR=`（`exit 1`）が返った場合は作業ディレクトリを確保できていないため、Claude は
**ロックを削除してレビューをスキップし、その旨をユーザーに報告する**（§5）。`$work` が空のまま
後続の `$work/r1` 等を組み立ててはならない。

### 3.3 ファイル配置（作業ディレクトリ内・固定名）

| 用途 | 旧パス | 新パス |
|---|---|---|
| Round1 プロンプト | `$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-prompt.md` | `$work/prompt.md` |
| Round1 出力 | `$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-r1` | `$work/r1` |
| Round2 プロンプト | `tmp-cdr/$uuid-prompt2.md` | `$work/prompt2.md` |
| Round2 出力 | `$CLAUDE_PROJECT_DIR/tmp-cdr/$uuid-r2` | `$work/r2` |

Round1/Round2 出力ディレクトリ内のファイル名（`verdict.json` / `events.jsonl` / `decisions.json`）は不変。

人間向けの判断ドキュメント（`docs/superpowers/reviews/YYYY-MM-DD-<topic>-codex-roundN.md`）は一時ファイルではないため対象外（従来どおり）。

## 4. データフロー

1. **前処理**: 作業ディレクトリ `$work` を解決（§3.2）。レビュー記録用 `docs/superpowers/reviews/` の作成・ロック作成は従来どおり。
2. **Round1**: `$work/prompt.md` を生成 → `codex-review.sh round1 ... "$work/prompt.md" "$work/r1"` → `$work/r1/verdict.json` 等を取得。`decisions.json` も `$work/r1` に書く。
3. **Round2**: `$work/prompt2.md` を生成 → `codex-review.sh round2 ... "$work/prompt2.md" "$work/r2"`。
4. **収束判定**: `convergence.sh "$work/r1/verdict.json" "$work/r1/decisions.json" "$work/r2/verdict.json" "$work/r2/decisions.json"`。
5. **完了処理**: 後始末を `[ -n "${work:-}" ] && rm -rf -- "$work"` に簡素化。ロック削除・完了サマリは従来どおり。

## 5. エラーハンドリング / 不変条件

- **`/tmp` 作成失敗 → `.claude/tmp-cdr/run-XXXXXX` へ自動フォールバック**（§3.2）。
- **`/tmp` と `.claude/` の両方が失敗 → `ERROR=`（`exit 1`）**。Claude はロックを削除してレビューをスキップし、ユーザーに理由を報告する（ブロックしない）。`$work` が空のまま後続パスを組み立てない。
- 後始末は `[ -n "${work:-}" ] && rm -rf -- "$work"`（`$work` が空のとき `rm` を実行しない安全ガード）。エラー中断時も実行する（従来の「ロック・一時ファイルは必ず削除」不変条件を維持）。
- 既存不変条件は不変:
  - Codex は常に read-only。
  - 1 ドキュメントあたり Codex 呼び出しは最大 2 回。
  - codex CLI 不在 / 認証切れ / タイムアウト → ブロックせずスキップし、必ずユーザーに報告。
  - ロックファイル `$CLAUDE_PROJECT_DIR/.claude/.codex-design-review.lock` は現状維持。

## 6. テスト / 検証

1. **既存 bats のグリーン維持**: `tests/codex-review.bats` / `convergence.bats` / `hook.bats` / `schema.bats` が引き続き通ること（無改修だが回帰確認）。
2. **解決コマンドの実機確認**:
   - 正常系: `${TMPDIR:-/tmp}` 経路で `WORK=/tmp/codex-design-review-XXXXXX` が返る。
   - フォールバック系: `TMPDIR` を書き込み不可な値にした状態で `.claude/tmp-cdr/run-XXXXXX` 経路に落ち、`WORK=` が返る。
   - 両方失敗系: `TMPDIR` も `$CLAUDE_PROJECT_DIR` も書けない状況で `ERROR=` を出力し `exit 1` すること（`WORK=` を空で返さない）。
3. **後始末確認**: `[ -n "${work:-}" ] && rm -rf -- "$work"` 後に作業ディレクトリが残らないこと。`$work` が空のとき `rm` が走らないこと。
4. **README 整合確認**: `README.md` の前提条件から `uuidgen` が削除され、`jq` のみになっていること。

## 7. スコープ外（YAGNI）

- `CDR_WORK_DIR` 等の環境変数による作業 root の上書き（フォールバックで十分なため今回は作らない）。
- 過去 plan ドキュメントの文言同期。
- プラグイン `.gitignore` の `/tmp-cdr/` 行の削除。
