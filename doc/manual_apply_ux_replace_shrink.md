# Manual Apply UX: Shrinking Replace

## Scenario Definition

- `old_count > new_count`
- the user must remove some old content while preserving a shorter final block

## Current Behavior

- matching prefix lines can stay highlighted in place
- remaining delete-target lines stay visible in the real buffer
- the target text for the shorter final block may be shown as side guidance instead of directly covering old text

## What Currently Works Well

- later hunks remain stable while the current hunk shrinks
- deletion-heavy cases are much more usable than the previous placeholder-based system
- the real text that still needs to be removed can remain visible

## Current UX Risks

- mid-transition states can look duplicated when the old structure and new shorter structure are both partially visible
- anchor lines can appear in both old and target positions while the hunk is only half-complete
- the user may not immediately know whether to delete more lines or move preserved lines

## Expected Good UX

- the UI should never cover text that must still be deleted
- the final retained lines should be understandable without making the old lines unreadable
- temporary duplicate-looking states should still suggest a clear next action

## Manual Validation Notes

- Can the user tell which lines are kept versus removed?
- Is it obvious how to consolidate the block down to the shorter final form?
- Are deletion-heavy replacements easier with linewise edits than characterwise edits?

## Current Assessment

- improved and usable
- still one of the scenarios most likely to need ongoing tuning

## Open Improvement Ideas

- stronger `keep:` / `remove:` labeling for mixed blocks
- better presentation for duplicate-looking anchor lines during partial completion
