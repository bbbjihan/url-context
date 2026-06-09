---
name: url-context
description: Manages registration of per-URL/pattern metadata. Registered entries are auto-injected into context by the UserPromptSubmit hook whenever a matching URL appears in the prompt. URL-agnostic — works for internal wikis, design-system or spec docs, API domains, git repos, and Figma files alike. Use when the user says "/url-context", "register/list/remove/edit this URL context", "save the context for this doc/page/figma", etc. Subcommands: add / list / show / edit / remove.
---

# url-context — manage per-URL metadata

Manages `<URL pattern>:<context info>` relationships as `<id>.md` entries that the plugin's
UserPromptSubmit hook (`scripts/url-context.sh`) auto-injects when a matching URL appears in a prompt.

## Storage scopes (user + project, merged)

Entries live in one of two stores; the hook reads **both** and merges them:

| Scope | Path | Use for |
| :---- | :--- | :------ |
| **user** (default) | `~/.claude/url-context/<id>.md` | shared across ALL your projects/sessions |
| **project** | `$CLAUDE_PROJECT_DIR/.claude/url-context/<id>.md` | this project only; team-shareable by committing to the repo |

- **Default scope for new entries is `user`.** Use project scope when the entry is specific to one
  project or should be shared with the team via the repo.
- **Precedence**: if the same `id` exists in both, the **project** entry wins (overrides user).

## Data model

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
- `id` is both the filename and the identifier (and the precedence key across scopes). Use a safe
  kebab-case slug.
- Record `registered` as today's date in absolute form (from the system context's currentDate).
- `README.md` is not data; exclude it from list/operations.

Interpret the first token of args as the subcommand. If the first token is a URL (not a known
subcommand), treat it as `add <url>`. If args is empty, show usage and run `list`.

---

## add `<url>` [note]

Register a new URL/pattern. **Auto-draft (B) first, fall back to manual (A)** on failure.

1. **Decide scope.** Default to **user** (`~/.claude/url-context/`). Choose **project**
   (`$CLAUDE_PROJECT_DIR/.claude/url-context/`) only if the entry is project-specific or meant to be
   team-shared via the repo. If ambiguous, confirm with the user.
2. **Analyze URL & decide match** (default path — any URL):
   - Confirm the match scope with the user: **exact URL** / **path prefix** / **whole domain**.
   - Default to "exact URL (excluding query string)". Escape regex metacharacters.
   - *Figma special case*: for a Figma URL, extract the `fileKey` (and `node-id` if present) and
     scope `match` to the fileKey path, e.g. `figma\.com/(design|file|board)/<fileKey>`.
3. **Duplicate check**: if an entry with the same `id` or `match` exists in either scope, say so
   (note which scope) and confirm overwrite vs `edit`.
4. **B — auto-draft** (branches by source):
   - General web URL → use **WebFetch** to read the page and draft a "what info this page holds"
     summary. `source: webfetch`.
   - Figma URL → additionally use `mcp__claude_ai_Figma__get_metadata` (and `get_screenshot` if
     needed) to read the page/node structure and draft a "what's where" body. `source: figma-mcp`.
5. **A — fallback**: if auto-fetch is unavailable (no permission / access fails / tool not
   connected), create a blank template and fill it from the user's input (transcribe if dictated).
   `source: manual`.
6. Write `<id>.md` into the chosen scope's directory (create the directory if missing).
7. Summarize the result: id, **scope**, name, match, source (B/A), key body points. For auto-drafts,
   add a "draft — please review and correct" note.

> Auto-drafts can be inaccurate; always recommend human review.

## list

List entries from **both** scopes (excluding README). Print a table of
`scope` / `name` / `id` / `match` / `source` / `registered` plus a one-line body summary. If an `id`
exists in both scopes, mark that the project entry overrides the user one.

## show `<id|url|name>`

Show the full contents of an entry, searching both scopes. If given a url/name, resolve it to the
matching entry. If the same id exists in both scopes, show the effective (project) one and note the
shadowed user entry. If not found, suggest close candidates.

## edit `<id|url|name>` [instruction]

Edit an entry (search both scopes; if in both, edit the effective project one unless told otherwise).
If an instruction is included, apply it; otherwise show current contents and ask. When changing
`match`, verify the regex is valid and not overly broad (over-matching).

## remove `<id|url|name>`

Delete an entry `.md`. **Before deleting, show the target id/scope/name/match and ask for
confirmation**, then delete. If the id exists in both scopes, confirm which scope to remove.

---

## Notes

- The engine (hook), data (.md), and management (this skill) are decoupled. This skill only CRUDs
  the `.md` files; injection is handled entirely by the hook reading the two directories.
- If `match` is too broad (e.g. a whole domain), unrelated prompts may trigger injection, so keep
  it narrow by default.
- If one prompt matches multiple entries' `match`, all of them are injected (deduped by id, project
  winning over user).
