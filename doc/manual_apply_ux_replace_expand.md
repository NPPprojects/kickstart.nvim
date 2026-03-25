# Manual Apply UX: Expanding Replace

## Scenario Definition

- `old_count < new_count`
- the user replaces an existing block with a longer final block

## Current Behavior

- existing lines provide a real edit anchor
- missing target lines are shown as virtual guidance
- the user must create real buffer lines for the expanded portion

## What Currently Works Well

- the hunk keeps a stable tracked range
- the user can grow the block without placeholder lines being inserted for them
- later hunks are no longer thrown off by the expansion

## Current UX Risks

- users can still hesitate when they need to create the first new real line
- virtual expected lines may feel like they already exist when they do not
- there can be uncertainty about whether to extend from above or below

## Expected Good UX

- the expansion point is explicit
- missing lines are clearly guidance, not editable text
- the first action to create the new lines is obvious

## Manual Validation Notes

- Is the insertion point clear?
- Does the user know when to press `o`, `O`, `A`, or `Enter`?
- Does the expanded block remain understandable after partial completion?

## Current Assessment

- functional
- still dependent on the user understanding normal Vim line-creation flow

## Open Improvement Ideas

- explicit growth markers at the insertion boundary
- stronger guidance on whether the new lines belong above or below the current line
