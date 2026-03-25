# Manual Apply UX: Multi-Hunk Session

## Scenario Definition

- one payload produces multiple hunks in the same target file
- hunks can be any combination of insert, delete, equal-size replace, shrinking replace, or expanding replace

## Current Behavior

- each hunk is tracked with its own extmark-backed range
- editing one hunk no longer invalidates the coordinates of later hunks
- each hunk gets its own header and progress status
- `[m` and `]m` provide local navigation

## What Currently Works Well

- this is the main architectural improvement over the previous system
- earlier line-count changes do not break later hunk tracking
- the session stays coherent even when several hunks are active

## Current UX Risks

- users still have to understand the render behavior of each individual hunk type
- partial progress across many hunks can be visually noisy
- session-level completion is only obvious once all individual hunks settle

## Expected Good UX

- each hunk is locally understandable
- navigation between hunks is fast
- no hunk becomes misaligned because another hunk changed line count
- the session feels like a set of independent guided edits, not one fragile global overlay

## Manual Validation Notes

- Do later hunks remain visually and behaviorally correct after major edits to early hunks?
- Is hunk navigation sufficient for larger sessions?
- Is the per-hunk header enough, or is a session summary eventually needed?

## Current Assessment

- architecturally much better than the original system
- UX quality now depends more on per-hunk rendering than on tracking correctness

## Open Improvement Ideas

- session summary of completed vs pending hunks
- stronger distinction between active hunk and surrounding hunks
- eventual support for multi-file sessions as a separate higher-level workflow
