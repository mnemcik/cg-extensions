# cg-extensions

First-party [Consigliere](https://github.com/mnemcik/consigliere) extensions,
co-located in one repo. Each extension lives in its own subdirectory with its own
`cg-extension.json` manifest, README, and CHANGELOG, and is versioned
independently.

## Extensions

| Extension | What it does |
|-----------|--------------|
| [`1password`](1password/) | Makes 1Password the authoritative credential store — `op://` referencing, just-in-time `op` retrieval, item-creation requests, 1Password SSH-agent git auth, and a `PostToolUse` hook that adds the 1Password remedy when git or ssh fails to authenticate. |
| [`spec-driven`](spec-driven/) | Spec-driven development workflow for greenfield software builds — PRD → layered specs → milestone implementation, gated to exclude brownfield/research/analysis/doc work. |
| [`voice`](voice/) | Drafts outbound messages (Slack, email, Jira, PR) in your own voice by loading a personal `VOICE.md` style guide; ships a skeleton, not anyone's content. |
| [`gmail-digest`](gmail-digest/) | Turns "check / digest X updates" into a structured digest of unread Gmail for a label, with per-target tracking; ships the trigger rule + workflow + a target template (requires a Gmail MCP). |
| [`gh-account-resolver`](gh-account-resolver/) | Per-command `gh` account routing — a `PreToolUse` hook picks the right logged-in `gh` account per Bash command (via `.claude/gh-account-map`) so parallel sessions don't fight over global `gh` auth state. Fails open; zero global footprint. |
| [`bundle-backup`](bundle-backup/) | Backs up the workspace as a `git bundle` to a folder (e.g. a synced company drive) after every commit, merge or rewrite — no git remote needed. Uses the `git-hooks` contribution point (cg 1.25+). |
| [`obsidian`](obsidian/) | Makes the workspace work as an Obsidian vault — seeded vault config, per-machine state gitignored, a Bases view of active projects, and a note on the link/tag/Bases gotchas. Uses the `gitignore` contribution point. |
| [`shopping`](shopping/) | One shared shopping list for the workspace — `cg shop` adds items from any project, groups open items by supplier so one order covers every project, and tracks needed → ordered → received. One file per item, so parallel sessions never conflict. |
| [`live-runs`](live-runs/) | Watch headless `claude -p` runs live — `cg live run` logs every agent step and the live output of every shell command, `cg live watch` shows it (as a tmux split next to the session when run inside tmux); same result JSON as `--output-format json`. |
| [`tmux`](tmux/) | Starts the workspace's AI session in its own session on cg's own tmux server (`tmux -L cg`) when you run `cg`, so it survives closing the terminal and tools can open panes next to it; your own tmux is left alone. Uses the `launcher` contribution point (cg 1.32+). |
| [`github-digest`](github-digest/) | Digests a watched GitHub repo's activity since the last digest straight from the GitHub API, so you need no notification email: a skill (no CLAUDE.md section) and a read-only `gh` fetcher, with one target file and since-cursor per repo. Ships its skill via `templates` into `.claude/skills/`. |

## Install

By fully-qualified name (via the built-in `cg` [registry](https://github.com/mnemcik/cg-extensions-registry)):

```sh
cg extension install cg/1password
```

Installs are fully qualified (`<registry>/<extension>`) — the `cg` alias is the public catalogue. Requires `cg` v1.6.0+.

Or directly from this repo, pointing at the extension's subdir:

```sh
cg extension install https://github.com/mnemcik/cg-extensions --path 1password
```

Remove with `cg extension remove <name>`; update with `cg extension update <name>`.

## Layout

```text
cg-extensions/
  <name>/
    cg-extension.json      # manifest (schema v1)
    fragments/ notes/ …    # contribution payloads
    README.md  CHANGELOG.md
  LICENSE                  # repo-wide (MIT)
```

Each subdir is a complete, independently-installable extension. Because they
share one repo, `cg extension update` tracks the default branch and reads each
extension's version from its manifest's `version` field (a whole-repo git tag
can't identify one co-located extension's version) — so **bump the `version` in
the subdir's `cg-extension.json`** to publish a new version.

## Adding an extension

1. Create `<name>/cg-extension.json` plus its payload dirs (`fragments/`,
   `notes/`, `hooks/`, `templates/`, `bin/` as needed).
2. Add a per-extension `README.md` + `CHANGELOG.md`.
3. CI validates every `*/cg-extension.json` against the canonical schema on push.
4. Add an entry to the [registry](https://github.com/mnemcik/cg-extensions-registry)
   `index.json` with `path: "<name>"` to make it installable by name.

See the Consigliere
[extension authoring guide](https://github.com/mnemcik/consigliere/blob/main/EXTENSIONS.md)
for the manifest reference and contribution points.

## Issues

Open issues in this repository and in [consigliere](https://github.com/mnemcik/consigliere) form one backlog. Type, priority, order and triage follow consigliere's [Issues and priority](https://github.com/mnemcik/consigliere/blob/main/CONTRIBUTING.md#issues-and-priority). Problems with the extension registry are filed here.

## How a PR gets to merge

Extensions run on users' machines, so every PR gets an **impact review** by the maintainer before it can merge, whoever opened it. PRs opened by Dependabot or Renovate are exempt. The review checks:

- **No private data** in the diff, the description or the commit messages: no names of people, or of the employers, clients or customers behind a workspace, and no internal hosts or paths, ticket keys or incidents. The repository is public.
- **Fit:** one extension per concern; a single workspace's preference stays in that workspace.
- **What runs on users' machines:** every contribution point the manifest uses, when it runs (on install, every session, every `cg`, every commit, every tool call, a typed command) and what it can reach. Anything that runs without the user typing it gets the closest look.
- **Untrusted content:** a skill that feeds external content to the agent (issues, PRs, comments, emails, web pages) says that this content is data, never instructions.
- **Shape:** tests where the extension has them, README and CHANGELOG updated, the manifest `version` bumped for a change meant for users.
- **Safety:** a workflow job named like a required check (`impact-review` above all) is rejected, since its result would satisfy that check without a review.

The flow:

1. **The outcome comes as a PR comment:** agreed, or changes requested. A plain agree on the maintainer's own PR may come without a comment.
2. **The PR's author carries it from there:** makes the requested changes, updates the branch from `main`, and answers every review comment until CI is green.
3. **The `impact-review` check** (required) is a commit status on the PR's head commit. Until it is `success`, the PR can't merge. The Impact Review workflow sets it for the bots and posts nothing for other PRs. After the review, the maintainer sets it on that commit:

   ```bash
   gh api -X POST repos/mnemcik/cg-extensions/statuses/<head-sha> \
     -f state=success -f context=impact-review -f description="Impact reviewed"
   ```

   A status belongs to one commit, so **a push needs a new review** at the new head, including an update from `main`. An agent running under the maintainer's account sets it only on the maintainer's go-ahead. Bot PRs are exempt by who opened them, so a person's push to a bot's branch gets `success` too: don't push changes to bot branches, open a separate PR.
4. **One approving review** is required by branch protection. Merging is the maintainer's call.

### Upstream proposals

A change that comes out of a workspace, such as an extension file a workspace edited or a local rule worth sharing, is an **upstream proposal**, not deliberate extension work. Opened by an agent under the maintainer's account, it looks like the maintainer's own PR, so it is also marked:

- **Label `upstream-proposal`**, set when the PR is opened.
- **Opened as a draft**, so it cannot be merged until someone marks it ready.
- **Body from the upstream-proposal template**: `gh pr create --draft --label upstream-proposal --template upstream-proposal.md`. Its Origin and Impact sections say where the change comes from and what it changes for every workspace using the extension.

## License

MIT — see [LICENSE](LICENSE).
