# Changelog

## 0.3.0

- **Added:** when `CG_WORKSPACE` is set, the new tmux session gets it (`new-session -e`; on tmux before 3.2, which lacks `-e`, the agent is started as `env CG_WORKSPACE=… <agent>`). cg 2.0+ sets it to the session's workspace, so `cg <command>` typed in the agent's session is served by that workspace even from a directory outside it. A new tmux session takes only `PATH` (and tmux's `update-environment` list) from the `cg` that starts it; every other variable comes from the server, which keeps the environment of the `cg` that started it. So without `-e`, every later session would get the first session's workspace.
- **Changed:** `CG_WORKSPACE` is kept out of the tmux server's own environment, so a session that doesn't set it has none instead of another session's. With cg 1.x the variable is unset and the tmux arguments are unchanged.

## 0.2.0

- **Added:** the terminal's tab title follows the agent's title (`set-titles on`, `#T`), so `/rename` and the conversation title show instead of `cg`.
- **Added:** `allow-passthrough` (`on` on tmux 3.3, `all` on 3.4+ so panes that aren't visible are included), so the agent's desktop notifications (OSC 9 / 777, such as "finished" or "needs input") reach the outer terminal. tmux forwards only sequences in its passthrough format (DCS `tmux;`); a plain OSC 777 is still dropped. tmux 3.2 skips the option.
- **Upgrade:** `tmux.conf` is read when cg's tmux server starts. A server that is already running keeps its settings until every cg session has ended; to apply them now, run `tmux -L cg source-file <extension dir>/tmux.conf`.

## 0.1.0

- **Added:** `launcher` contribution: `cg` / `cg start` start the agent in a new session on cg's own tmux server (`tmux -L cg`; `<agent>-<dir>-<HHMMSS>-<pid>`, current directory) with the bundled `tmux.conf`; inside tmux, without a terminal, or without tmux (with a warning), the agent runs directly.
