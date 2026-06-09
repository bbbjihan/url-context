#!/usr/bin/env bash
# url-context — UserPromptSubmit hook (plugin engine)
#
# Walks the project's .claude/url-context/*.md entries and tests each entry's
# frontmatter `match` (a regex) against the user prompt. On a match, prints that
# entry's body to stdout so it is injected into the current turn's context.
#
# - If no entry matches, prints nothing and exits cleanly (normal behavior).
# - The engine lives in the plugin; registered data lives per-project in
#   .claude/url-context/.
# - bash 3.2 (macOS default) compatible; requires jq.

set -uo pipefail

DATA_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/url-context"
[ -d "$DATA_DIR" ] || exit 0

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty')"
[ -z "$prompt" ] && exit 0

emitted=0
for f in "$DATA_DIR"/*.md; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in README.md) continue ;; esac

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
    id="$(basename "$f" .md)"
    printf '<url-context id="%s" src=".claude/url-context/%s.md">\n' "$id" "$id"
    cat "$f"
    printf '\n</url-context>\n\n'
  fi
done

exit 0
