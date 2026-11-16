# Changelog

## 0.1.0

- **Added:** `launcher` contribution: `cg` / `cg start` start the agent in a new session on cg's own tmux server (`tmux -L cg`; `<agent>-<dir>-<HHMMSS>-<pid>`, current directory) with the bundled `tmux.conf`; inside tmux, without a terminal, or without tmux (with a warning), the agent runs directly.
