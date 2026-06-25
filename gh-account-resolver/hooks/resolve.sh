#!/bin/bash
# .claude/hooks/gh-account-resolver.sh
#
# PreToolUse hook for the Bash tool. Auto-selects the correct logged-in `gh`
# account PER COMMAND so concurrent Claude sessions don't fight over the
# globally-active gh account (`gh auth switch` writes shared state in
# ~/.config/gh/hosts.yml, which drifts between parallel sessions and causes
# "404 / Repository not found" when the wrong account is active).
#
# Mechanism: when a Bash command invokes `gh` against a repo whose OWNER maps
# to a non-default account (per .claude/gh-account-map), rewrite the command to
#   GH_TOKEN="$(gh auth token --user <account> 2>/dev/null)" <original command>
# The literal token NEVER appears in the rewritten string — it is pulled live
# from the keyring at execution time. The inner `gh auth token --user X` reads
# the default keyring/config and is unaffected by the not-yet-set outer GH_TOKEN.
#
# ZERO footprint outside the session: no ~/.zshrc, ~/.config, PATH, or global
# gh-state changes. Everything lives in this repo's .claude/.
#
# FAIL OPEN, ALWAYS: any error / unparseable input / missing gh / unsupported
# field → emit nothing and exit 0 so the original command runs unchanged. The
# hook may only *correct* a command, never break it.
#
# Output (only when a rewrite applies) — documented PreToolUse JSON:
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"<rewritten>"}}}
#
# See projects/gh-account-resolver/README.md for the full design + test matrix.

# Deliberately NOT `set -e`: a non-zero from any probe must fall through to the
# no-op exit, never abort mid-script and risk a partial/garbled emit.
set -u

# --- 1. Read tool input -----------------------------------------------------
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ "$tool_name" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# --- 2. Only act on gh commands ---------------------------------------------
# Match `gh` as a command head: at string start, or after a separator
# (; && || | & ( ), or after a `cd ... &&`. Not as a substring of another word.
echo "$cmd" | grep -qE '(^|[[:space:];&|()]+)gh[[:space:]]' || exit 0

# --- 3. Don't double-wrap ---------------------------------------------------
# If the command already pins a token/config or is otherwise pre-wrapped, no-op.
case "$cmd" in
  *GH_TOKEN=*|*GH_CONFIG_DIR=*|*GITHUB_TOKEN=*) exit 0 ;;
esac

# --- 4. Resolve the target repo owner ---------------------------------------
owner=""

# 4a. Explicit --repo OWNER/REPO or -R OWNER/REPO flag (supports = form too).
#     Take the first occurrence; strip any surrounding quotes.
repo_flag=$(printf '%s' "$cmd" | grep -oE '(--repo|-R)[[:space:]=]+[^[:space:]"'\''&|;()]+' | head -1) || true
if [ -n "${repo_flag:-}" ]; then
  repo_val=$(printf '%s' "$repo_flag" | sed -E 's/^(--repo|-R)[[:space:]=]+//')
  case "$repo_val" in
    */*) owner="${repo_val%%/*}" ;;
  esac
fi

# 4b. Else derive owner from origin remote of the command's working dir.
if [ -z "$owner" ]; then
  # Prefer an explicit leading `cd <dir>` in the command; else the agent's pwd.
  target=$(printf '%s' "$cmd" | grep -oE 'cd[[:space:]]+[^[:space:]&|;()]+' | head -1 | awk '{print $2}') || true
  if [ -n "${target:-}" ]; then
    workdir="${target/#\~/$HOME}"
  else
    workdir=$(pwd 2>/dev/null) || workdir=""
  fi
  [ -n "$workdir" ] || exit 0

  remote=$(git -C "$workdir" remote get-url origin 2>/dev/null) || true
  if [ -n "${remote:-}" ]; then
    # Normalise both SSH and HTTPS forms (incl. SSH host aliases like
    # github-work) down to OWNER. Examples:
    #   git@github.com:idellabv/repo.git           -> idellabv
    #   git@github-work:idellabv/repo.git          -> idellabv
    #   ssh://git@github.com/idellabv/repo.git     -> idellabv
    #   https://github.com/idellabv/repo.git       -> idellabv
    #   https://x@github.com/idellabv/repo.git     -> idellabv
    path_part=""
    case "$remote" in
      *://*)
        # URL form: strip scheme, then host (+ optional userinfo), keep path.
        path_part=$(printf '%s' "$remote" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#^[^/]*/##')
        ;;
      *:*)
        # scp-like SSH form host:owner/repo — take everything after the colon.
        path_part="${remote#*:}"
        ;;
      *)
        path_part="$remote"
        ;;
    esac
    path_part="${path_part#/}"
    case "$path_part" in
      */*) owner="${path_part%%/*}" ;;
    esac
  fi
fi

# Neither flag nor remote yielded an owner -> fall through to default account.
[ -n "$owner" ] || exit 0

# --- 5. Look the owner up in the repo-resident map --------------------------
# Locate the map relative to the workspace root (walk up from this script).
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd) || exit 0
map_file="$script_dir/../gh-account-map"
[ -r "$map_file" ] || exit 0

# Lowercase the owner for case-insensitive match.
owner_lc=$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')

default_account=""
account=""
while IFS= read -r line || [ -n "$line" ]; do
  # Strip comments and surrounding whitespace.
  line="${line%%#*}"
  case "$line" in
    *=*) : ;;
    *) continue ;;
  esac
  key=$(printf '%s' "${line%%=*}" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  val=$(printf '%s' "${line#*=}" | tr -d '[:space:]')
  [ -n "$key" ] || continue
  [ -n "$val" ] || continue
  if [ "$key" = "default" ]; then
    default_account="$val"
  elif [ "$key" = "$owner_lc" ]; then
    account="$val"
  fi
done < "$map_file"

# Owner not mapped, or maps to the default account -> no rewrite needed.
[ -n "$account" ] || exit 0
[ "$account" != "$default_account" ] || exit 0

# --- 6. Rewrite the command -------------------------------------------------
# Prefix a live-from-keyring token substitution. The literal token never
# appears here; it is resolved at execution time.
rewritten="GH_TOKEN=\"\$(gh auth token --user ${account} 2>/dev/null)\" ${cmd}"

# --- 7. Emit the documented PreToolUse updatedInput JSON --------------------
jq -nc --arg c "$rewritten" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:{command:$c}}}' \
  2>/dev/null || exit 0

exit 0
