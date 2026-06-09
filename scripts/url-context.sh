#!/usr/bin/env bash
# url-context — UserPromptSubmit hook (plugin engine)
#
# Reads registered entries from BOTH stores, tests each entry's frontmatter
# `match` (a regex) against the prompt, and prints matching entries to stdout so
# they are injected into the current turn's context.
#
#   user-level:    ~/.claude/url-context/*.md
#                    shared across ALL projects/sessions
#   project-level: $CLAUDE_PROJECT_DIR/.claude/url-context/*.md
#                    this project only; can be team-shared by committing to the repo
#
# Project entries take precedence over user entries with the same id (filename):
# the project dir is scanned first, and a given id is emitted at most once.
#
# - If nothing matches, prints nothing and exits cleanly (normal behavior).
# - bash 3.2 (macOS default) compatible — no associative arrays; requires jq.

set -uo pipefail

USER_DIR="$HOME/.claude/url-context"
PROJ_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/url-context"

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty')"
[ -z "$prompt" ] && exit 0

emitted=0
seen=" "   # space-delimited ids already handled (project scanned first → wins)

# Project dir first so its entries take precedence over same-id user entries.
for dir in "$PROJ_DIR" "$USER_DIR"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in README.md) continue ;; esac
    id="${base%.md}"

    # Dedup by id; whichever dir is scanned first (project) wins.
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "

    # Extract the `match:` value from the frontmatter (first --- .. next ---)
    match="$(awk '
      NR==1 && $0=="---" { infm=1; next }
      infm && $0=="---"  { exit }
      infm && /^match:/  { sub(/^match:[[:space:]]*/,""); print; exit }
    ' "$f")"
    [ -z "$match" ] && continue

    # Strip surrounding quotes (single/double)
    case "$match" in
      \"*\") match="${match#\"}"; match="${match%\"}" ;;
      \'*\') match="${match#\'}"; match="${match%\'}" ;;
    esac
    [ -z "$match" ] && continue

    if printf '%s' "$prompt" | grep -qiE "$match" 2>/dev/null; then
      if [ "$emitted" -eq 0 ]; then
        printf '## Registered URL context\n\n'
        printf 'This prompt contains a pre-registered URL/pattern. Always consult the metadata below when working on it.\n\n'
        emitted=1
      fi
      scope="user"; [ "$dir" = "$PROJ_DIR" ] && scope="project"
      printf '<url-context id="%s" scope="%s">\n' "$id" "$scope"
      cat "$f"
      printf '\n</url-context>\n\n'
    fi
  done
done

exit 0
