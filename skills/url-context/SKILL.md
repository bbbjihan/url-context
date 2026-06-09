---
name: url-context
description: Manages registration of per-URL/pattern metadata. Registered entries are auto-injected into context by the UserPromptSubmit hook whenever a matching URL appears in the prompt. URL-agnostic — works for internal wikis, design-system or spec docs, API domains, git repos, and Figma files alike. Use when the user says "/url-context", "register/list/remove/edit this URL context", "save the context for this doc/page/figma", etc. Subcommands: add / list / show / edit / remove.
---

# url-context — manage per-URL metadata

Manages `<URL pattern>:<context info>` relationships as `.claude/url-context/<id>.md` entries.
Registered entries are auto-injected into context by the plugin's UserPromptSubmit hook
(`scripts/url-context.sh`), which detects URLs in the prompt.

The engine is URL-agnostic: it matches a registered pattern against the prompt and injects the
entry you wrote. Any URL works — internal wikis, spec/design docs, API domains, git repos. Figma
URLs are just one case that happens to get a richer auto-draft source (the Figma MCP).

## Data model

- **Storage**: `$CLAUDE_PROJECT_DIR/.claude/url-context/<id>.md` (per-project)
- **Entry format**:

```markdown
---
id: payments-api-doc
match: 'wiki\.example\.com/api/payments'   # regex tested against the prompt (grep -iE)
name: Payments API doc
url: https://wiki.example.com/api/payments
source: webfetch        # webfetch | figma-mcp | manual
registered: 2026-06-09
---

What this page covers:
- §2 Authentication: token issuance + rotation
- §4 Webhooks: event types and retry policy
...
```

Core rules:
- Matching is driven by the frontmatter **`match` (regex), not the filename**. The hook tests
  each entry's `match` against the prompt with `grep -iE`.
- Write `match` as a **single-quoted YAML scalar** to preserve regex backslashes,
  e.g. `match: 'wiki\.example\.com/api/payments'`.
- `id` is both the filename and the identifier. Use a safe kebab-case slug.
- Record `registered` as today's date in absolute form (from the system context's currentDate).
- `README.md` is not data; exclude it from list/operations.

Interpret the first token of args as the subcommand. If none, show usage and run `list`.

---

## add `<url>` [note]

Register a new URL/pattern. **Auto-draft (B) first, fall back to manual (A)** on failure.

1. **Analyze URL & decide match** (default path — any URL):
   - Confirm the match scope with the user: **exact URL** / **path prefix** / **whole domain**.
   - Default to "exact URL (excluding query string)". Escape regex metacharacters.
   - *Figma special case*: for a Figma URL, extract the `fileKey` (and `node-id` if present) and
     scope `match` to the fileKey path, e.g. `figma\.com/(design|file|board)/<fileKey>`.
2. **Duplicate check**: if an entry with the same `id` or `match` exists, say so and confirm
   overwrite vs `edit`.
3. **B — auto-draft** (branches by source):
   - General web URL → use **WebFetch** to read the page and draft a "what info this page holds"
     summary. `source: webfetch`.
   - Figma URL → additionally use `mcp__claude_ai_Figma__get_metadata` (and `get_screenshot` if
     needed) to read the page/node structure and draft a "what's where" body. `source: figma-mcp`.
4. **A — fallback**: if auto-fetch is unavailable (no permission / access fails / tool not
   connected), create a blank template and fill it from the user's input (transcribe if dictated).
   `source: manual`.
5. Write `.claude/url-context/<id>.md`.
6. Summarize the result: id, name, match, source (B/A), key body points. For auto-drafts, add a
   "draft — please review and correct" note.

> Auto-drafts can be inaccurate; always recommend human review.

## list

Read `.claude/url-context/*.md` (excluding README) and print a table of
`name` / `id` / `match` / `source` / `registered` plus a one-line body summary.

## show `<id|url|name>`

Show the full contents of an entry. If given a url/name, resolve it to the matching entry.
If not found, suggest close candidates.

## edit `<id|url|name>` [instruction]

Edit an entry. If an instruction is included, apply it; otherwise show current contents and ask.
When changing `match`, verify the regex is valid and not overly broad (over-matching).

## remove `<id|url|name>`

Delete an entry `.md`. **Before deleting, show the target id/name/match and ask for confirmation**,
then delete.

---

## Notes

- The engine (hook), data (.md), and management (this skill) are decoupled. This skill only CRUDs
  the `.md` files; injection is handled entirely by the hook reading the directory.
- If `match` is too broad (e.g. a whole domain), unrelated prompts may trigger injection, so keep
  it narrow by default.
- If one prompt matches multiple entries' `match`, all of them are injected.
