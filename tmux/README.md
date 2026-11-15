# tmux

A Consigliere extension that starts the workspace's AI session inside its own tmux session whenever you run `cg` (or `cg start`) in the workspace.

## Problem

An AI session started straight in a terminal tab lives and dies with that tab. Closing the tab or quitting the terminal by accident ends the session. Tools also can't open anything next to it: a live log, a test watcher, or the viewer of the `live-runs` extension. Starting the session in tmux by hand every time is easy to forget and needs a long command.

## Mechanism

The extension contributes a `launcher` (cg 1.31+). `cg start` then runs `bin/cg-tmux launch -- <agent…>` instead of the agent (`session.agent` in `.cg.json`, default `claude`), and `cg-tmux`:

- starts the agent in a **new tmux session** named `<agent>-<directory>-<HHMMSS>`, in the current directory, so every `cg` gets its own session and parallel sessions stay separate. Quitting the agent ends the tmux session.
- uses the bundled **`tmux.conf`** when it starts the tmux server: mouse on, 100k lines of history, `escape-time 10` (Esc reaches the agent at once instead of after tmux's default 500 ms), extended keys, true colour. A tmux server that is already running keeps its own settings, and `~/.tmux.conf` is not read for it.
- runs the agent **directly** when it is already inside tmux, or, with a warning, when tmux is not installed. `cg` always starts the session.

| Contribution | What |
|---|---|
| `launcher` | `bin/cg-tmux launch` (a bash script) |

No CLAUDE.md rules, notes or workspace files: removing the extension makes `cg` start the agent directly again.

## Usage

```sh
brew install tmux                  # or your package manager
cg extension install cg/tmux
cg                                 # starts claude inside tmux
tmux attach                        # back to a session after closing its terminal
```

Inside tmux, `Ctrl+B` is tmux's prefix key: Claude Code's own `Ctrl+B` (move a command to the background) needs it twice. A terminal's own features that work per tab (Warp's blocks, for example) don't apply inside tmux.

## Requirements

- cg 1.31+ (the `launcher` contribution point); an older cg installs the extension but ignores the launcher.
- tmux (3.x); without it, `cg` starts the agent directly and says so.
- macOS or Linux.

## Tests

`tests/run.sh` runs `cg-tmux` against a fake tmux (arguments, session name, the inside-tmux and no-tmux paths) and checks with the real tmux, when installed, that the bundled `tmux.conf` loads.
