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

## Round 1

5. **プロンプト生成**: 種別に応じて `reviewer-prompt-spec.md` か `reviewer-prompt-plan.md` を読み、`{{TARGET_PATH}}` を対象パスに、`{{REFERENCES}}` をあなたが把握している関連参照(対応 spec のパス等)に置換し、`$work/prompt.md` に書き出す。
6. **Codex 実行**(read-only・バックグラウンド・最大15分)。Bash を `run_in_background: true` で:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/codex-review.sh" round1 \
     "$CLAUDE_PROJECT_DIR" \
     "$CLAUDE_PLUGIN_ROOT/schemas/verdict-schema.json" \
     "$work/prompt.md" \
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
