English: [README.md](./README.md)

# codex-design-review

OpenAI Codex CLI を使って spec / plan ドキュメントをクロスモデルレビューする Claude Code プラグイン。

## 概要 / 仕組み

1. PostToolUse hook が `docs/superpowers/{specs,plans}/*.md` への書き込みを検知する。
2. hook が `/codex-design-review:review` スキルを起動する。
3. スキルが Codex を read-only で最大 2 ラウンド実行し、指摘を吟味・反映する。未解決の意見の相違はユーザーにエスカレーションする。

## 前提

- OpenAI Codex CLI がインストール済みで認証済み（`codex login status` が "Logged in" を表示）。認証情報が `~/.config/codex` にある場合、スキルは自動で `CODEX_HOME` を解決する。
- `jq` が `PATH` で利用可能。
- [Superpowers](https://github.com/amidaike/superpowers) の spec/plan ワークフロー（`docs/superpowers/{specs,plans}` 配下のデザインドキュメント）向けに設計されている。Superpowers は推奨だが必須ではなく、`receiving-code-review` スキルが存在しない場合は汎用的なレビュー規律にフォールバックする。

## インストール（スコープベース）

有効化は Claude Code のインストールスコープで制御する。プロジェクトごとのマーカーファイルは不要。

まず marketplace を追加する（マシンごとに一度）:

```bash
claude plugin marketplace add krossto/claude-plugins
```

### 推奨: ローカルスコープ（現在のリポジトリのみで有効）

`/plugin` UI で **Local** を選ぶか、次のコマンドを実行する:

```bash
claude plugin install codex-design-review@krossto-plugins --scope local
```

ローカルスコープにより hook を 1 リポジトリに限定し、他プロジェクトでの意図しないレビューを防ぐことができる。

### チーム向け: プロジェクトスコープ

すべての協力者とレビューを共有するには、プロジェクトスコープでインストールする（コミット済み `.claude/settings.json` に書き込まれる）:

```bash
claude plugin install codex-design-review@krossto-plugins --scope project
```

### 重要: ユーザースコープで有効化しない

ローカルまたはプロジェクトスコープで選択的に有効化する場合、`~/.claude/settings.json`（ユーザースコープ）の `enabledPlugins` にこのプラグインを追加しないこと。ユーザースコープで有効化すると、すべてのプロジェクトで hook が読み込まれ、スコープベースのゲーティングが無効になる。

### スキルの手動呼び出し

レビュースキルは直接呼び出すことも可能:

```
/codex-design-review:review
```

## アップデート

この marketplace はサードパーティのため、プラグインの自動更新は**既定で OFF**。

- **自動更新を有効化（推奨）:** `/plugin` → **Marketplaces** → `krossto-plugins` → **Enable auto-update**。以降は起動時に自動更新され、`/reload-plugins` の実行を促す通知が出る。
- **手動更新:** 下記コマンドを実行し、Claude Code を再起動して反映する。

```bash
claude plugin update codex-design-review@krossto-plugins
```

インストール時のスコープに合わせて `--scope local` / `--scope project` を付ける。本プラグインは version 未指定（SHA 駆動）のため、「最新」は `main` ブランチの HEAD を指す。

## テスト

```bash
bats tests/
```

## スコープ外（YAGNI）

実装・テストコードのレビュー、複数レビュアー、マルチモデル対応、CI 統合、ラウンド数・観点のプロジェクト別カスタマイズ。
