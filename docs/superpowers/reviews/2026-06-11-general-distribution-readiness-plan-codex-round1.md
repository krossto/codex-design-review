# Codex レビュー判断: 一般配布対応リファクタ plan (round 1)

- 対象: `docs/superpowers/plans/2026-06-11-general-distribution-readiness.md`
- ラウンド: 1
- Codex thread_id: 019eb5ef-4b43-7321-a114-0131bcd23f5c
- overall: revise / confidence: 0.88
- 講評: 主要スコープは妥当だが、フラグ廃止の順序が spec の条件付き判断とズレ、一部監査/TDD 手順に穴。

| ID | 深刻度 | 指摘(要約) | 判断 | 理由 |
|---|---|---|---|---|
| F1 | important | フラグ廃止(Task2)が F1 実機検証(Task8)より前。失敗時に退行リスク、plan 内で完了条件が閉じていない | 採用 | spec は条件付き。preflight ゲートを Task1 へ前倒し、条件付き＋フォールバックを plan 内に明記 |
| F2 | important | Task3-7 が実装後 grep/jq 中心で先行する赤テストが無い。日本語監査が Task7 で初出 | 採用 | no-japanese / manifest テストを Task2 で前倒し赤設置。プロンプトのプレースホルダ検証も追加 |
| F3 | important | `grep -rlED` の `-D` は GNU grep で device-action 引数を食う(実バグ) | 採用 | `grep -rlE` に修正、`status==1`＋空出力で判定 |

3件すべて受理し plan を改訂済み。
