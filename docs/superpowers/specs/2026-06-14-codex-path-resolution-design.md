# Codex 実行パス / 設定ディレクトリ解決の堅牢化 設計書

**日付:** 2026-06-14
**ステータス:** ユーザーレビュー待ち
**次工程:** superpowers:writing-plans で実装プランを作成

## 1. 概要

`scripts/codex-review.sh` が依存する 2 つの解決処理 —— **codex 実行ファイルの解決** と **`CODEX_HOME`（設定/認証ディレクトリ）の解決** —— を、主要なインストール/配置パターンをフォールバックとして確実に確認するよう堅牢化する。

**動機:** 現状、

1. 実行ファイルは `${CDR_CODEX_BIN:-codex}` で **PATH 解決のみ**に依存する（`codex-review.sh:35`）。PostToolUse フックなど PATH が最小化された文脈では、npm グローバル導入の `codex` が PATH に乗らず解決できないことがある。
2. `CODEX_HOME` 解決は `~/.config/codex/auth.json` の **存在のみ**を見る（`codex-review.sh:37-40`）。これは Codex の公式既定 `~/.codex` を取りこぼし、かつ認証保存が OS keyring の場合に `auth.json` が存在しないため検出できない。

いずれも「稀に codex が見つからない / 認証ディレクトリが特定できない」事象の原因になりうる。

**調査結果（公式ドキュメント, 2026-06 時点）:**

| 項目 | 事実 | 出典 |
|---|---|---|
| 設定ディレクトリ | `CODEX_HOME`（既定 `~/.codex`）。`config.toml`・`auth.json` はここに置かれる | [Codex Config (advanced)](https://developers.openai.com/codex/config-advanced) |
| XDG `~/.config/codex` | **Codex は非対応**（コミュニティ要望段階）。`~/.config/codex` は環境固有のケース | [Codex Config (advanced)](https://developers.openai.com/codex/config-advanced) |
| 認証保存 | `cli_auth_credentials_store` 既定 `auto` = OS keyring 優先・無ければ `auth.json`。**keyring 時は auth.json が存在しない** | [Codex Auth](https://developers.openai.com/codex/auth) |
| 実行ファイル | `npm i -g @openai/codex` / Homebrew / 単体バイナリ | [@openai/codex (npm)](https://www.npmjs.com/package/@openai/codex) |

## 2. 確定済みの設計判断

議論（2026-06-14）で確定した事項。**実装時に蒸し返さないこと。**

1. **構成（アプローチ A）**: 解決ロジックを新規ヘルパー `scripts/resolve-codex.sh` に切り出し、`codex-review.sh` が source する。ヘルパーは **関数定義のみ**で副作用を持たない（`set` 等で親シェルの挙動を変えない）。bats で単体テスト可能にする。
2. **実行ファイル解決の優先順**: `CDR_CODEX_BIN`（既存オーバーライド、検証せずそのまま使用＝後方互換）→ `command -v codex`（PATH）→ `npm prefix -g` の `/bin/codex`（`npm` が PATH 上にあり prefix が非空のときのみ。`npm bin -g` は新しい npm で廃止済みのため**使わない**）→ 一般的な場所（`$HOME/.npm-global/bin`, `/usr/local/bin`, `/opt/homebrew/bin`）。最初に見つかった実行可能ファイルを採用。
   - **保証範囲（F3）**: npm 系候補は **`npm` 自体が PATH 上にある**ことが前提。nvm / asdf / Volta などでフックがサニタイズされた環境で起動し、`npm` も `codex` も PATH に無い場合は自動解決できないことがある。その場合は **`CDR_CODEX_BIN` を escape hatch** として案内する（脆弱なバージョン glob による自動探索は §7 のとおり行わない）。
3. **preflight 失敗の明示**: 実行ファイルがどこにも無い場合、`codex-review.sh` は **即座に exit 3** とし、導入方法（`npm i -g @openai/codex` / `CDR_CODEX_BIN` 設定）を案内するエラーを stderr に出す。現状の「実行して初めて失敗が分かる」挙動を改善する。**preflight は引数パース直後・`mkdir`/`cat` より前**に実行し（fail-fast。作業前に確実に弾く）、診断メッセージが path/source エラーに紛れないようにする（F2）。exit コード体系（3 = codex 異常終了）は変えず、説明に「実行ファイル未検出（preflight）」を追記する。
4. **`CODEX_HOME` 解決（2 パス方式）**: 既存の `CODEX_HOME` が設定済みなら尊重（上書きしない）。未設定の場合のみ次を実行する。
   - **パス1（auth.json 優先）**: `auth.json` を `[$HOME/.codex, $HOME/.config/codex]` の順で探し、最初に在るディレクトリを `CODEX_HOME` として export。
   - **パス2（config.toml フォールバック）**: auth.json がどこにも無ければ、`config.toml` を同じ順で探し、最初に在るディレクトリを export（keyring 認証で auth.json が無いケースに対応）。
   - どちらにも無ければ **未設定のまま**（Codex の既定 `~/.codex` ＋ keyring に委譲。エラーにしない）。
5. **優先順の根拠**: `~/.codex` は Codex 公式既定なので config レベルでは優先。ただし **auth.json（実ファイル認証）の所在を config.toml より優先**する。これにより「`~/.codex` に config.toml のみ存在し、認証は `~/.config/codex/auth.json` にある」実機ケースで正しく `~/.config/codex` を選べる（パス1 がパス2 に優先するため）。
6. **変更スコープ**: 新規 `scripts/resolve-codex.sh`、新規 `tests/resolve-codex.bats`、`scripts/codex-review.sh`（解決部の置換）、`README.md` / `README.ja.md`（前提条件の記述更新）、本 spec。`hooks/` / `convergence.sh` / 既存テストは無改修。
7. **範囲外**: Windows 対応（本プラグインは bash 前提）、Codex 認証の実行そのもの、keyring 内容の検証、`CODEX_HOME` が設定済みだが中身が空のケースの警告（尊重するのみ）。

## 3. アーキテクチャ

### 3.1 影響範囲

| ファイル | 変更 |
|---|---|
| `scripts/resolve-codex.sh` | **新規**。`cdr_resolve_codex_bin` / `cdr_resolve_codex_home` の 2 関数を定義 |
| `scripts/codex-review.sh` | 35 行目・37-40 行目を、ヘルパー source ＋関数呼び出しに置換。preflight 失敗で exit 3 |
| `tests/resolve-codex.bats` | **新規**。解決ロジックの単体テスト |
| `README.md` / `README.ja.md` | 前提条件（解決動作の記述）を一般化 |

### 3.2 `cdr_resolve_codex_bin`

**契約:** 解決した実行ファイルパス（またはコマンド名）を stdout に出力し `return 0`。見つからなければ何も出力せず `return 1`。

解決順:

1. `CDR_CODEX_BIN` が非空 → その値をそのまま出力して `return 0`（検証しない＝後方互換。bare 名・絶対/相対パスのいずれも呼び出し側がそのまま実行）。
2. `command -v codex` が成功 → 解決パスを出力して `return 0`。
3. 候補を順に `[ -x ]` で確認し、最初の実行可能ファイルを出力して `return 0`:
   - `$(npm prefix -g 2>/dev/null)/bin/codex` （npm が PATH 上にある場合のみ。空 prefix の `/bin/codex` 誤検出を避けるため prefix が非空のときだけ候補化）
   - `$HOME/.npm-global/bin/codex`
   - `/usr/local/bin/codex`
   - `/opt/homebrew/bin/codex`
   （`npm` が PATH に無ければ `npm prefix -g` は空となり当該候補はスキップ。npm 呼び出しは PATH 解決が失敗した稀な経路でのみ走る。`npm bin -g` は廃止済みのため候補から除外。）
4. いずれも該当なし → `return 1`。

> 補足（実機確認, 2026-06-14）: 本環境では `codex` が PATH 非搭載で `/home/krossto/.npm-global/bin/codex`（`npm prefix -g`=`~/.npm-global`）に存在し、上記候補1で解決できることを確認済み。`npm bin -g` は本環境の npm では "Unknown command"（廃止）。

### 3.3 `cdr_resolve_codex_home`

**契約:** 必要時のみ `CODEX_HOME` を export する。常に `return 0`（設定不在はエラーにしない）。テスト容易性のため `$HOME` / `$CODEX_HOME` を環境から読む。

ロジック（§2 項目4 の 2 パス方式）:

```
若し CODEX_HOME が非空 → 何もしない（尊重）
さもなくば:
  パス1: for d in "$HOME/.codex" "$HOME/.config/codex":
           [ -f "$d/auth.json" ] なら export CODEX_HOME="$d"; return
  パス2: for d in "$HOME/.codex" "$HOME/.config/codex":
           [ -f "$d/config.toml" ] なら export CODEX_HOME="$d"; return
  どちらも無し → 未設定のまま return
```

### 3.4 `codex-review.sh` への統合

解決処理は **引数パース（`case … esac`）直後・`mkdir -p`／`cat` より前**に置く（F2: fail-fast）。現状 35 行目・37-40 行目にある解決処理は削除し、ここへ集約する。`SCRIPT_DIR` は外部 `dirname` に依存せず bash のパラメータ展開で求める（PATH 最小時でも source できるよう builtin のみ使用）:

```bash
# 引数パース直後
src="${BASH_SOURCE[0]}"
case "$src" in */*) SCRIPT_DIR="${src%/*}";; *) SCRIPT_DIR=".";; esac
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd -P)"
# shellcheck source=resolve-codex.sh
. "$SCRIPT_DIR/resolve-codex.sh"

# preflight: 実行ファイルが無ければ mkdir/cat 等の前に弾く
codex_bin="$(cdr_resolve_codex_bin)" || {
  err "codex CLI not found (PATH / npm global bin / common locations). Install: 'npm i -g @openai/codex', or set CDR_CODEX_BIN."
  exit 3
}

cdr_resolve_codex_home   # CODEX_HOME を必要時のみ export

# …この後で従来どおり mkdir -p "$out_dir" / prompt="$(cat …)" 等
```

`cd`・`pwd`・`source(.)`・`command -v`・`[ -x ]` はいずれも builtin なので、PATH が最小化された文脈でも preflight 自体は到達・実行できる（`npm prefix -g` だけは外部コマンドで、不在時は当該候補がスキップされるのみ）。以降の `"$codex_bin" exec …` 呼び出し（round1/round2）は不変。

## 4. データフロー

1. **source**: `codex-review.sh` が同階層の `resolve-codex.sh` を読み込み、2 関数を定義（副作用なし）。
2. **bin 解決**: `cdr_resolve_codex_bin` を呼び `$codex_bin` を確定。失敗時は err ＋ exit 3（preflight）。
3. **home 解決**: `cdr_resolve_codex_home` を呼び、必要時のみ `CODEX_HOME` を export。
4. **codex 実行**: 既存の round1/round2 ロジック（`</dev/null`・`-s read-only`・`--output-schema` 等）は不変。

## 5. エラーハンドリング / 不変条件

- **実行ファイル未検出 → exit 3（preflight）**。導入方法を案内。`codex-review.sh` ヘッダのコメントを更新（3 = codex 異常終了＋実行ファイル未検出）。
- **設定ディレクトリ未検出 → エラーにしない**。`CODEX_HOME` 未設定のまま Codex 既定（`~/.codex`）＋keyring に委譲。
- **`CODEX_HOME` 設定済み → 常に尊重**（上書きしない）。中身が空でも尊重（ユーザー意図）。
- 既存不変条件は不変:
  - Codex は常に read-only、1 ドキュメントあたり最大 2 ラウンド。
  - codex CLI 不在 / 認証切れ → ブロックせずスキップし、必ずユーザーに報告（スキル側の哲学）。
  - 既存テストは `CDR_CODEX_BIN` を使うため、解決ロジック変更の影響を受けない。

## 6. テスト / 検証

新規 `tests/resolve-codex.bats`（ヘルパーを source して関数を直接検証。`HOME` / `PATH` / `npm` をスタブ）:

**bin 解決:**
1. `CDR_CODEX_BIN` 設定時 → その値を返す。
2. PATH 上に `codex` あり → `command -v` 経由で解決。
3. PATH 上に無し・npm グローバル bin にあり（`npm` スタブが偽 prefix を返し、その `bin/codex` を配置）→ 解決。
4. どこにも無し → `return 1`（非 0）。

**home 解決:**
5. `CODEX_HOME` 設定済み → 尊重（別ディレクトリを指していても上書きしない）。
6. 未設定・`~/.codex/auth.json` あり → `CODEX_HOME=~/.codex`（パス1）。
7. 未設定・`~/.codex` に `config.toml` のみ（auth.json はどこにも無し＝keyring）→ `CODEX_HOME=~/.codex`（パス2）。
8. 未設定・`~/.config/codex/auth.json` のみ → `CODEX_HOME=~/.config/codex`（パス1）。
9. 未設定・両方に `auth.json` → `~/.codex` 優先（パス1 の順序）。
10. 未設定・どちらにも何も無し → `CODEX_HOME` 未設定のまま。
11. **（実機回帰）** 未設定・`~/.codex` に `config.toml` のみ・`~/.config/codex` に `auth.json` → `CODEX_HOME=~/.config/codex`（パス1 がパス2 に優先）。

**統合（`codex-review.sh`）:**
12. **preflight（F2）**: codex も npm も**解決できない制御された環境**で `CDR_CODEX_BIN` 未設定にして実行 → **exit 3** かつ stderr に `codex CLI not found` を含むこと（source/path エラーではなく意図したメッセージであることを assert）。`/usr/bin:/bin` のような既製 PATH は不可（`npm` が `/usr/bin` にある実機では `npm prefix -g` が実 codex を発見して exit 3 にならない）。hermetic にするため:
    - `HOME="$BATS_TEST_TMPDIR/home"`（`.npm-global/bin/codex` を含まない空ディレクトリ。`$HOME/.npm-global/bin` 候補を無効化）
    - `PATH="$BATS_TEST_TMPDIR/emptybin"`（空ディレクトリ。`codex`・`npm` とも不在）
    - 事前条件 assert: その `PATH`/`HOME` 下で `command -v codex` と `command -v npm` がともに失敗すること
    - 子は絶対パスの bash で起動: `run env -i HOME="$HOME" PATH="$PATH" /bin/bash "$script" round1 …`
    - assert: status 3、出力に `codex CLI not found`
    - 前提（テスト環境）: `/usr/local/bin/codex`・`/opt/homebrew/bin/codex` は不在であること（絶対パス候補は env で制御できないため、テスト環境の前提とする）
13. **既存 bats のグリーン維持**: `codex-review.bats` / `convergence.bats` / `hook.bats` / `schema.bats` / `no-japanese.bats` / `skill-structure.bats` が引き続き通ること（`resolve-codex.sh` は scripts/ 配下で no-japanese の対象外）。
    - **既知の既存失敗（F1, 本タスク範囲外）**: `tests/manifest.bats` は削除済み `.claude-plugin/marketplace.json` を参照する 2 テスト（"marketplace.json is valid JSON" / "marketplace plugin entry description notes Superpowers"）を持ち、`de8bc6d`（self marketplace 削除）以降この baseline で既に red。本タスク（パス解決）とは無関係なため green 維持の対象から除外し、別途修正する（§7）。

## 7. スコープ外（YAGNI）

- Windows 対応（`%USERPROFILE%\.codex` 等）。
- `CODEX_HOME` の値の妥当性検証・空ディレクトリ警告。
- keyring の中身検証や `codex login status` の自動実行。
- 過去 plan/spec ドキュメントの文言同期（Task 1 とは別管理）。
- **既存 `tests/manifest.bats` の修正（F1）**: 削除済み `marketplace.json` を参照する pre-existing 失敗。Task 1（marketplace 統合）系の後続として別途扱う。本タスクでは触らない。
- **nvm/asdf/Volta のバージョン glob 自動探索（F3）**: `$HOME/.nvm/versions/node/*/bin/codex` 等はバージョン選択が一意でなく脆弱。自動探索は行わず、サニタイズ環境では `CDR_CODEX_BIN` を使う運用とする。
