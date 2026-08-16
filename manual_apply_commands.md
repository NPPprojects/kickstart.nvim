# Manual Apply Commands

Leader key: `<Space>`

Manual apply prefix: `<Space>m`

## Standalone Git Usage

- `:ManualApplyGitFile target` guides the current file through the `HEAD` to `target` diff
- `:ManualApplyGitFile base target` guides the current file through the aggregate `base` to `target` diff

The refs define the source diff; the current buffer is the destination you edit. For example, `:ManualApplyGitFile A E` can replay the combined changes from commits B through E into a current file on a newer branch. Standalone sessions do not create agent result files.

Prefix menu:

- `<Space>ml` autocomplete the current line during an insert phase
- `<Space>ma` approve the current line within the current hunk
- `<Space>mi` materialize the next guided insert line
- `<Space>m.` jump to the next hunk
- `<Space>m,` jump to the previous hunk
- `<Space>m/` autocomplete the current hunk
- `<Space>mc` reject the current hunk
- `<Space>mm` clear or complete the current manual-apply overlay

Outside the prefix:

- `u` undo the most recent manual-apply action, then fall back to normal undo
