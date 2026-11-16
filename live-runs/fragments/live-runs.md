## Live Headless Runs

**Start every headless `claude -p` run (Spec Kit stages, long agent jobs) with `cg live run <label> <claude args…>`, never bare `claude -p`**, so the owner can watch it live; it prints the same result JSON as `--output-format json` and passes the exit code on. In those runs, never pipe commands through `| tail` or `| head`: the output is logged in full anyway, and cutting it holds live output back and loses detail. Details: [`notes/live-runs.md`](notes/live-runs.md).
