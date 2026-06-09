# url-context

A Claude Code plugin that **auto-injects pre-written metadata into context** whenever a
**registered URL or pattern** appears in your prompt.

You register, once, what a given URL *is* and where to find what inside it. From then on, any
prompt that mentions that URL silently gains that context — no re-explaining, no manual lookup.

The mechanism is URL-agnostic: anything addressable by a URL or matchable by a pattern can be
registered. For example:

- Internal wikis / runbooks — "the payments API doc: auth in §2, webhooks in §4"
- Design-system or spec documents
- API domains, git repositories, dashboards
- **Figma files** — "this file's Foundation page holds tokens, node 1-2 is the login flow"

Figma is simply one applicable case. It gets an extra convenience (auto-drafting from the Figma
MCP), but the engine itself knows nothing special about Figma — it just matches URLs and injects
the entry you wrote.

> Auto-injection runs via a `UserPromptSubmit` hook, so this ships as a **plugin, not a bare skill**.
> Installing the plugin wires up the hook and skill together.

## Layout

```
url-context/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # (exposes this repo as a marketplace too)
├── hooks/hooks.json         # registers the UserPromptSubmit hook
├── scripts/url-context.sh   # matching engine (tests frontmatter `match` regex)
└── skills/url-context/      # management commands (add/list/show/edit/remove)
```

Registered **data** lives not in the plugin but in one of two stores, which the hook reads and
merges:

- **user** (default): `~/.claude/url-context/<id>.md` — shared across all your projects/sessions
- **project**: `<project>/.claude/url-context/<id>.md` — this project only; team-shareable by
  committing to the repo

If the same `id` exists in both, the **project** entry takes precedence. (Engine is shared; data is
user- and/or project-scoped.)

## Install

Add a local path or git repo as a marketplace, then install.

```
/plugin marketplace add /path/to/url-context
/plugin install url-context@url-context-marketplace
```

When distributed via git:

```
/plugin marketplace add <git-owner>/<repo>
/plugin install url-context@url-context-marketplace
```

The hook activates from the next session after install. For local development, you can also load
it directly without a marketplace:

```
claude --plugin-dir /path/to/url-context
```

## Usage

```
/url-context add https://wiki.example.com/api/payments
/url-context add https://figma.com/design/ABC123/Design-System   # Figma is just one case
/url-context list
/url-context show payments-api-doc
/url-context edit payments-api-doc
/url-context remove payments-api-doc
```

On `add`, the metadata draft is sourced by URL type:
- **Any web URL** → read the page via WebFetch and draft "what info this page holds"
- **Figma URL** → additionally draft from structure via the Figma MCP (`get_metadata`)
- **No access** → fall back to a blank template for manual authoring

Once registered, just include that URL in a prompt and the hook auto-injects its metadata.

## Entry format

```markdown
---
id: payments-api-doc
match: 'wiki\.example\.com/api/payments'   # tested against the prompt with grep -iE
name: Payments API doc
url: https://wiki.example.com/api/payments
source: webfetch        # webfetch | figma-mcp | manual
registered: 2026-06-09
---

What this page covers:
- §2 Authentication: token issuance + rotation
- §4 Webhooks: event types and retry policy
- "Sandbox" section: test credentials and base URLs
```

- Write `match` as a **single-quoted YAML scalar** (preserves regex backslashes).
- Keep `match` narrow by default (an exact URL or specific path) to avoid over-matching.

## Requirements

- `jq` (the hook uses it to parse the prompt JSON)
- bash (compatible with macOS's default 3.2)
- Auto-draft: an environment where WebFetch (for any URL) or the Figma MCP (for Figma URLs) is
  available
