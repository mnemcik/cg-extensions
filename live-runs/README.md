# live-runs

A Consigliere extension for watching headless Claude Code runs (`claude -p`) live: Spec Kit stages, long agent jobs, anything an orchestrating session starts in the background.

## Problem

With `claude -p --output-format json` a run shows nothing until it ends, then only a final summary. A 30-minute implement stage reads files, edits code and runs test suites, and the person guiding the work can't see any of it while it happens. Shell command output (a test run) only reaches the agent when the command ends, so even the event stream shows it late.

## Mechanism

`cg live run <label> <claude args…>` runs `claude -p --output-format stream-json --verbose <claude args…>`:

- **Every agent step** (text, tool calls with their input, tool results, the final result) is written as one JSON event per line to `~/.cache/cg-live/<stamp>-<label>.events.jsonl`, with a `_ts` timestamp.
- **Every shell command's output, live**: the run sets `CLAUDE_CODE_SHELL_PREFIX` to `bin/cg-live-tee`, which runs each Bash tool call unchanged and copies the command and its output, as it happens, to `<stamp>-<label>.cmd.log`. Claude gets the same output and exit code; hooks, the status line and MCP startup pass through untouched. `PYTHONUNBUFFERED=1` keeps Python test runners from holding lines back.
- **The same result as before**: stdout is the final `result` event, the shape `--output-format json` prints (`result`, `session_id`, `total_cost_usd`, …), and the exit code is claude's. Callers switch from `claude -p --output-format json …` to `cg live run <label> …`, with two differences: don't pass `--output-format` (cg live sets it), and pass the prompt as an argument, because claude's stdin is `/dev/null` (a prompt piped in on stdin no longer reaches it).
- **The viewer opens itself inside tmux**: run from a tmux pane (for example a session started by the `tmux` extension), it splits that pane once per window and starts `cg live watch` there; later runs reuse it, and the viewer exits when the pane that started it closes, so quitting the agent also ends the session. Elsewhere it prints how to watch.

`cg live watch` follows the newest run and switches to newer ones by itself: the agent's text, each tool call (`⚙ Bash  pytest …`, `⚙ Edit  file (−3 +5 lines)`), the start of each result, live command output under a `━━ HH:MM:SS $ <command>` header with its exit code, and a closing line with turns, time and cost.

| Contribution | What |
|---|---|
| `subcommands` | `cg live` (`bin/cg-live`, bash; `bin/cg-live-tee`, the shell prefix) |
| `claude-md-sections` | The rule: start headless runs with `cg live run`, and don't pipe their commands through `\| tail` / `\| head` |
| `notes` | `notes/live-runs.md`: commands, files, environment variables, gotchas |

## Usage

```sh
cg extension install cg/live-runs
cg live run 019-implement --permission-mode acceptEdits --allowedTools "Read" "Edit" -- '/speckit-implement …'
cg live watch                 # in another pane; or let the tmux split open it
cg live watch --once <file>   # replay a finished run
```

## Requirements

- cg 1.30.2 or later: older cg doesn't find a subcommand in a subfolder of this repo.
- `claude` (Claude Code) and `jq` on PATH; macOS or Linux.
- The logs hold full transcripts and every command's output. They are private to you (directory `700`, files `600`), and nothing removes them: delete `~/.cache/cg-live/` when you no longer need them.
- Optional: tmux, for the automatic split (see the `tmux` extension). Without it, run `cg live watch` yourself.

## Tests

`tests/run.sh` runs `cg live run` against a fake claude that emits stream-json events and sends one Bash tool call and one hook through the shell prefix the way Claude Code does. The tool calls use the exact invocation shapes Claude Code 2.1.325 sends (captured from the real CLI): a one-word command, a quoted one, a pipeline, and a hook containing `eval '`. It checks the result JSON, the exit code, the event and command logs and their permissions, the prefix's pass-through and exit codes, the tmux split's arguments (with a fake tmux), the viewer exiting when its pane closes, stopping the viewer without killing its caller, and `cg live watch --once` rendering.
