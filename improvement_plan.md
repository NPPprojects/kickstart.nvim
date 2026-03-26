# Improvement Plan

## Manual Apply

### High-value next steps

1. Better fuzzy/context relocation
   Use exact old-side matches first, then exact context-anchor matches, then a bounded context-scored search near the hinted location.
2. Per-hunk actions
   Add commands to hide, skip, or otherwise act on only the hunk under the cursor instead of the full session.
3. Session summary list
   Expose all tracked hunks and their status in a quickfix or location list for faster scanning.
4. Re-anchor command
   Add an explicit command to re-scan and re-anchor hunks after the buffer has drifted.

### Additional quality-of-life improvements

- Show collapsed prefix/suffix context near the hunk header so the user can see why the hunk is anchored there.
- Show session progress in headers, such as `2/5 completed`, and make the current hunk more visually distinct.
- Add a diff-view toggle that opens a scratch preview of old content versus expected new content for the current hunk.
- Support durable session recovery beyond the current in-memory restore flow.
- Differentiate strict completion from softer states such as whitespace-only mismatches.

### Next review

- Consider what can be removed from the current manual-apply flow to simplify the model and reduce UI noise.
- Standardize navigation on `<leader>,` and `<leader>.`; remove redundant `[m` and `]m` mappings.
- Keep `restore_current()` and `LAST_CLEARED`; do not remove the hide-and-restore flow.
- Evaluate whether character-level mismatch rendering can be simplified to line-level feedback.
- Evaluate whether the deletion-heavy special rendering path is worth keeping or should be folded into one simpler render model.
