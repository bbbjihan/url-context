# CLAUDE.md — url-context

Guidance for Claude (and contributors) working in this repository. This captures the
**high-context decisions** behind the project — the "why" that isn't obvious from the code or the
README. Read this before changing anything.

## What this is

A Claude Code **plugin** that auto-injects pre-registered per-URL metadata into the conversation
whenever a matching URL appears in a prompt. The repo is simultaneously the plugin and a
single-plugin marketplace.

## Architecture — three decoupled parts

- **Engine** — `scripts/url-context.sh`, a `UserPromptSubmit` hook registered in `hooks/hooks.json`.
  Reads the prompt, tests each data entry's `match` regex, and prints matching entries to stdout
  so they are injected into that turn's context.
- **Data** — `.claude/url-context/<id>.md`. **NOT in this repo.** It lives **per-project** in the
  user's project at `$CLAUDE_PROJECT_DIR/.claude/url-context/`. The engine is shared; the data is
  per-project. The `examples/url-context/` files here are samples only.
- **Management** — `skills/url-context/SKILL.md`, the `/url-context` skill that CRUDs data entries
  (add / list / show / edit / remove).

The three never reach into each other: the skill only writes `.md` files; the hook only reads the
directory. **Preserve this separation.**

## Non-obvious design decisions (the "why")

- **URL-agnostic; Figma is just one case.** The framing is deliberately general-first. The engine
  knows nothing about Figma — Figma URLs only get a richer auto-draft *source* (the Figma MCP) in
  the skill's `add` flow. Keep docs/examples general-first: `example-doc.md` is the primary example,
  `example-figma.md` is secondary. **Do not re-center the project on Figma.**
- **Matching is by frontmatter `match` (regex), not filename.** An earlier prototype keyed entries
  by filename = Figma fileKey; that doesn't generalize to arbitrary URLs, so it was replaced with a
  per-entry `match` regex.
- **`match` must be a single-quoted YAML scalar** (e.g. `match: 'figma\.com/...'`) so regex
  backslashes survive YAML parsing. The hook strips surrounding single/double quotes.
- **Cache-safety.** Installed plugins are copied to `~/.claude/plugins/cache`; packaged relative
  paths pointing *outside* the plugin break. This hook only uses `${CLAUDE_PLUGIN_ROOT}` (its own
  script) and `${CLAUDE_PROJECT_DIR}` (the data dir) — both resolved at runtime — so it survives the
  cache copy. **Never make the hook reference repo-relative data paths.**
- **bash 3.2 (macOS default) compatibility.** No `mapfile`/`readarray`. A `grep` no-match must not
  kill the script (use `set -uo pipefail`, not `-e`; guard with `2>/dev/null`). Quote-stripping is
  done in bash, not awk, to avoid quoting hell.
- **`jq` is a hard dependency** — the hook parses the prompt JSON from stdin. Listed in README
  requirements.
- **`README.md` is excluded** from matching and skill operations (it is not a data entry).

## Versioning & releasing (explicit version policy)

- We use an **explicit `version`** in `.claude-plugin/plugin.json` (currently `0.1.0`). Users only
  receive an update when this field is bumped. (Omitting `version` would switch to commit-SHA =
  every commit counts as an update; we intentionally do **not** do that.)
- **To ship a behavior change:** bump `version` in **both** `.claude-plugin/plugin.json` and the
  plugin entry in `.claude-plugin/marketplace.json`, then commit + push. Users then run
  `/plugin marketplace update url-context-marketplace` followed by `/reload-plugins`.
- **Docs-only changes (like this file) do NOT need a version bump** — they don't affect installed
  plugin components. CLAUDE.md is not a plugin component; installers receive cached components, not
  the repo tree.
- Auto-update is **OFF by default** for third-party marketplaces, so updates are pull-based unless
  the user enables it.

## Distribution

- Install: `/plugin marketplace add <owner>/url-context` →
  `/plugin install url-context@url-context-marketplace`.

## Development workflow

- Live-test without installing: `claude --plugin-dir <repo>`, then `/reload-plugins` after edits.
  This bypasses the cache/version logic, so it's the fastest dev loop.
- Test the hook directly: set `CLAUDE_PROJECT_DIR` to a temp dir containing `.claude/url-context/*.md`,
  then pipe a fake hook JSON into the script:
  `printf '%s' '{"prompt":"... https://..."}' | ./scripts/url-context.sh`

## Known follow-ups (not yet done)

- **Skill namespace is awkward:** once installed, the skill is invoked as `/url-context:url-context`.
  Consider renaming the skill folder (e.g. `skills/manage/` → `/url-context:manage`). Not yet changed.
