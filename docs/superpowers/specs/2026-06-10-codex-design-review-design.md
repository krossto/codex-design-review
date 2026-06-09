# codex-design-review プラグイン設計書

**日付:** 2026-06-10
**ステータス:** ユーザーレビュー待ち
**次工程:** superpowers:writing-plans で実装プランを作成(別セッションのエージェントが担当)

## 1. 概要

Claude Code(Superpowers フロー)が作成する**設計文書(spec)と実装プラン(plan)**を、OpenAI Codex CLI にクロスモデルレビューさせる Claude Code プラグイン。

**理論的根拠:** Claude と Codex(GPT 系)は訓練系統が異なるため、異なる種類のミスを検出できる。Superpowers 標準のレビューは Claude subagent による自己レビューであり、モデル固有のバイアスを共有する。レビュアーを別モデルにすることで独立した検証性を得る。

**レビュアーの姿勢:** 誠実かつ、やや批判的ではあるが建設的。

### スコープ

| 対象 | レビューする |
|---|---|
| spec(`docs/superpowers/specs/**`) | ✅ |
| plan(`docs/superpowers/plans/**`) | ✅ |
| 実装コード・テストコード | ❌(スコープ外。将来 `codex exec review` で拡張可能だが今回は作らない) |

## 2. 確定済みの設計判断

議論(2026-06-10、hq セッション)で確定した事項。**実装時に蒸し返さないこと。**

1. **レビュー対象は spec / plan の2点のみ**。コードレビューは無し。
2. **起動制御はプロジェクト単位**。プラグインはユーザーレベルでインストールし、対象プロジェクトの `.claude/settings.json` で有効化(B案: hooks + skill)。
3. **不一致時のエスカレーション**: 同一論点が2ラウンド未解決なら、その論点だけ抜き出してユーザーに三択(Codex 案採用 / Claude 案維持 / 保留)を提示。
4. **独立性**: Codex には Claude の思考履歴を渡さない。成果物(spec / plan)とポインタのみ渡す。
5. **文脈取得**: Codex 自身が `-C <プロジェクトルート>` + read-only サンドボックスでコードベースを探索する(AGENTS.md はネイティブ自動ロード)。プロンプトに全文脈を詰め込まない。
6. **トリガー方式**: 同期 `codex exec`(Claude Code の Bash `run_in_background` で非ブロッキング実行)+ 2ラウンド目は `codex exec resume <session-id>`。agmsg 等の非同期メッセージングは不採用(常駐セッション前提が今回の要求応答型ループに合わないため)。
7. **配布形態**: 個人プラグイン(リポジトリ名 = プラグイン名 = `codex-design-review`)。

## 3. アーキテクチャ

### 3.1 リポジトリ構成

```
codex-design-review/
├── .claude-plugin/
│   └── plugin.json              # プラグインマニフェスト
├── hooks/
│   ├── hooks.json               # PostToolUse hook 定義
│   └── on-design-doc-written.sh # トリガー判定スクリプト
├── skills/
│   └── codex-design-review/
│       ├── SKILL.md             # レビューループの手順書(本体)
│       ├── reviewer-prompt-spec.md   # spec 用レビュアープロンプト雛形
│       └── reviewer-prompt-plan.md   # plan 用レビュアープロンプト雛形
├── schemas/
│   └── verdict-schema.json      # Codex の構造化出力スキーマ
├── tests/                       # bats テスト(hook 判定・スタブでのループ検証)
└── docs/superpowers/            # 本プロジェクト自身の spec / plan
```

### 3.2 動作フロー全体

```
[Superpowers brainstorming が spec を Write]
        │
        ▼ (ハーネスが決定論的に実行)
[PostToolUse hook: on-design-doc-written.sh]
  - 書かれたパスが docs/superpowers/{specs,plans}/**/*.md か判定
  - プロジェクトで本プラグインが有効か判定
  - 該当時のみ additionalContext で「codex-design-review スキルを実行せよ」を注入
        │
        ▼
[Claude: codex-design-review スキル(レビューループ)]
  Round 1:
    1. codex exec を read-only で起動(バックグラウンド) → verdict JSON
    2. 指摘ごとに 採用/拒否/保留 を判定 → 判断ドキュメント出力
    3. 採用分を spec/plan に反映
  Round 2:
    4. codex exec resume で更新版 + 判断ドキュメントを再レビュー
    5. 収束判定
        │
        ├─ approved or 全論点解決 → 完了サマリを出力して通常フローへ復帰
        └─ 未解決論点あり → 論点ごとにユーザーへ三択を提示(AskUserQuestion)
```

## 4. コンポーネント詳細

### 4.1 plugin.json

```json
{
  "name": "codex-design-review",
  "version": "0.1.0",
  "description": "Cross-model review of Superpowers spec/plan documents by OpenAI Codex CLI"
}
```

(正確なフィールドは実装時に plugin-dev の作法に合わせる)

### 4.2 Hook(トリガー)

- **イベント:** `PostToolUse`、matcher は `Write|Edit|MultiEdit`(Edit/MultiEdit も対象にするのは、spec/plan が部分修正で完成するケースがあるため)
- **判定ロジック(スクリプト内、bash):**
  1. tool_input の `file_path` が `docs/superpowers/specs/**/*.md` または `docs/superpowers/plans/**/*.md` にマッチするか
  2. プロジェクト単位の有効化チェック(下記 4.6)
  3. **ループ中の再発火抑止:** レビューループ中に Claude が spec を改訂すると hook が再発火する。`$CLAUDE_PROJECT_DIR/.claude/.codex-design-review.lock`(ロックファイル)が存在する間は発火しない。ロックの作成・削除はスキル側の手順に含める。stale lock 対策として、ロックファイルが 60 分より古い場合は無視する。
- **出力:** 条件成立時のみ JSON で `additionalContext` を返し、「`codex-design-review` スキルを起動してレビューループを実行せよ。対象: <path>」と指示。**hook は判定と注入のみ**を行い、Codex 実行などの重い処理は一切しない。
- **フェイルセーフ:** いかなるエラーでも exit 0(Write/Edit 本体を絶対に妨げない)。

注: hook はあくまで「確実な発火装置」。実際のレビュー実行を行うのは Claude(スキルの手順)である。Claude が注入指示を無視するリスクは Superpowers 同様 description / 文言の強さで担保し、運用で調整する。

**軽微な編集の扱い:** typo 修正などレビュー済みドキュメントへの軽微な編集でも hook は発火する(hook 側では意味的な判定をしない)。この場合、スキル冒頭の判断基準として「設計内容に実質的変更が無い編集はレビューをスキップし、スキップした旨を一言報告する」を明記する。判定はモデルに委ねるが、スキップ時も必ず報告させることで黙殺を防ぐ。

### 4.3 スキル(レビューループ本体)

`skills/codex-design-review/SKILL.md` に手順を記述。要点:

**前処理:**
1. 対象ドキュメント種別(spec / plan)とプロジェクトルートを特定
2. ロックファイルを作成(4.2 の再発火抑止)
3. `uuidgen` で実行 ID を生成(一時ファイル名・セッション対応付けに使用。複数プロジェクト並行実行時の衝突回避)

**Round 1:**
4. レビュアープロンプトを組み立て(4.4)、以下を Bash `run_in_background` で実行:

```bash
codex exec \
  -C <プロジェクトルート> \
  -s read-only \
  --output-schema <plugin>/schemas/verdict-schema.json \
  -o /tmp/cdr-<uuid>-r1.json \
  --json \
  "<レビュアープロンプト>" > /tmp/cdr-<uuid>-r1-events.jsonl 2>&1
```

   - `--json` の JSONL イベントから **session id を取得**(Round 2 の resume に必要)
5. verdict JSON をパースし、指摘(findings)を列挙
6. **各指摘を superpowers:receiving-code-review の規律で技術的に検証**(迎合禁止・コードベースの現実に照らして判断)し、採用 / 拒否 / 保留 を理由付きで決定
7. 判断ドキュメントを `docs/superpowers/reviews/YYYY-MM-DD-<topic>-codex-round1.md` に出力(4.5 のフォーマット)
8. 採用した指摘を spec/plan に反映

**Round 2:**
9. `codex exec resume <session-id>` で再レビューを依頼。渡すもの: 更新済みドキュメントのパス + 判断ドキュメントのパス(拒否理由を Codex が読めるようにする = 反論の機会)
10. verdict をパースし、6〜8 と同様に処理。判断ドキュメントは round2 として出力

**収束判定:**
- Round 2 の verdict が `approved`、または争点(Claude が拒否し Codex が再主張した指摘)が無い → **完了**。完了サマリ(指摘数 / 採用数 / 拒否数 / 保留数)をユーザー向けに出力し、ロックを削除して通常フローへ復帰
- 同一論点が2ラウンド経ても未解決 → **その論点だけを抜き出して** AskUserQuestion で三択提示: ①Codex 案を採用 ②Claude 案を維持 ③保留(ドキュメントに保留として記録)。ユーザー裁定を判断ドキュメントに追記して完了
- ラウンド上限は **2 で固定**(将来設定化する場合もデフォルトは 2)

### 4.4 レビュアープロンプト

spec 用と plan 用の2雛形。共通の構成:

1. **役割宣言:** 「あなたは別の AI エージェント(Claude)が作成した設計文書のレビュアー。誠実かつ、やや批判的ではあるが建設的に。」
2. **文脈取得の指示:** リポジトリを read-only で探索し、AGENTS.md / CLAUDE.md / README / 関連コードを読んでから判断すること。一般論ではなく**このプロジェクトの現実**に基づく指摘のみ行うこと。
3. **レビュー対象:** 対象ドキュメントのパス + 関連参照先のポインタ(Claude が組み立て時に列挙)
4. **観点(spec 用):** 完全性(TBD・placeholder)/ 内部整合性 / 曖昧さ / 過剰設計(YAGNI)/ 実現可能性 / 見落とされたリスク・エッジケース
5. **観点(plan 用):** spec との整合(過不足・スコープクリープ)/ タスク分解の妥当性 / TDD 手順の有無 / 依存順序 / 検証ステップの有無
6. **出力指示:** verdict スキーマに従うこと。指摘は actionable なもののみ。**各指摘に具体的な修正案を必ず添える**こと(ユーザー要求: 指摘事項とその修正案を複数列挙)。

Round 2 では「判断ドキュメントの拒否理由を読み、納得なら取り下げ、納得できなければ理由を添えて再主張せよ」を追加。

### 4.5 verdict スキーマと判断ドキュメント

**verdict-schema.json(構造化出力):**

```json
{
  "verdict": {
    "overall": "approved | revise",
    "confidence": 0.0-1.0,
    "summary": "全体講評(短文)"
  },
  "findings": [
    {
      "id": "F1",
      "severity": "critical | important | minor",
      "section": "対象セクション名/見出し",
      "issue": "何が問題か",
      "why": "なぜ問題か",
      "suggestion": "具体的な修正案"
    }
  ]
}
```

(JSON Schema 形式での正確な定義は実装時に作成。OpenAI 公式 Cookbook「Build Code Review with the Codex SDK」の verdict 構造を参考にする)

**判断ドキュメント(`docs/superpowers/reviews/…-codex-roundN.md`):** Markdown。ヘッダに対象ドキュメント・ラウンド・Codex セッション ID・モデル名を記録し、本文は指摘ごとの表:

| ID | 深刻度 | 指摘(要約) | 判断 | 理由 |
|---|---|---|---|---|
| F1 | important | … | 採用 / 拒否 / 保留 / ユーザー裁定 | … |

### 4.6 プロジェクト単位の有効化

- **正攻法:** 対象プロジェクトの `.claude/settings.json` の `enabledPlugins` に本プラグインを追加し、コミットする。プラグインが無効なプロジェクトでは hook 自体が登録されない(はず)。
- **検証事項(実装時):** プラグイン同梱 hook が per-project の enablement に正しく従うかを実機確認する。**従わない場合のフォールバック:** hook スクリプト冒頭で `$CLAUDE_PROJECT_DIR/.claude/settings.json` 内の有効化フラグ(または marker ファイル `.claude/codex-design-review.enabled`)を確認し、無ければ即 exit 0。
- 導入手順(README に記載する):
  1. ローカル marketplace 登録 + `/plugin install codex-design-review`(初回のみ。正確な手順は実装時に plugin-dev の作法で確定)
  2. 対象プロジェクトで `enabledPlugins` を設定してコミット

## 5. 安全・運用要件

- Codex 実行は**常に `-s read-only`**。`--dangerously-bypass-approvals-and-sandbox` は使用禁止(ユーザーのグローバル安全方針と一致)。レビュアーは技術的にファイル変更不可能であること。
- **MCP 起因の既知バグ対策:** `--json` / `--output-schema` は MCP ツール有効時に無視される報告がある(openai/codex#15451)。レビュー実行時は MCP を無効化するか(`-c` での無効化方法を実装時に確認)、ローカル v0.138.0 での再現有無を検証して対策を決める。
- **モデル:** 既定ではユーザーの `~/.config/codex/config.toml` に従う(現状: 既定モデル + `model_reasoning_effort = "high"`)。プロジェクト固有の上書きは将来課題(YAGNI)。
- **タイムアウト:** Bash のフォアグラウンド上限(10分)を避けるため `run_in_background` で実行し完了を待つ。15 分を超えたら中断してユーザーに報告。
- **コスト意識:** 1 ドキュメントあたり最大 2 ラウンド = Codex 呼び出し最大 2 回。それ以上は構造的に発生しない。

## 6. エラー処理

| 状況 | 挙動 |
|---|---|
| `codex` CLI が無い / 認証切れ | レビューをスキップし、その旨をユーザーに通知して通常フロー続行(ブロックしない) |
| verdict JSON が不正・欠落 | フォーマット注意を添えて 1 回だけ再依頼。再失敗ならユーザーに報告してスキップ |
| `resume` で `-o` が機能しない(既知報告) | stdout / JSONL イベントからのキャプチャにフォールバック |
| session id が取得できない | Round 2 を新規 `codex exec`(更新版ドキュメント + round1 判断ドキュメントを渡す)で代替 |
| hook スクリプト内エラー | 常に exit 0。Write/Edit を妨げない |
| タイムアウト(15 分) | バックグラウンドジョブを停止し、ユーザーに報告してスキップ |

## 7. テスト戦略

- **Codex スタブ:** 環境変数(例: `CDR_CODEX_BIN`)で `codex` バイナリを差し替え可能にし、定型 verdict JSON を返すスタブスクリプトでループロジックを API 消費ゼロでテストする。スタブで「approved」「revise→approved」「2ラウンド不一致」の 3 シナリオを検証。
- **hook 判定テスト:** bats で、対象パス/非対象パス/ロック有り/無効プロジェクト の各ケースを検証。
- **受け入れテスト(手動・実 API 1回):** サンドボックスプロジェクトで spec を書き、hook 発火 → 実 Codex レビュー → 判断ドキュメント生成 → 収束、まで通す。

## 8. スコープ外(YAGNI)

- 実装コード・テストコードのレビュー(`codex exec review` の活用)
- 複数レビュアー(panel / council)、Gemini 等の他モデル対応
- agmsg 等による常駐エージェント間メッセージング
- CI / GitHub Actions 統合
- ラウンド数・観点のプロジェクト別カスタマイズ(設定ファイル機構)

## 9. 実装時の検証事項(次セッションへの引き継ぎ)

実装プラン作成前に以下を実機で確認すること(すべて codex-cli **0.138.0** で):

1. `codex exec --json` の JSONL から **session id をどのフィールドで取得できるか**
2. `codex exec resume` で `--output-schema` / `-o` が使えるか(使えなければ §6 のフォールバック)
3. **MCP 有効時に `--output-schema` が無視されるバグ**(#15451)が手元で再現するか。再現する場合の無効化フラグ
4. プラグイン同梱 hook が **per-project enablement に従うか**(§4.6)
5. ローカル marketplace 登録〜 `/plugin install` の正確な手順(plugin-dev プラグイン参照)

### 参考資料

- OpenAI 公式: Non-interactive mode / CLI reference / Build Code Review with the Codex SDK (Cookbook)
- Claude Code 公式: Hooks reference / Plugins
- 先行例: hamelsmu/claude-review-loop(Stop hook + 並列 Codex)、cathrynlavery/codex-skill(hooks でプラン自動レビュー)、alecnielsen/adversarial-review(4フェーズ debate と circuit breaker)
- Superpowers 内部: `docs/superpowers/specs/2026-01-22-document-review-system-design.md`(レビューループと人間エスカレーションの先行設計)
