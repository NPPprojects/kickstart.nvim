# Manual Apply UX: Equal-Size Replace

## Scenario Definition

- `old_count == new_count`
- both are greater than `0`
- the user replaces existing text with new text without changing line count

## Current Behavior

- the real lines stay in place
- expected text can be shown directly against the current text
- completion is straightforward because the hunk range does not need to grow or shrink

## What Currently Works Well

- this is the most natural case for overlay-based guidance
- stable line count keeps the hunk easy to reason about
- exact-match highlighting works well once the line content is corrected

## Current UX Risks

- if overlay text is too aggressive, it can hide details the user still needs to edit
- long lines with small edits may still benefit from more targeted mismatch emphasis

## Expected Good UX

- the user can see both what is wrong and what the target text should be
- the edit path is obvious without needing to hide the overlay
- done lines are visually stable and do not redraw oddly

## Manual Validation Notes

- Does the overlay help instead of obscure?
- Are single-character edits obvious?
- Are completed lines visually clean when the cursor is not focused on them?

## Current Assessment

- generally strong after moving completed lines to real-buffer highlighting

## Open Improvement Ideas

- smarter mismatch emphasis for small in-line edits
- optional word-level guidance for long lines
