# tmux

A Consigliere extension that starts the workspace's AI session inside its own tmux session whenever you run `cg` (or `cg start`) in the workspace.

## Problem

An AI session started straight in a terminal tab lives and dies with that tab. Closing the tab or quitting the terminal by accident ends the session. Tools also can't open anything next to it: a live log, a test watcher, or the viewer of the `live-runs` extension. Starting the session in tmux by hand every time is easy to forget and needs a long command.

## Mechanism

The extension contributes a `launcher` (cg 1.32+). `cg start` then runs `bin/cg-tmux launch -- <agent…>` instead of the agent (`session.agent` in `.cg.json`, default `claude`), and `cg-tmux`:

- starts the agent in a **new tmux session** on cg's **own tmux server** (`tmux -L cg`), named `<agent>-<directory>-<HHMMSS>-<pid>`, in the current directory, so every `cg` gets its own session and parallel sessions stay separate. Quitting the agent ends the tmux session. Your own tmux server, its sessions and `~/.tmux.conf` are left alone.
- uses the bundled **`tmux.conf`** when it starts that server: mouse on, 100k lines of history, `escape-time 10` (Esc reaches the agent at once instead of after tmux's default 500 ms), extended keys, true colour, the terminal's tab title taken from the agent's title (so `/rename` shows), and passthrough so the agent's desktop notifications reach the terminal (tmux 3.3+; from any pane, visible or not, on 3.4+). tmux forwards only notifications sent in its passthrough format (DCS `tmux;`), so an agent or hook that writes a plain OSC 777 / OSC 9 is still dropped. It applies to cg's server only, and is read once, when the server starts; `~/.tmux.conf` is not read for it.
- runs the agent **directly** when it is already inside tmux, when stdin or stdout isn't a terminal (tmux can't attach then), or, with a warning, when tmux is not installed. `cg` always starts the session.

**Worth knowing:**
- **Environment.** A new session gets the `PATH` of the `cg` that started it (tmux handles `PATH` that way). The variables in tmux's `update-environment` list (`SSH_AUTH_SOCK`, `DISPLAY` and a few more; `tmux -L cg show -g update-environment` lists them) also come from that `cg`. Every other variable comes from cg's tmux server as it was when the first `cg` started it: a variable you set or change later reaches new sessions only after the server stops (it stops when its last session ends, or `tmux -L cg kill-server`). One exception: `CG_WORKSPACE`, which cg 2.0+ sets to the session's workspace, is passed to each new session itself (`new-session -e`; on tmux before 3.2, as `env CG_WORKSPACE=… <agent>`) and kept out of the server's environment, so `cg <command>` typed in the agent's session is served by its own workspace even from a directory outside it, never by the workspace of the `cg` that started the server. With cg 1.x it is unset and nothing is passed.
- **Exit code.** `cg` returns tmux's exit code, not the agent's.
- **A one-word command runs through a shell.** It is the whole command that counts: bare `cg` with the default `session.agent` (`["claude"]`) gives tmux the single word `claude`, which it runs with its `default-shell -c`; `cg start --resume <id>` (or an agent with arguments) gives it several words, which it executes directly. (On tmux before 3.2 with cg 2.0+, the command starts with `env CG_WORKSPACE=…`, so it is always several words; `env` finds the agent on the same `PATH`.)
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

**Passthrough trade-off.** With passthrough on, any program printing in any pane of cg's tmux server (on tmux 3.4+ also panes that aren't visible) can send escape sequences wrapped in tmux's passthrough format straight to your terminal: clipboard writes, the title, terminal-specific sequences. That is what happens without tmux; tmux still filters sequences that aren't wrapped. A pane that shows raw command output, such as the `live-runs` watch split, is one such pane.

Inside tmux, `Ctrl+B` is tmux's prefix key: Claude Code's own `Ctrl+B` (move a command to the background) needs it twice. A terminal's own features that work per tab (Warp's blocks, for example) don't apply inside tmux.

## Requirements

- cg 1.32+ (the `launcher` contribution point). An older cg installs the extension but ignores the launcher; after upgrading cg, run `cg extension update tmux` to get it.
- tmux 3.2 or later: the bundled `tmux.conf` uses `extended-keys` and `terminal-features`, which 3.0 and 3.1 reject when a session starts. Without tmux, `cg` starts the agent directly and says so.
- macOS or Linux.

## Tests

`tests/run.sh` runs `cg-tmux` against a fake tmux: the arguments (dedicated `-L cg` server, config, directory, agent argv, `-e CG_WORKSPACE=…` only when it is set, `env` on tmux before 3.2, a trailing `;` escaped), unique session names in the same second, and the inside-tmux, no-terminal and no-tmux paths. With the real tmux, when installed, it checks that the bundled `tmux.conf` loads that `CG_WORKSPACE` reaches the agent in a session on a server that is already running, and that a server started with it doesn't pass it to a later session without it.
