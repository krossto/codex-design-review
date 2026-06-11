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
- `jq` が利用可能。

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
