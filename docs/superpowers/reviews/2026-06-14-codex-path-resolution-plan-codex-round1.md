# Codex Review Judgment: codex-path-resolution plan (round 1)

- Target: docs/superpowers/plans/2026-06-14-codex-path-resolution.md
- Round: 1
- Codex thread_id: 019ec69c-1e0d-74f3-9d6c-dd01f628eedf
- overall: revise / confidence: 0.88
- Summary: spec とおおむね整合・分解も妥当だが、resolver テストが hermetic 不足で、指定フォールバックの1つに failing test が無いとの指摘。2件とも accept。

| ID | Severity | Finding (summary) | Decision | Reason |
|---|---|---|---|---|
| F1 | important | 「未検出」期待テストが絶対パス候補（/usr/local, /opt/homebrew）を考慮せず、npm-prefix テストの PATH に /usr/bin:/bin が混入し実 codex が先勝ちしうる | accept | `skip_if_common_codex_exists` ガードを追加し test4（not found）と統合テストで呼ぶ。npm-prefix テストの PATH を `$TMP/stubbin` のみに純化（スタブ shebang は絶対 /bin/sh で解決され PATH 不要） |
| F2 | minor | `$HOME/.npm-global/bin/codex` フォールバックの failing test が無く、実装が当該分岐を落としても全テスト緑になりうる | accept | npm 不在・`~/.npm-global/bin/codex` 配置で当該パスに解決することを assert する専用テストを追加 |

## 反映内容
- Task1 Step1: `skip_if_common_codex_exists` ヘルパー追加。test3 の PATH を `$TMP/stubbin` に純化。test4（not found）に skip ガード。`~/.npm-global` フォールバックの新規テスト追加（bin 4→5）。
- Task3 Step1: 統合 preflight テストに skip ガード追加。
- 各 Step の件数表記を更新（11→12、12→13、全体13）。
