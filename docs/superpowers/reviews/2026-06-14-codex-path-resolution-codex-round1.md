# Codex Review Judgment: codex-path-resolution spec (round 1)

- Target: docs/superpowers/specs/2026-06-14-codex-path-resolution-design.md
- Round: 1
- Codex thread_id: 019ec685-08e4-7f10-8c49-312e3b2a9da1
- overall: revise / confidence: 0.86
- Summary: 設計はおおむね一貫しているが、検証セット・preflight 順序・PATH 最小化時の解決可能性に未接地の点があるとの指摘。3件すべて技術的に妥当と判断し accept。

| ID | Severity | Finding (summary) | Decision | Reason |
|---|---|---|---|---|
| F1 | important | §6 が `manifest.bats` の green 維持を要求するが、同テストは削除済み `marketplace.json` を参照し baseline で既に red。受け入れ基準が不整合 | accept | marketplace.json 不在のため red を確認。本タスク無関係の pre-existing 失敗。§6 から除外し §7 で別途扱いと明記 |
| F2 | important | preflight が実際には最初でない（`mkdir`/`cat` の後）。`SCRIPT_DIR` が外部 `dirname` 依存で PATH 最小時に誤診断。test 12 の「PATH 空」設定と矛盾 | accept | fail-fast として preflight を引数パース直後・mkdir/cat 前へ移動。`SCRIPT_DIR` を `${BASH_SOURCE[0]%/*}`（builtin）で算出。test 12 を現実的 PATH＋意図メッセージ assert に修正 |
| F3 | minor | npm フォールバックは `npm` が PATH 上にある前提。nvm/asdf/Volta のサニタイズ環境では npm も codex も失われ得る | accept | 保証範囲を明記し `CDR_CODEX_BIN` を escape hatch として案内（方針B）。脆弱なバージョン glob 自動探索は YAGNI として §7 で除外。`npm bin -g` 廃止も反映 |

## 反映内容
- §2.2/§2.3: 保証範囲・escape hatch・preflight を最初に実行する旨を追記。
- §3.2: 候補リストを `npm prefix -g` 主軸に整理（`npm bin -g` 除外）。
- §3.4: source＋preflight＋home 解決を引数パース直後へ集約、`SCRIPT_DIR` を dirname 非依存に。
- §6: test 12 を現実的 PATH 化、test 13 から `manifest.bats` を除外し pre-existing 失敗を明記。
- §7: `manifest.bats` 修正（F1）と version glob 自動探索（F3）を scope 外として追記。
