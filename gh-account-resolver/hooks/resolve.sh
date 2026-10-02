#!/bin/bash
# gh-account-resolver — per-call gh account routing for Claude Code sessions.
#
# `gh auth switch` writes shared state (~/.config/gh/hosts.yml), so parallel
# Claude sessions fight over the active account and `gh` against a repo the
# active account can't see fails with "Could not resolve to a Repository".
#
# One script, two roles, chosen by the name it is invoked as:
#
#   * As the SessionStart hook (installed as .claude/hooks/<ext>-resolve.sh):
#     create <project>/.claude/gh-account-resolver/bin/gh as a symlink to this
#     script, and append one guarded line to $CLAUDE_ENV_FILE that puts that
#     bin dir first on PATH. Claude Code applies that file to every Bash
#     command of the session, including subagents, background commands and
#     child processes (xargs, bash -c, scripts). Run under any other hook
#     event, it does nothing.
#
#   * As `gh` (through the symlink): work out the repo owner from the call's
#     real arguments, look it up in .claude/gh-account-map, and exec the real
#     gh, with GH_TOKEN from `gh auth token --user <account>` when the owner
#     maps to a non-default account. The token is never in argv or in any
#     command text; it lives only in the real gh process's environment.
#
# FAIL OPEN, ALWAYS: anything unexpected execs the real gh unchanged. No
# `set -e`, so a failed probe can never abort the caller's command.
#
# Portable to macOS /bin/bash 3.2: no associative arrays, no ${var,,}.

# Never trace this script, even when the caller exported xtrace via SHELLOPTS:
# the routed path handles a token.
set +x +v 2>/dev/null
set +e +u

self="$0"
case "$self" in */*) me="${self##*/}" ;; *) me="$self" ;; esac

# Resolve symlinks without `readlink -f` (not available on older macOS).
realpath_of() {
  local p="$1" l n=0 d
  while [ -L "$p" ] && [ $n -lt 20 ]; do
    l=$(readlink -- "$p") || break
    case "$l" in /*) p="$l" ;; *) p="${p%/*}/$l" ;; esac
    n=$((n + 1))
  done
  case "$p" in */*) d="${p%/*}" ;; *) d=. ;; esac
  d=$(cd -P -- "${d:-/}" 2>/dev/null && pwd) || return 1
  printf '%s/%s' "$d" "${p##*/}"
}

# Single-quote a string for safe inclusion in shell source.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# trim VAR VALUE: set VAR to VALUE without surrounding whitespace, no fork.
trim() {
  local _t="$2"
  _t="${_t#"${_t%%[![:space:]]*}"}"
  _t="${_t%"${_t##*[![:space:]]}"}"
  printf -v "$1" '%s' "$_t"
}

# ------------------------------------------------------------ install role
if [ "$me" != "gh" ]; then
  [ -t 0 ] || cat >/dev/null 2>&1      # drain the hook's JSON input
  # Only SessionStart provides CLAUDE_ENV_FILE. Under any other event (e.g. a
  # 0.1.0 PreToolUse registration left in an older worktree's settings), do
  # nothing and emit nothing.
  [ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0
  real_self=$(realpath_of "$self") || exit 0
  bin="$CLAUDE_PROJECT_DIR/.claude/gh-account-resolver/bin"
  mkdir -p "$bin" 2>/dev/null || exit 0
  [ -f "$bin/.gitignore" ] || printf '*\n' >"$bin/.gitignore" 2>/dev/null
  # Replace the link atomically: build it under a temp name, then rename.
  tmp="$bin/.gh.$$"
  ln -s "$real_self" "$tmp" 2>/dev/null && mv -f "$tmp" "$bin/gh" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  # Claude Code reuses the env file across resume and compact, so write the
  # line once (marker), and make the line itself a no-op when bin is already
  # on PATH.
  marker='# gh-account-resolver'
  if ! grep -qF "$marker" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    qb=$(sq "$bin")
    printf '%s\n' "case \":\$PATH:\" in *:$qb:*) ;; *) export PATH=$qb\":\$PATH\" ;; esac $marker" \
      >>"$CLAUDE_ENV_FILE" 2>/dev/null
  fi
  exit 0
fi

# ------------------------------------------------------------ route role

# Backstop against exec loops between resolver copies.
hops="${GH_ACCOUNT_RESOLVER_HOPS:-0}"
case "$hops" in *[!0-9]*|'') hops=0 ;; esac
export GH_ACCOUNT_RESOLVER_HOPS=$((hops + 1))

my_real=$(realpath_of "$self")

# Find the real gh: the first `gh` on PATH that is neither this script nor in
# any resolver bin dir (another workspace's copy on PATH would otherwise exec
# back here, forever).
real_gh=""
oldifs=$IFS
IFS=:
for d in $PATH; do
  [ -n "$d" ] || continue
  case "$d" in */.claude/gh-account-resolver/bin|*/.claude/gh-account-resolver/bin/) continue ;; esac
  c="$d/gh"
  [ -f "$c" ] && [ -x "$c" ] || continue
  if [ -L "$c" ]; then
    r=$(realpath_of "$c")
    [ "$r" = "$my_real" ] && continue
  fi
  real_gh="$c"
  break
done
IFS=$oldifs

if [ -z "$real_gh" ] || [ "$hops" -ge 3 ]; then
  echo "gh-account-resolver: cannot find the real gh on PATH" >&2
  exit 127
fi

passthru() { exec "$real_gh" "$@"; }

# Explicit pins and commands that don't act on a repo pass straight through.
# (`GH_TOKEN=x gh auth status` would report only the injected token.)
[ -n "${GH_TOKEN:-}" ] && passthru "$@"
[ -n "${GITHUB_TOKEN:-}" ] && passthru "$@"
[ $# -eq 0 ] && passthru "$@"
case "$1" in
  auth|config|alias|extension|extensions|ext|help|version|completion|--version|--help|-h)
    passthru "$@" ;;
esac

# The map is <project>/.claude/gh-account-map. Find it from where the symlink
# lives (<project>/.claude/gh-account-resolver/bin/gh), else from where this
# script lives (<project>/.claude/hooks/<name>.sh).
case "$self" in */*) linkdir="${self%/*}" ;; *) linkdir=. ;; esac
map=""
for cand in "$linkdir/../../gh-account-map" "${my_real%/*}/../gh-account-map"; do
  if [ -r "$cand" ]; then map="$cand"; break; fi
done
[ -n "$map" ] || passthru "$@"

# Flags whose value is free text, a file or a branch, never a repo. Their
# values are never mined for an owner: a URL inside --body once routed a
# comment to the wrong account.
is_text_flag() {
  case "$1" in
    -b|--body|-t|--title|-m|--message|-n|--notes|--notes-file|--comment|-q|--jq|\
    --template|-T|-F|--body-file|-f|--field|--raw-field|-H|--header|--input|\
    -l|--label|--add-label|--remove-label|-B|--base|--head|-a|--assignee|\
    --milestone)
      return 0 ;;
  esac
  return 1
}

# OWNER/REPO, HOST/OWNER/REPO or a URL -> OWNER
from_repo_val() {
  local v="$1" a
  v="${v#https://}"; v="${v#http://}"
  case "$v" in
    */*/*) a="${v#*/}"; printf '%s' "${a%%/*}" ;;
    */*) printf '%s' "${v%%/*}" ;;
  esac
}

# https://github.com/OWNER/... -> OWNER
from_url() {
  local v="$1"
  case "$v" in
    https://github.com/*/*|http://github.com/*/*|https://www.github.com/*/*)
      v="${v#*github.com/}"; printf '%s' "${v%%/*}" ;;
  esac
}

# repos/OWNER/..., orgs/OWNER, users/OWNER (optionally a full api.github.com
# URL) -> OWNER. {owner} placeholders mean "the current repo": no owner here.
from_api_path() {
  local v="$1"
  v="${v#https://api.github.com}"; v="${v#/}"
  case "$v" in
    repos/\{owner\}*|orgs/\{owner\}*|users/\{owner\}*) return ;;
    repos/*/*|orgs/?*|users/?*) v="${v#*/}"; v="${v%%/*}"; v="${v%%\?*}"; printf '%s' "$v" ;;
  esac
}

# repo:O/R, org:O, user:O, owner:O anywhere in a word list, including inside a
# key=value field such as `-f q=org:O`.
from_qualifier() {
  local t
  for t in $1; do
    case "$t" in [A-Za-z_]*=*) t="${t#*=}" ;; esac
    case "$t" in
      repo:*/*) t="${t#repo:}"; printf '%s' "${t%%/*}"; return ;;
      org:?*|user:?*|owner:?*) printf '%s' "${t#*:}"; return ;;
    esac
  done
}

sub1="$1"
sub2="${2:-}"
owner=""

# 1. -R / --repo / --repo= / -Rx/y; --owner for search and project; --org / -o
#    for secret and variable.
prev=""
for a in "$@"; do
  case "$prev" in
    -R|--repo) owner=$(from_repo_val "$a"); break ;;
    --owner) case "$sub1" in search|project) owner="$a"; break ;; esac ;;
    --org|-o) case "$sub1" in secret|variable) owner="$a"; break ;; esac ;;
  esac
  case "$a" in
    --repo=*) owner=$(from_repo_val "${a#--repo=}"); break ;;
    -R?*) owner=$(from_repo_val "${a#-R}"); break ;;
    --owner=*) case "$sub1" in search|project) owner="${a#--owner=}"; break ;; esac ;;
    --org=*) case "$sub1" in secret|variable) owner="${a#--org=}"; break ;; esac ;;
  esac
  prev="$a"
done

# 2. GH_REPO
[ -z "$owner" ] && [ -n "${GH_REPO:-}" ] && owner=$(from_repo_val "$GH_REPO")

# 3. A repo positional, only for `gh repo` commands that take one. A bare name
#    (no slash) for clone/create/fork means the logged-in user's repo, so the
#    current directory must not decide: use the default account. `repo list
#    OWNER` names the owner directly.
if [ -z "$owner" ] && [ "$sub1" = repo ]; then
  case "$sub2" in
    clone|view|fork|edit|delete|archive|unarchive|sync|set-default|create|list)
      n=0; prev=""
      for a in "$@"; do
        n=$((n + 1)); [ $n -le 2 ] && continue
        if is_text_flag "$prev"; then prev="$a"; continue; fi
        case "$a" in --) break ;; -*) prev="$a"; continue ;; esac
        case "$a" in
          */*) owner=$(from_url "$a"); [ -n "$owner" ] || owner=$(from_repo_val "$a") ;;
          *) case "$sub2" in
               list) owner="$a" ;;
               clone|create|fork) passthru "$@" ;;
             esac ;;
        esac
        break
      done ;;
  esac
fi

# 4. A github.com URL given as an argument (never as a text flag's value).
if [ -z "$owner" ]; then
  prev=""
  for a in "$@"; do
    if ! is_text_flag "$prev"; then
      owner=$(from_url "$a")
      [ -n "$owner" ] && break
    fi
    prev="$a"
  done
fi

# 5. gh api: the endpoint path, then qualifiers in any argument (search
#    queries are usually passed as -f q=...).
if [ -z "$owner" ] && [ "$sub1" = api ]; then
  ep=""; prev=""
  for a in "${@:2}"; do
    if [ -z "$ep" ] && ! is_text_flag "$prev"; then
      case "$prev" in
        -X|--method|-p|--preview|--hostname|--cache) ;;   # flags that take a value
        *) case "$a" in -*) ;; *) ep="$a" ;; esac ;;
      esac
    fi
    prev="$a"
  done
  [ -n "$ep" ] && owner=$(from_api_path "$ep")
  if [ -z "$owner" ]; then
    for a in "$@"; do owner=$(from_qualifier "$a"); [ -n "$owner" ] && break; done
  fi
fi

# 6. gh search: qualifiers in the query words.
if [ -z "$owner" ] && [ "$sub1" = search ]; then
  for a in "${@:2}"; do owner=$(from_qualifier "$a"); [ -n "$owner" ] && break; done
fi

# 7. The current directory's remote, preferring the one gh itself would use:
#    the gh-resolved base, then upstream, then origin.
if [ -z "$owner" ]; then
  rname=$(git config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null |
    awk '$2=="base"{sub(/^remote\./,"",$1); sub(/\.gh-resolved$/,"",$1); print $1; exit}')
  url=""
  for r in $rname upstream origin; do
    url=$(git remote get-url "$r" 2>/dev/null) && [ -n "$url" ] && break
    url=""
  done
  if [ -n "$url" ]; then
    case "$url" in
      *://*) p="${url#*://}"; p="${p#*/}" ;;   # scheme://host/OWNER/REPO
      *:*) p="${url#*:}" ;;                    # git@host:OWNER/REPO
      *) p="" ;;
    esac
    p="${p#/}"
    case "$p" in */*) owner="${p%%/*}" ;; esac
  fi
fi

[ -n "$owner" ] || passthru "$@"

# Map lookup: `owner = account` lines, `#` comments, CRLF tolerated, owner
# compared case-insensitively.
shopt -s nocasematch 2>/dev/null
default_acct=""
acct=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  line="${line%%#*}"
  case "$line" in *=*) ;; *) continue ;; esac
  trim k "${line%%=*}"
  trim v "${line#*=}"
  [ -n "$k" ] && [ -n "$v" ] || continue
  if [[ "$k" == "default" ]]; then
    default_acct="$v"
  elif [[ "$k" == "$owner" ]]; then
    acct="$v"
  fi
done <"$map"
shopt -u nocasematch 2>/dev/null

[ -n "$acct" ] || passthru "$@"
[ "$acct" != "$default_acct" ] || passthru "$@"

tok=$("$real_gh" auth token --user "$acct" 2>/dev/null </dev/null)
[ -n "$tok" ] || passthru "$@"
export GH_TOKEN="$tok"
unset tok
exec "$real_gh" "$@"
