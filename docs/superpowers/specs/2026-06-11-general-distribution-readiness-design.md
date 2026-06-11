# codex-design-review 一般配布対応リファクタ 設計書

**日付:** 2026-06-11
**ステータス:** ユーザーレビュー待ち
**次工程:** superpowers:writing-plans で実装プランを作成

## 1. 概要

codex-design-review プラグインを「個人環境前提」から「一般配布レディ」へ整える。
起動制御を Claude Code ネイティブの installation scope に一本化し、自作フラグファイルを廃止。
配布物の言語を英語へ統一（日本語 README は別途用意）。skill 名を短縮し、Superpowers 依存を明示する。

対象は **A〜E の5項目**を1つのパスでまとめて実施する:

- **A**: skill 名短縮（`codex-design-review` → `review`）
- **B**: Superpowers への**ソフト依存**の明示 + ランタイムフォールバック
- **C**: 環境依存の排除（言語の英語統一 + 個人環境依存の監査）
- **D**: 有効化フラグファイルの廃止
- **E**: 導入スコープの整理（ネイティブ scope・local 推奨）

## 2. 確定済みの設計判断

ブレインストーミング（2026-06-11）で確定。**実装時に蒸し返さないこと。**

1. **E（起動・スコープ）**: 起動制御は Claude Code ネイティブ scope に一本化。README は **local スコープ**（`.claude/settings.local.json`・非共有）を第一推奨とし、project スコープ（`.claude/settings.json`・git 共有）を併記。
2. **D（フラグ廃止）**: 自作の有効化マーカー `.claude/codex-design-review.enabled` を**廃止**。プラグインがそのプロジェクトで scope 導入されていること自体が opt-in となる。**ただしこれは「scope ベースで hook のロードがプロジェクト単位にゲートされる」ことが前提**であり、本プロジェクトの旧 plan（2026-06-10）は逆（`enabledPlugins` はユーザーレベル管理で per-project 自動 enablement は効かない）と記録している。よって**フラグ廃止は §6 の実機検証成功を条件**とし、検証できない/失敗する場合は廃止を見送り自己ゲートを残す（§3.1 フォールバック参照）。
3. **C（言語）**: SKILL 本文・`reviewer-prompt-{spec,plan}.md`・hook の additionalContext・skill description を**英語化**。README は**英語を主**とし、**日本語版 `README.ja.md`** を別ファイルで用意し相互リンク。
4. **A（skill 名）**: skill ディレクトリ `skills/codex-design-review/` → `skills/review/`。呼び出しは `/codex-design-review:review`。**プラグイン名は `codex-design-review` のまま変更しない**。
5. **B（依存）**: Superpowers への依存は**ソフト依存**として扱う。`plugin.json` の `dependencies`（ハード依存）は**使わない**（superpowers を強制インストールしない、cross-marketplace 許可も不要）。代わりに (a) description/README に前提を明示、(b) SKILL の `superpowers:receiving-code-review` 参照を「無ければ一般的なレビュー規律で代替」とフォールバック可能にする。
6. **再入防止ロック**（`.claude/.codex-design-review.lock`）は**維持**。
7. **スコープ外**: 案B 配布移行（別手順書 `~/workspace/claude-plugins-migration.md`）、RCD、バージョン bump。

## 3. アーキテクチャ / 変更点

### 3.1 起動・スコープ（E + D）

**hook（`hooks/on-design-doc-written.sh`）**
- 「2. per-project 有効化マーカー」判定（`[ -f "$proj/.claude/codex-design-review.enabled" ] || exit 0`）を**削除**。
- パス判定（specs/plans）・ロック判定・additionalContext 出力は**維持**。additionalContext 文字列は英語化（§3.2）。
- 結果: プラグインがそのプロジェクトで有効（scope 導入済み）なときのみ hook がロードされ、対象パスへの書き込みで発火する。

**SKILL（`skills/.../SKILL.md`）**
- 前処理からマーカー作成（`touch ....enabled`）の記述を削除。完了処理のマーカー削除記述も削除。
- ロック作成/削除は維持。

**README**
- 「プロジェクトでの有効化（マーカー作成）」節を**削除**。
- 導入手順を scope ベースに置換: marketplace 追加 → `/plugin install codex-design-review@<marketplace>` を **local スコープ**で（`/plugin` UI でスコープ選択、または `--scope local`）導入する手順を第一推奨。project スコープを「チーム共有したい場合」として併記。
- **重要な前提**: local スコープでのゲートを成立させるには、プラグインを **user スコープで有効化しないこと**（`~/.claude/settings.json` の `enabledPlugins` に入れない）。user スコープ有効化が残っていると hook が全プロジェクトでロードされ、ゲートが効かない。README にもこの注意を明記する。

**フォールバック（§6 検証が失敗した場合）**
- scope ベースのゲートが実機で成立しない場合、フラグ廃止を見送り、hook 冒頭の自己ゲートを**維持**する。その際マーカーファイル方式に固執せず、`$CLAUDE_PROJECT_DIR/.claude/settings.local.json`（または `.claude/settings.json`）の `enabledPlugins` に本プラグインが有効化されているかを読む方式も候補とする（plan で実装方式を確定）。

### 3.2 言語・ポータビリティ（C）

英語化する成果物:
- `skills/review/SKILL.md` 本文（frontmatter description は既に英語、本文を英語へ）
- `skills/review/reviewer-prompt-spec.md` / `reviewer-prompt-plan.md`
- `hooks/on-design-doc-written.sh` の additionalContext 文字列（およびコメント）
- **`schemas/verdict-schema.json` の `description`**（`approved = ...` / `全体講評` / `何が問題か` 等。`--output-schema` で Codex に渡るモデル向け配布物のため英語化必須）
- skill / plugin description（既に英語のものは維持）

README:
- `README.md` を英語で書き直す（導入・前提・仕組み・テスト）。
- `README.ja.md` を新規作成（日本語版）。両者の冒頭に相互リンク。

個人環境依存の監査:
- 全ファイルを走査し、ハードコードされた個人パス・特定環境前提が無いか確認。
- **メタデータ方針**: `plugin.json` の `author.name` と `marketplace.json` の `owner.name`/`author.name`（現状 `krossto`）は**作者表示として維持**し、環境依存とは扱わない（除去しない）。
- 既知の一般的記述（`CODEX_HOME` の `~/.config/codex/auth.json` 解決、`$CLAUDE_PROJECT_DIR/.claude/.lock` パス、`/tmp` 作業ディレクトリ）は一般環境で成立するため維持。問題が見つかれば是正。

### 3.3 skill 名短縮（A）

- ディレクトリ `skills/codex-design-review/` を `skills/review/` にリネーム（配下の `SKILL.md`・`reviewer-prompt-*.md` ごと移動）。
- SKILL frontmatter の `name` を `review` に。
- hook の additionalContext が skill 起動を促す文言を、新しい呼び出し名と整合させる（「起動せよ」の対象を `/codex-design-review:review` に）。
- **docs 更新範囲**: `README.md`・`README.ja.md`・本 spec・現行 plugin/marketplace メタデータの呼び出し例**のみ**更新する。過去の `docs/superpowers/specs/**` / `plans/**` / `reviews/**` は**履歴として原則更新しない**（不要な巨大 diff を避ける）。ただし本 spec 自身の旧パス参照は新設計に合わせる。

### 3.4 形式的依存（B）— ソフト依存 + フォールバック

- `plugin.json` に `dependencies` は**追加しない**。
- README（英・日）、および **`plugin.json` と `marketplace.json` の両方の plugin description** に「**Superpowers ワークフロー（spec/plan を `docs/superpowers/{specs,plans}` に作る運用）を前提**とする」旨を明記。
- SKILL 本文の `superpowers:receiving-code-review` 参照を、**フォールバック付き**に書き換える: 「receiving-code-review skill が利用可能ならその規律で吟味する。無ければ、迎合せず技術的根拠に基づきコードベースの現実に照らして accept/reject/hold を判断する、という一般的な規律で代替する」。

## 4. 挙動（変更後の起動フロー）

1. ユーザーがプラグインを local スコープで対象プロジェクトに導入（opt-in）。
2. そのプロジェクトで `docs/superpowers/{specs,plans}/*.md` を書く → hook がパス判定し additionalContext を注入。
3. ロックが新しければ抑止、無ければ skill 起動を指示。
4. skill が `/tmp` 作業ディレクトリで Codex レビューを実行（既存ロジック）。
5. 未導入プロジェクトでは hook 自体がロードされないため、何も起きない（フラグ判定は不要）。

## 5. エラーハンドリング / 不変条件（維持）

- hook はいかなるエラーでも `exit 0`（Write/Edit 本体を妨げない）。
- Codex は常に read-only、1 ドキュメントあたり最大 2 ラウンド。
- codex 不在 / 認証切れ / タイムアウト → ブロックせずスキップしユーザー報告。
- ロックファイルは必ず削除。
- `/tmp` 作業ディレクトリの解決・フォールバック・空ガード cleanup（既存）は不変。

## 6. テスト

- **`tests/hook.bats`**: 全テストがマーカー `touch` 前提 → 改修。
  - 「no marker -> silent exit」テストは概念消滅につき**削除**。
  - 他テストから `touch ....enabled` 行を除去（マーカー無しでも spec/plan パスで発火することを検証する形へ）。
  - additionalContext のアサーションを英語化後の文言・新呼び出し名に整合（例: `test("review")` 等、plan で確定）。
- **`tests/schema.bats` / `convergence.bats` / `codex-review.bats`**: 無影響の見込み。skill ディレクトリ名変更でパス参照があれば是正（plan で確認）。
- 英語化に伴い、テストが日本語固定文言に依存している箇所があれば更新。

**skill リネーム検証（A）**: schema.bats 系または新規テストで次を検証:
- `skills/review/SKILL.md` が存在し、frontmatter が `name: review`。
- `skills/review/reviewer-prompt-spec.md` と `reviewer-prompt-plan.md` が存在。
- 旧 `skills/codex-design-review/` が存在しない。
- hook の additionalContext が `/codex-design-review:review` を含む。

**日本語残存監査（C）**: `rg -n '[ぁ-んァ-ヶ一-龥]' README.md skills/review hooks schemas .claude-plugin` 等で日本語を走査し、意図的な日本語（`README.ja.md`・過去 docs）以外に残っていないことを確認。

**F1 実機検証（D/E の成立条件・必須）**:
- project A に **local スコープ**でインストール、project B は未導入。両者で同一の `docs/superpowers/specs/*.md` 書き込みを行い、**A でのみ** hook の additionalContext が出る（B では何も起きない）ことを実機確認する。
- project スコープでも同様に確認する。
- 前提として、検証中はプラグインを **user スコープで有効化しない**こと（有効化が残ると全プロジェクトで発火しゲート検証にならない）。
- **検証が失敗/不能なら、フラグ廃止（D）を見送り §3.1 のフォールバック（自己ゲート維持）を採用する**。

## 7. スコープ外（YAGNI）

- 案B 配布移行（カタログ/個別リポ化）。本リファクタ完了後に別途実施。
- RCD プラグイン。
- バージョン bump（配布工程で実施）。
- ハード依存（`plugin.json` dependencies）・cross-marketplace 許可設定。
- i18n フレームワーク化（英語統一 + 日本語 README の二本立てで足りる）。
