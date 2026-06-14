Japanese version: [README.ja.md](./README.ja.md)

# codex-design-review

A Claude Code plugin that cross-model reviews spec and plan documents using OpenAI Codex CLI.

## Overview / How it works

1. A PostToolUse hook detects writes to `docs/superpowers/{specs,plans}/*.md`.
2. The hook launches the `/codex-design-review:review` skill.
3. The skill runs OpenAI Codex read-only for a bounded 2-round review loop, judges each finding, applies accepted ones, and escalates unresolved disagreements to the user.

## Prerequisites

- OpenAI Codex CLI installed and authenticated (`codex login status` shows "Logged in"). If credentials live in `~/.config/codex`, the skill resolves `CODEX_HOME` automatically.
- `jq` available on `PATH`.
- Built for the [Superpowers](https://github.com/amidaike/superpowers) spec/plan workflow (design docs under `docs/superpowers/{specs,plans}`). Superpowers is recommended but not required; if its `receiving-code-review` skill is absent, the review falls back to a general discipline.

## Install (scope-based)

Activation is controlled by Claude Code installation scope — no per-project marker file is needed.

First, add the marketplace (once per machine):

```bash
claude plugin marketplace add krossto/claude-plugins
```

### Recommended: local scope (active only in the current repo)

Use the `/plugin` UI and choose **Local**, or run:

```bash
claude plugin install codex-design-review@krossto-plugins --scope local
```

Local scope keeps the hook isolated to one repository and avoids unintended reviews in other projects.

### Team option: project scope

To share reviews with every collaborator, install at project scope (written to committed `.claude/settings.json`):

```bash
claude plugin install codex-design-review@krossto-plugins --scope project
```

### Important: do not enable at user scope

If you install at local or project scope for selective activation, do **not** add the plugin to `enabledPlugins` in `~/.claude/settings.json` (user scope). A user-scope enable causes the hook to load in every project, bypassing scope-based gating.

### Invoking the skill manually

The review skill can also be invoked directly:

```
/codex-design-review:review
```

## Tests

```bash
bats tests/
```

## Out of scope (YAGNI)

Review of implementation/test code, multiple reviewers, multi-model support, CI integration, per-project customization of round count or review focus.
