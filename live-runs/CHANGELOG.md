# Changelog

## 0.1.0

- **Added:** `cg live run <label> <claude args…>`: runs `claude -p` with `stream-json` events and every shell command's output logged live under `~/.cache/cg-live/`; prints the same result JSON as `--output-format json` and passes claude's exit code on. Inside tmux it opens the viewer as a split, once per window.
- **Added:** `cg live watch [--events | --cmds] [--once] [file]`: follows the latest run (and newer ones) with the agent's text, tool calls, results, live command output and the final turns / time / cost.
- **Added:** CLAUDE.md rule (start headless runs with `cg live run`; no `| tail` / `| head` in them) and the `notes/live-runs.md` note.
