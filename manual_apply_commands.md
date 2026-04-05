# Manual Apply Commands

Leader key: `<Space>`

Manual apply prefix: `<Space>m`

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
