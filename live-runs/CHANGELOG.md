# Changelog

## 0.2.0

- **Changed (breaking): requires cg 2.0.** The manifest is v2 and declares its commands (`live`, `live run`, `live watch`) with `commands` instead of `subcommands`; cg 1.x refuses to install it. Update cg on every machine that shares the workspace first (`cg update upgrade`, or `brew upgrade --cask cg` for a Homebrew install), then run `cg extension update` and commit.

## 0.1.1

- **Docs:** the note says how to run `cg live` from a repo outside the workspace: the session must be started with `cg`, so it carries its workspace (cg 2.0+).
- **Fixed:** the usage message lists `cg live watch --until-pane ID`.

## 0.1.0

- **Added:** `cg live run <label> <claude args…>`: runs `claude -p` with `stream-json` events and every shell command's output logged live under `~/.cache/cg-live/`; prints the same result JSON as `--output-format json` and passes claude's exit code on. Inside tmux it opens the viewer as a split, once per window.
- **Added:** `cg live watch [--events | --cmds] [--once] [file]`: follows the latest run (and newer ones) with the agent's text, tool calls, results, live command output and the final turns / time / cost.
- **Added:** the viewer exits when the pane that started it closes; logs are private (`700`/`600`) and named with the process ID; the tmux split passes its command as arguments.
- **Added:** CLAUDE.md rule (start headless runs with `cg live run`; no `| tail` / `| head` in them) and the `notes/live-runs.md` note.
