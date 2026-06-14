# Codex Review Judgment: codex-path-resolution spec (round 2)

- Target: docs/superpowers/specs/2026-06-14-codex-path-resolution-design.md
- Round: 2
- Codex thread_id: 019ec685-08e4-7f10-8c49-312e3b2a9da1
- overall: revise / confidence: 0.84
- Summary: F1 は解決確認。F2・F3 を再主張。両者とも妥当で accept し追加修正を反映。

| ID | Severity | Finding (summary) | Decision | Reason |
|---|---|---|---|---|
| F2 | important | test 12 の例 PATH `/usr/bin:/bin` は不確実。npm が /usr/bin にある実機では `npm prefix -g` が実 codex を発見し exit 3 にならない | accept | 本環境はまさに該当（`/usr/bin/npm` 実在、codex は `~/.npm-global/bin`）。HOME と PATH を制御した hermetic テストへ修正（空 PATH＋空 HOME＋絶対 bash＋事前条件 assert） |
| F3 | minor | §2.2（`npm bin -g` を best-effort で残す）と §3.2（廃止・除外）が自己矛盾 | accept | §3.2 に合わせ §2.2 から `npm bin -g` を削除。優先順は `npm prefix -g`／`$HOME/.npm-global/bin`／`/usr/local/bin`／`/opt/homebrew/bin` のみ |

## 反映内容
- §2.2: `npm bin -g` の記述を削除し §3.2 と整合。
- §6 test 12: `/usr/bin:/bin` 例を撤回し、制御された HOME/PATH・絶対 bash・事前条件 assert による hermetic テストへ書き換え。
