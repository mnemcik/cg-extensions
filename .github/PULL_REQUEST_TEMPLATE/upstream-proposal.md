## Summary

What this PR changes in the framework.

## Origin

- **Workspace:** which workspace the change comes from
- **Source:** the file or rule there (e.g. a drifted `notes/<name>.md`), and the incident or reason behind it
- **Why upstream:** why every workspace benefits, not only this one

## Impact on workspaces

- **On update:** what changes for a workspace with this extension installed (`cg extension update`)
- **Drift:** which workspaces edited the same files and will see them as drifted, if known
- **Behaviour:** how Claude acts differently after the change, and in which situations

## Test plan

- [ ] The extension's own tests pass (`<name>/tests/run.sh`, if it has them)
- [ ] Opened as a draft with the `upstream-proposal` label; `impact-reviewed` is added by the maintainer only

See [README.md](https://github.com/mnemcik/cg-extensions/blob/main/README.md#upstream-proposals) for what the label and the gate do.
