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

# No globbing: the loops below split unquoted words, and a `*` in a search
# query must not expand to the files in the current directory.
set -f

my_real=$(realpath_of "$self")

# Loop guard by identity, not depth. Every resolver copy that runs adds its
# own path to GH_ACCOUNT_RESOLVER_SEEN and skips every path already listed, so
# two copies can never exec each other in a circle. A legitimate nested call
# (a gh alias, extension or git hook that runs gh again) still works.
seen="${GH_ACCOUNT_RESOLVER_SEEN:-}"
export GH_ACCOUNT_RESOLVER_SEEN="$seen:$my_real"

# Find the real gh: the first `gh` on PATH that is not a resolver copy.
real_gh=""
oldifs=$IFS
IFS=:
for d in $PATH; do
  [ -n "$d" ] || continue
  case "$d" in */.claude/gh-account-resolver/bin|*/.claude/gh-account-resolver/bin/) continue ;; esac
  c="$d/gh"
  [ -f "$c" ] && [ -x "$c" ] || continue
  if [ -L "$c" ]; then r=$(realpath_of "$c"); else r="$c"; fi
  [ "$r" = "$my_real" ] && continue
  case ":$seen:" in *":$r:"*) continue ;; esac
  real_gh="$c"
  break
done
IFS=$oldifs

if [ -z "$real_gh" ]; then
  echo "gh-account-resolver: cannot find the real gh on PATH" >&2
  exit 127
fi

passthru() { exec "$real_gh" "$@"; }

# Explicit pins and commands that don't act on a repo pass straight through.
# (`GH_TOKEN=x gh auth status` would report only the injected token.) Gists
# always belong to the logged-in user.
[ -n "${GH_TOKEN:-}" ] && passthru "$@"
[ -n "${GITHUB_TOKEN:-}" ] && passthru "$@"
[ $# -eq 0 ] && passthru "$@"
case "$1" in
  auth|config|alias|extension|extensions|ext|help|version|completion|gist|--version|--help|-h)
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

# Flags known to take no value. Any other flag written as `--flag value` is
# assumed to take one, and that value is never read as a positional: flag
# values are free text, file paths, branches or labels (`--body <url>`,
# `--add-label kind/bug`), and reading them once routed a write to the wrong
# account. An unknown boolean flag only costs the next positional, which then
# falls back to the current directory.
is_bool_flag() {
  case "$1" in
    -w|--web|-y|--yes|--force|--confirm|-s|--squash|--merge|-r|--rebase|--admin|--auto|\
    --delete-branch|--draft|--fill|--fill-first|--fill-verbose|--public|--private|\
    --internal|--clone|--remote|--no-clone|--archived|--comments|--exit-status|\
    --watch|--required|--fail-fast|--undo|--include-all-branches|--disable-issues|\
    --disable-wiki|--push|--paginate|--slurp|-i|--include|--silent|--verbose|\
    --no-maintainer-edit|--dry-run|--editor|-e|--recover|--ignore-unknown)
      return 0 ;;
  esac
  return 1
}

# Split the arguments into positionals (subcommands included) and the values
# of -f/-F/--field/--raw-field.
pos=()
fields=()
skip=0
field=0
for a in "$@"; do
  if [ $skip -eq 1 ]; then
    skip=0
    [ $field -eq 1 ] && fields+=("$a")
    field=0
    continue
  fi
  case "$a" in
    --) break ;;
    --field=*|--raw-field=*) fields+=("${a#*=}") ;;
    -f?*|-F?*) fields+=("${a#-?}") ;;
    -f|-F|--field|--raw-field) skip=1; field=1 ;;
    --*=*) ;;
    -*) is_bool_flag "$a" || skip=1 ;;
    *) pos+=("$a") ;;
  esac
done

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

# repo:O/R, org:O, user:O, owner:O in a list of search words.
from_qualifier() {
  local t
  for t in $1; do
    case "$t" in
      repo:*/*) t="${t#repo:}"; printf '%s' "${t%%/*}"; return ;;
      org:?*|user:?*|owner:?*) printf '%s' "${t#*:}"; return ;;
    esac
  done
}

sub1="$1"
sub2="${pos[1]:-}"
owner=""

# 1. -R / --repo / --repo= / -Rx/y; --owner for search and project; --org / -o
#    for secret and variable; --org for repo fork (the fork's new owner).
prev=""
for a in "$@"; do
  [ "$a" = "--" ] && break
  case "$prev" in
    -R|--repo) owner=$(from_repo_val "$a"); break ;;
    --owner) case "$sub1" in search|project) owner="$a"; break ;; esac ;;
    --org|-o)
      case "$sub1 $sub2" in secret\ *|variable\ *|"repo fork") owner="$a"; break ;; esac ;;
  esac
  case "$a" in
    --repo=*) owner=$(from_repo_val "${a#--repo=}"); break ;;
    -R?*) owner=$(from_repo_val "${a#-R}"); break ;;
    --owner=*) case "$sub1" in search|project) owner="${a#--owner=}"; break ;; esac ;;
    --org=*)
      case "$sub1 $sub2" in secret\ *|variable\ *|"repo fork") owner="${a#--org=}"; break ;; esac ;;
  esac
  prev="$a"
done

# 2. GH_REPO
[ -z "$owner" ] && [ -n "${GH_REPO:-}" ] && owner=$(from_repo_val "$GH_REPO")

# 3. `gh repo` commands that take a repo: the first positional with a slash.
#    Without one, the target belongs to the logged-in user (a bare name for
#    clone/create/fork, no name for list/create), so the current directory
#    must not decide: use the default account. `repo list OWNER` names the
#    owner directly.
if [ -z "$owner" ] && [ "$sub1" = repo ]; then
  case "$sub2" in
    clone|view|fork|edit|delete|archive|unarchive|sync|set-default|create|list)
      first=""
      for a in "${pos[@]:2}"; do
        case "$a" in
          */*) owner=$(from_url "$a"); [ -n "$owner" ] || owner=$(from_repo_val "$a"); break ;;
          *) [ -n "$first" ] || first="$a" ;;
        esac
      done
      if [ -z "$owner" ]; then
        case "$sub2" in
          list) [ -n "$first" ] && owner="$first" || passthru "$@" ;;
          clone|create) passthru "$@" ;;
          fork) [ -n "$first" ] && passthru "$@" ;;
        esac
      fi ;;
  esac
fi

# 4. A github.com URL given as a positional argument.
if [ -z "$owner" ]; then
  for a in "${pos[@]}"; do
    owner=$(from_url "$a")
    [ -n "$owner" ] && break
  done
fi

# 5. gh api: the endpoint path, then a search query (`?q=` on the endpoint, or
#    a q=/query= field). Other field values (`-f body=...`) are free text and
#    never read.
if [ -z "$owner" ] && [ "$sub1" = api ]; then
  ep="${pos[1]:-}"
  [ -n "$ep" ] && owner=$(from_api_path "$ep")
  if [ -z "$owner" ]; then
    case "$ep" in
      *\?q=*|*\&q=*)
        q="${ep#*q=}"; q="${q%%&*}"
        q=$(printf '%s' "$q" | sed 's/%3[Aa]/:/g; s/%2[Ff]/\//g; s/+/ /g; s/%20/ /g')
        owner=$(from_qualifier "$q") ;;
    esac
  fi
  if [ -z "$owner" ]; then
    # A graphql query= field is GraphQL text, not a search query.
    [ "$ep" = graphql ] && fields=()
    for f in "${fields[@]}"; do
      case "$f" in
        q=*|query=*) owner=$(from_qualifier "${f#*=}"); [ -n "$owner" ] && break ;;
      esac
    done
  fi
fi

# 6. gh search: qualifiers in the query words.
if [ -z "$owner" ] && [ "$sub1" = search ]; then
  for a in "${pos[@]:2}"; do owner=$(from_qualifier "$a"); [ -n "$owner" ] && break; done
fi

# 7. The current directory's remote, preferring the one gh itself would use:
#    the gh-resolved base (or the OWNER/REPO it records), then upstream, then
#    origin.
if [ -z "$owner" ]; then
  resolved=$(git config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null | head -n 1)
  rname=""
  if [ -n "$resolved" ]; then
    rval="${resolved#* }"
    case "$rval" in
      */*) owner=$(from_repo_val "$rval") ;;
      base) rname="${resolved%% *}"; rname="${rname#remote.}"; rname="${rname%.gh-resolved}" ;;
    esac
  fi
fi
if [ -z "$owner" ]; then
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
