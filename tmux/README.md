# tmux

A Consigliere extension that starts the workspace's AI session inside its own tmux session whenever you run `cg` (or `cg start`) in the workspace.

## Problem

An AI session started straight in a terminal tab lives and dies with that tab. Closing the tab or quitting the terminal by accident ends the session. Tools also can't open anything next to it: a live log, a test watcher, or the viewer of the `live-runs` extension. Starting the session in tmux by hand every time is easy to forget and needs a long command.

## Mechanism

The extension contributes a `launcher` (cg 1.32+). `cg start` then runs `bin/cg-tmux launch -- <agent…>` instead of the agent (`session.agent` in `.cg.json`, default `claude`), and `cg-tmux`:

- starts the agent in a **new tmux session** on cg's **own tmux server** (`tmux -L cg`), named `<agent>-<directory>-<HHMMSS>-<pid>`, in the current directory, so every `cg` gets its own session and parallel sessions stay separate. Quitting the agent ends the tmux session. Your own tmux server, its sessions and `~/.tmux.conf` are left alone.
- uses the bundled **`tmux.conf`** when it starts that server: mouse on, 100k lines of history, `escape-time 10` (Esc reaches the agent at once instead of after tmux's default 500 ms), extended keys, true colour, the terminal's tab title taken from the agent's title (so `/rename` shows), and passthrough so the agent's desktop notifications reach the terminal (tmux 3.3+). It applies to cg's server only, and is read once, when the server starts; `~/.tmux.conf` is not read for it.
- runs the agent **directly** when it is already inside tmux, when stdin or stdout isn't a terminal (tmux can't attach then), or, with a warning, when tmux is not installed. `cg` always starts the session.

**Worth knowing:**
- **Environment.** A new session gets the `PATH` of the `cg` that started it (tmux handles `PATH` that way). The variables in tmux's `update-environment` list (`SSH_AUTH_SOCK`, `DISPLAY` and a few more; `tmux -L cg show -g update-environment` lists them) also come from that `cg`. Every other variable comes from cg's tmux server as it was when the first `cg` started it: a variable you set or change later reaches new sessions only after the server stops (it stops when its last session ends, or `tmux -L cg kill-server`).
- **Exit code.** `cg` returns tmux's exit code, not the agent's.
- **A one-word command runs through a shell.** It is the whole command that counts: bare `cg` with the default `session.agent` (`["claude"]`) gives tmux the single word `claude`, which it runs with its `default-shell -c`; `cg start --resume <id>` (or an agent with arguments) gives it several words, which it executes directly.
- **Closing the terminal leaves the agent running** inside cg's tmux server. Quit the agent to end the session, or stop it from outside with `tmux -L cg kill-session -t <name>`.

| Contribution | What |
|---|---|
| `launcher` | `bin/cg-tmux launch` (a bash script) |

No CLAUDE.md rules, notes or workspace files: removing the extension makes `cg` start the agent directly again.

## Usage

```sh
brew install tmux                  # or your package manager
cg extension install cg/tmux
cg                                 # starts claude inside tmux
tmux -L cg ls                      # cg's sessions
tmux -L cg attach                  # back to the most recent one after closing its terminal
tmux -L cg attach -t <name>        # or to a specific one
tmux -L cg kill-session -t <name>  # stop one from outside
```

Inside tmux, `Ctrl+B` is tmux's prefix key: Claude Code's own `Ctrl+B` (move a command to the background) needs it twice. A terminal's own features that work per tab (Warp's blocks, for example) don't apply inside tmux.

## Requirements

- cg 1.32+ (the `launcher` contribution point). An older cg installs the extension but ignores the launcher; after upgrading cg, run `cg extension update tmux` to get it.
- tmux 3.2 or later: the bundled `tmux.conf` uses `extended-keys` and `terminal-features`, which 3.0 and 3.1 reject when a session starts. Without tmux, `cg` starts the agent directly and says so.
- macOS or Linux.

## Tests

`tests/run.sh` runs `cg-tmux` against a fake tmux: the arguments (dedicated `-L cg` server, config, directory, agent argv), unique session names in the same second, and the inside-tmux, no-terminal and no-tmux paths. With the real tmux, when installed, it checks that the bundled `tmux.conf` loads.
