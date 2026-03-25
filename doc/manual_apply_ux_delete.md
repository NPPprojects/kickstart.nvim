# Manual Apply UX: Pure Delete

## Scenario Definition

- `old_count > 0`
- `new_count == 0`
- the user must remove text without replacing it with new buffer lines

## Current Behavior

- lines that should be removed stay visible in the real buffer
- delete-target lines are highlighted with delete styling
- the user can remove the lines directly with normal Vim delete operations

## What Currently Works Well

- real source text remains visible
- the hunk is usually easy to complete with linewise deletion
- there is little ambiguity about the target end state

## Current UX Risks

- character-wise deletions can still be awkward if the user attempts precise editing instead of deleting the whole line or block
- mixed context lines can make it slightly unclear where the deletion boundary ends

## Expected Good UX

- delete lines remain visible until removed
- nothing obscures the text that still needs to be deleted
- linewise operations like `dd` or visual delete feel natural and sufficient

## Manual Validation Notes

- Are delete-only hunks obvious on first view?
- Does the user know which lines to remove without reading the raw diff?
- Does the UI remain clear when adjacent context lines are long?

## Current Assessment

- one of the strongest scenarios in the current implementation

## Open Improvement Ideas

- optional `delete block` summary when several consecutive lines are pure removals
- more explicit boundary markers for large delete spans
