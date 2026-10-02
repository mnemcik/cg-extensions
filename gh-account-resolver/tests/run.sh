#!/bin/bash
# Test suite for hooks/resolve.sh, run against a fake `gh`. Never calls the
# real gh.
#
#   tests/run.sh            run every case under bash and (if installed) zsh
#   tests/run.sh bash       run under the named shells only
#
# The fake gh answers `auth token --user X` with `tok-X`, and otherwise prints
# `acct=<X>` (from GH_TOKEN) or `acct=default`, so each case can assert which
# account a call was routed to without any real credential.

set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../hooks/resolve.sh"

shells=("$@")
if [ ${#shells[@]} -eq 0 ]; then
  shells=(bash)
  command -v zsh >/dev/null 2>&1 && shells+=(zsh)
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/ghr-test.XXXXXX")
trap 'rm -rf "$T"' EXIT

# ---------------------------------------------------------------- fixtures
mkdir -p "$T/realbin"
cat >"$T/realbin/gh" <<'EOF'
#!/bin/bash
if [ "${1:-} ${2:-}" = "auth token" ]; then
  [ "${4:-}" = "broken" ] && exit 1
  printf 'tok-%s\n' "${4:-}"
  exit 0
fi
if [ -n "${GH_TOKEN:-}" ]; then acct="${GH_TOKEN#tok-}"; else acct=default; fi
case "${1:-}" in
  stdin) IFS= read -r l; echo "acct=$acct stdin=$l" ;;
  exit) echo "acct=$acct"; exit "${2:-0}" ;;
  nest) if [ "${2:-0}" -gt 0 ]; then gh nest $((${2} - 1)); else echo "acct=$acct"; fi ;;
  *) echo "acct=$acct" ;;
esac
EOF
chmod +x "$T/realbin/gh"

make_project() {   # make_project DIR
  mkdir -p "$1/.claude/hooks"
  cp "$src" "$1/.claude/hooks/gh-account-resolver-resolve.sh"
  chmod +x "$1/.claude/hooks/gh-account-resolver-resolve.sh"
  printf '%s\n' \
    '# owner = account' \
    'default = mine' \
    'work-org = work   # the work account' \
    'Mixed-Case = work' \
    'mine = mine' >"$1/.claude/gh-account-map"
  printf 'crlf-org = work\r\n' >>"$1/.claude/gh-account-map"
  printf 'nonl-org = work' >>"$1/.claude/gh-account-map"
}

install() {   # install PROJECT ENVFILE
  echo '{"hook_event_name":"SessionStart","source":"startup"}' |
    CLAUDE_ENV_FILE="$2" CLAUDE_PROJECT_DIR="$1" "$1/.claude/hooks/gh-account-resolver-resolve.sh"
}

P="$T/proj"
make_project "$P"
install "$P" "$T/env"

mkrepo() {   # mkrepo DIR [remote url]...
  mkdir -p "$1"
  git -C "$1" init -q
  local d="$1"; shift
  while [ $# -gt 1 ]; do git -C "$d" remote add "$1" "$2"; shift 2; done
}
mkrepo "$T/r/work" origin git@github.com:work-org/a.git
mkrepo "$T/r/pers" origin https://github.com/mine/b.git
mkrepo "$T/r/workhttps" origin https://github.com/work-org/e.git
mkrepo "$T/r/resolved" origin https://github.com/mine/f.git
git -C "$T/r/resolved" config remote.origin.gh-resolved work-org/f
mkrepo "$T/r/fork" origin https://github.com/mine/c.git upstream ssh://git@github-work/work-org/c.git
mkrepo "$T/r/alias" origin git@github-work:work-org/d.git
mkrepo "$T/r/none"
mkdir -p "$T/r/plain" "$T/r/glob"
: >"$T/r/glob/org:work-org"   # a glob-expanded `*` would read as a qualifier

BASEPATH="$T/realbin:/usr/bin:/bin"

# ---------------------------------------------------------------- runner
pass=0; fail=0
SH=""

# run DIR CMD: run CMD in a fresh $SH that sourced the env file, from DIR.
run() {
  env -i HOME="$HOME" PATH="$BASEPATH" TMPDIR="${TMPDIR:-/tmp}" \
    "$SH" -c ". '$T/env'; cd '$1' && $2" 2>"$T/stderr"
}

check() {   # check NAME DIR EXPECTED CMD
  local out
  out=$(run "$2" "$4" | tr '\n' ' ')
  out="${out% }"
  if [ "$out" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL [%s] %s\n  cmd:      %s\n  expected: %s\n  got:      %s\n' "$SH" "$1" "$4" "$3" "$out"
    sed 's/^/  stderr:   /' "$T/stderr"
  fi
}

ok() {   # ok NAME CONDITION...
  if "${@:2}"; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL [%s] %s\n' "$SH" "$1"; fi
}

W="$T/r/work"; M="$T/r/pers"

for SH in "${shells[@]}"; do
  # --- the four shapes from issue #6, plus mixed owners and child processes
  check "chain after cd"        "$T/r/plain" "acct=work acct=work" "cd '$W' && gh pr view 1; gh pr view 2"
  check "second command"        "$M" "acct=work acct=work"   "gh pr view 1 -R work-org/a; gh pr view 2 -R work-org/b"
  check "positional clone"      "$M" "acct=work"             "D=\$(mktemp -d); cd \$D; gh repo clone work-org/b ."
  check "loop over owners"      "$M" "acct=default acct=work" "for o in mine work-org; do gh pr view 2 -R \$o/b; done"
  check "mixed-owner chain"     "$W" "acct=work acct=default" "gh pr list; gh pr list -R mine/b"
  check "xargs"                 "$M" "acct=work"             "echo work-org/a | xargs gh repo view"
  check "bash -c"               "$M" "acct=work"             "bash -c 'gh pr list -R work-org/a'"
  check "subshell and \$()"     "$M" "acct=work acct=work"   "( gh pr list -R work-org/a ); echo \$(gh pr list -R work-org/a)"

  # --- owner resolution
  check "-R"                    "$M" "acct=work"    "gh pr list -R work-org/a"
  check "--repo"                "$M" "acct=work"    "gh pr list --repo work-org/a"
  check "--repo="               "$M" "acct=work"    "gh pr list --repo=work-org/a"
  check "-Rx/y"                 "$M" "acct=work"    "gh pr list -Rwork-org/a"
  check "HOST/OWNER/REPO"       "$M" "acct=work"    "gh pr list -R github.com/work-org/a"
  check "owner case-insensitive" "$M" "acct=work"   "gh pr list -R mixed-case/a"
  check "-R mine from work cwd" "$W" "acct=default" "gh pr list -R mine/b"
  check "GH_REPO"               "$M" "acct=work"    "GH_REPO=work-org/a gh pr list"
  check "repo view positional"  "$M" "acct=work"    "gh repo view work-org/a --web"
  check "repo list OWNER"       "$M" "acct=work"    "gh repo list work-org"
  check "repo clone URL"        "$M" "acct=work"    "gh repo clone https://github.com/work-org/a"
  check "pr URL argument"       "$M" "acct=work"    "gh pr view https://github.com/work-org/a/pull/1"
  check "api repos/"            "$M" "acct=work"    "gh api repos/work-org/a/pulls"
  check "api /orgs/"            "$M" "acct=work"    "gh api /orgs/work-org/members"
  check "api users/"            "$M" "acct=work"    "gh api users/work-org"
  check "api full URL"          "$M" "acct=work"    "gh api https://api.github.com/repos/work-org/a"
  check "api --method= first"   "$M" "acct=work"    "gh api --method=PATCH repos/work-org/a"
  check "api with flags first"  "$M" "acct=work"    "gh api -X POST -H 'Accept: x' repos/work-org/a/issues -f title=t"
  check "api mine from work"    "$W" "acct=default" "gh api repos/mine/b/pulls/1/comments -f body=x"
  check "api {owner} in work"   "$W" "acct=work"    "gh api 'repos/{owner}/{repo}/pulls'"
  check "api {owner} in pers"   "$M" "acct=default" "gh api 'repos/{owner}/{repo}/pulls'"
  check "api repo: qualifier"   "$M" "acct=work"    "gh api search/code -f 'q=foo repo:work-org/a'"
  check "api org: in -f q="     "$M" "acct=work"    "gh api search/issues -f q=org:work-org"
  check "search qualifier"      "$M" "acct=work"    "gh search issues 'is:open org:work-org'"
  check "search --owner"        "$M" "acct=work"    "gh search repos --owner work-org"
  check "search --owner="       "$M" "acct=work"    "gh search repos --owner=work-org"
  check "project --owner"       "$M" "acct=work"    "gh project list --owner work-org"
  check "secret --org"          "$M" "acct=work"    "gh secret list --org work-org"
  check "cwd ssh remote"        "$W" "acct=work"    "gh pr list"
  check "cwd host alias"        "$T/r/alias" "acct=work" "gh pr list"
  check "cwd https remote"      "$M" "acct=default" "gh pr list"
  check "cwd https remote, work" "$T/r/workhttps" "acct=work" "gh pr list"
  check "gh-resolved OWNER/REPO" "$T/r/resolved" "acct=work" "gh pr list"
  check "fork: upstream wins"   "$T/r/fork" "acct=work" "gh pr list"
  check "no remote"             "$T/r/none" "acct=default" "gh pr list"
  check "not a repo"            "$T/r/plain" "acct=default" "gh pr list"
  check "CRLF map line"         "$M" "acct=work"    "gh pr list -R crlf-org/a"
  check "last line, no newline" "$M" "acct=work"    "gh pr list -R nonl-org/a"
  check "unmapped owner"        "$W" "acct=default" "gh pr list -R stranger/x"

  # --- slashes that are not repos stay on the cwd account
  check "label with slash"      "$W" "acct=work"    "gh pr edit 1 --add-label kind/bug"
  check "branch with slash"     "$W" "acct=work"    "gh pr checkout feature/x"
  check "release asset path"    "$W" "acct=work"    "gh release upload v1 dist/a.zip"
  check "body file path"        "$W" "acct=work"    "gh issue create --body-file docs/x.md -t t"
  check "base branch"           "$W" "acct=work"    "gh pr create --base release/1.0 -t t -b b"
  check "label slash, pers"     "$M" "acct=default" "gh pr edit 1 --add-label kind/bug"

  # --- URLs inside text are not owners (the wrong-identity write)
  check "URL in --body"         "$M" "acct=default" "gh issue comment 5 --body https://github.com/work-org/x/issues/1"
  check "URL in -b"             "$M" "acct=default" "gh pr create -t t -b https://github.com/work-org/x"
  check "URL in -f"             "$M" "acct=default" "gh api repos/mine/b/issues -f body=https://github.com/work-org/x"

  # --- values of other flags are not owners either (code review of #7)
  check "URL in -c"             "$M" "acct=default" "gh pr close 5 -c https://github.com/work-org/x/pull/3"
  check "URL in --subject"      "$M" "acct=default" "gh pr merge 5 --squash --subject https://github.com/work-org/x/issues/1"
  check "URL in --homepage"     "$M" "acct=default" "gh repo edit --homepage https://github.com/work-org/site"
  check "create, homepage URL"  "$M" "acct=default" "gh repo create --homepage https://github.com/work-org/site mine/new"
  check "flag value before repo" "$W" "acct=default" "gh repo edit -d 'new description' mine/b"
  check "topic before repo"     "$W" "acct=default" "gh repo edit --add-topic foo mine/b"
  check "branch before repo"    "$W" "acct=default" "gh repo sync --branch main mine/b"
  check "create, desc first"    "$M" "acct=work"    "gh repo create -d 'a description' work-org/new"
  check "create, gitignore first" "$M" "acct=work"  "gh repo create --gitignore Node work-org/new"
  check "view, --json first"    "$M" "acct=work"    "gh repo view --json name work-org/a"
  check "clone, -u first"       "$M" "acct=work"    "gh repo clone -u up work-org/a"
  check "fork --org"            "$M" "acct=work"    "gh repo fork mine/b --org work-org"
  check "api body qualifier"    "$M" "acct=default" "gh api 'repos/{owner}/{repo}/issues/1/comments' -f body='moved to org:work-org'"
  check "api header qualifier"  "$M" "acct=default" "gh api user -H 'X: owner:work-org'"
  check "api ?q= qualifier"     "$M" "acct=work"    "gh api 'search/issues?q=is%3Aopen+org%3Awork-org'"
  check "graphql query text"    "$M" "acct=default" "gh api graphql -f query='# see org:work-org
{ viewer { login } }'"
  check "search '*' no glob"    "$T/r/glob" "acct=default" "gh search repos '*'"

  # --- user-scoped commands use the default account
  check "gist create"           "$W" "acct=default" "gh gist create f.txt"
  check "repo list, no owner"   "$W" "acct=default" "gh repo list"
  check "repo create --source"  "$W" "acct=default" "gh repo create --source=. --private"

  # --- gh calling gh (aliases, extensions) is not a loop
  check "nested gh calls"       "$W" "acct=work"    "gh nest 4"

  # --- bare names mean the logged-in user
  check "repo create bare"      "$W" "acct=default" "gh repo create newthing --private"
  check "repo clone bare"       "$W" "acct=default" "gh repo clone dotfiles"
  check "repo fork, no arg"     "$W" "acct=work"    "gh repo fork"

  # --- pass-through
  check "GH_TOKEN pin"          "$W" "acct=pinned"  "GH_TOKEN=tok-pinned gh pr list"
  check "GITHUB_TOKEN pin"      "$W" "acct=default" "GITHUB_TOKEN=x gh pr list"
  check "auth passes through"   "$W" "acct=default" "gh auth status"
  check "config passes through" "$W" "acct=default" "gh config get editor"
  check "--version"             "$W" "acct=default" "gh --version"
  check "bare gh"               "$W" "acct=default" "gh"

  # --- exit codes, stdin, caller shell options
  check "exit code"             "$W" "acct=work 3"  "gh exit 3; echo \$?"
  check "stdin passes through"  "$W" "acct=work stdin=hi" "echo hi | gh stdin"
  check "set -euo pipefail"     "$T/r/plain" "acct=default after" "set -euo pipefail; gh pr list; echo after"
  check "set -e, no remote"     "$T/r/none" "acct=default after" "set -e; gh pr list; echo after"
  check "set -x"                "$M" "acct=work"    "set -x; gh pr list -R work-org/a"
  ok "set -x leaks no token" eval '! grep -q "tok-work" "$T/stderr"'
done

# SHELLOPTS only exists in bash.
SH=bash
check "SHELLOPTS xtrace"       "$M" "acct=work"    "set -x; export SHELLOPTS; gh pr list -R work-org/a"
ok "SHELLOPTS leaks no token" eval '! grep -q "tok-work" "$T/stderr"'

SH=bash

# --- fail-open paths (shell-independent)
mv "$P/.claude/gh-account-map" "$P/.claude/map.bak"
check "missing map"            "$W" "acct=default" "gh pr list"
printf 'this is = = not\n=\njunk\n' >"$P/.claude/gh-account-map"
check "malformed map"          "$W" "acct=default" "gh pr list"
mv "$P/.claude/map.bak" "$P/.claude/gh-account-map"
printf 'broken-org = broken\n' >>"$P/.claude/gh-account-map"
check "token fetch fails"      "$M" "acct=default" "gh pr list -R broken-org/a"

# Only where no system gh sits in /usr/bin or /bin (CI runners ship one there).
if [ ! -e /usr/bin/gh ] && [ ! -e /bin/gh ]; then
  out=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" bash -c ". '$T/env'; gh pr list" 2>&1; echo "rc=$?")
  ok "missing real gh: 127" eval 'case "$out" in *"cannot find the real gh"*rc=127) true ;; *) false ;; esac'
fi

# --- install role
env1="$T/env-idem"
for i in 1 2 3; do install "$P" "$env1"; done
ok "env line written once" [ "$(grep -c '# gh-account-resolver' "$env1")" -eq 1 ]
n=$(env -i PATH="$BASEPATH" bash -c ". '$env1'; . '$env1'; . '$env1'; . '$env1'; printf '%s' \"\$PATH\"" |
  tr ':' '\n' | grep -c 'gh-account-resolver/bin')
ok "PATH entry added once" [ "$n" -eq 1 ]
ok "bin/gh is a symlink" [ -L "$P/.claude/gh-account-resolver/bin/gh" ]
ok "bin dir ignores itself" [ "$(cat "$P/.claude/gh-account-resolver/bin/.gitignore")" = "*" ]

out=$(echo '{"hook_event_name":"PreToolUse"}' |
  env -u CLAUDE_ENV_FILE CLAUDE_PROJECT_DIR="$P" "$P/.claude/hooks/gh-account-resolver-resolve.sh"; echo "rc=$?")
ok "other hook event: silent no-op" [ "$out" = "rc=0" ]

# --- two resolver copies on PATH must not loop
P2="$T/proj2"
make_project "$P2"
install "$P2" "$T/env2"
check "two resolvers on PATH"  "$M" "acct=work" ". '$T/env2'; gh pr list -R work-org/a"

# --- two resolver copies outside the resolver bin dirs, each pointing at the
#     other first: only the identity guard stops them exec-ing each other.
P4="$T/proj4"; make_project "$P4"
mkdir -p "$T/u1" "$T/u2"
ln -s "$P2/.claude/hooks/gh-account-resolver-resolve.sh" "$T/u1/gh"
ln -s "$P4/.claude/hooks/gh-account-resolver-resolve.sh" "$T/u2/gh"
out=$(cd "$W" && env -i HOME="$HOME" PATH="$T/u1:$T/u2:$BASEPATH" \
  perl -e 'alarm 10; exec @ARGV' "$T/u1/gh" pr list -R work-org/a 2>&1)
ok "identity loop guard" [ "$out" = "acct=work" ]

# --- removal: a dangling symlink falls back to the real gh
P3="$T/proj3"
make_project "$P3"
install "$P3" "$T/env3"
rm "$P3/.claude/hooks/gh-account-resolver-resolve.sh"
out=$(env -i HOME="$HOME" PATH="$BASEPATH" bash -c ". '$T/env3'; cd '$W' && gh pr list" 2>&1)
ok "dangling symlink falls back" [ "$out" = "acct=default" ]

echo "passed: $pass  failed: $fail  (shells: ${shells[*]})"
[ "$fail" -eq 0 ]
