# Manual Apply UX: Pure Insert

## Scenario Definition

- `old_count == 0`
- `new_count > 0`
- the diff introduces new lines at an anchor point without deleting existing lines

## Current Behavior

- the target text is shown as virtual guidance
- the real buffer may not yet contain an editable line for the inserted text
- the user often needs to infer whether to use `o`, `O`, `i`, or to press `Enter` from insert mode

## What Currently Works Well

- the system does not mutate the buffer with placeholder lines
- expected inserted lines are visible
- once the user creates the real lines, the hunk can complete cleanly

## Current UX Risks

- the insertion anchor is not always obvious
- virtual guidance can look like editable text when it is not
- users may think the system is blocking text entry when the real issue is that no real line exists yet

## Expected Good UX

- the user can tell immediately where the new lines belong
- the UI makes it obvious whether insertion is above or below the anchor
- the first keystroke to start inserting is discoverable
- guidance never implies that a virtual line is directly editable

## Manual Validation Notes

- Can a user identify the insertion point without experimentation?
- Is it clear whether `o` or `O` is the natural action?
- Does the guidance still make sense after one or two inserted lines already exist?
- Is completion understandable once the inserted lines match?

## Current Assessment

- mechanically functional
- discoverability still weaker than it should be

## Open Improvement Ideas

- explicit `insert below` / `insert above` markers
- hunk header hint for first action
- stronger visual distinction between virtual guidance and real editable lines
