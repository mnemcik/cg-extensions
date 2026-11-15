# Live Headless Runs (`cg live`)

**Category:** workflow
**Tags:** `claude-code`, `headless`, `monitoring`
**Source:** the `live-runs` cg extension

Load when starting, watching or debugging a headless `claude -p` run.

## Commands

- `cg live run <label> <claude args…>`: `claude -p --output-format stream-json --verbose <claude args…>`, with `</dev/null`. Do not pass `--output-format` yourself. stdout is the final `result` event as one JSON object (as `--output-format json`), the exit code is claude's. Read `.result`, `.session_id` (for `--resume`) and `.total_cost_usd` from it as before.
- `cg live watch [--events | --cmds] [--once] [file]`: follow the latest run, or the given `*.events.jsonl` / `*.cmd.log`. `WATCH_LINES=40` shows more of each tool result, `WATCH_THINKING=1` shows thinking.

## Files

`$CG_LIVE_DIR` (default `~/.cache/cg-live/`) keeps every run: `<stamp>-<label>.events.jsonl` (one event per line, `_ts` added), `<stamp>-<label>.cmd.log` (each shell command with a header, its output, its exit code), and `latest.*` symlinks to the newest run. Nothing cleans them up.

## Environment

| Variable | Effect |
|---|---|
| `CG_LIVE_DIR` | where runs are logged |
| `CG_LIVE_NO_WATCH=1` | no tmux split and no hint |
| `CG_LIVE_CLAUDE` | the claude binary to run (tests) |

## Gotchas

- **Don't pipe commands through `| tail -N` or `| head`** in a run's prompt or let the agent do it on its own: `tail` holds all output back until the command ends, so nothing streams, and the agent loses the lines it cut (e.g. which tests were skipped). Say "run commands without `| tail` / `| head`; the output is logged anyway" in stage prompts.
- **The split opens once per tmux window**, marked with the pane option `@cg_live_watch`; closing the viewer (Ctrl+C) lets the next run open a new one. Ctrl+C in the viewer stops watching, not the run.
- **Opening the viewer after a run started** replays the events first, then the command log, so on a replay the two are not interleaved in time order. Live, they are.
- **The shell prefix sees more than Bash tool calls**: hooks, the status line and stdio MCP startup go through it too; only invocations of the form `… eval '<cmd>' < /dev/null …` are logged.
