# Manual Apply System

## Purpose

`lua/custom/manual_apply.lua` implements a Neovim workflow for manually applying AI-suggested edits from a unified diff payload.

The system is designed to keep the diff visible as guidance while the user edits the real file themselves. It does not auto-apply the patch, and it does not insert placeholder content just to make the overlay work.

At a high level:

1. Codex writes a JSON payload in `/tmp`.
2. Neovim detects that payload when opened.
3. `manual_apply.lua` opens the target file, parses the diff into hunks, and locates each hunk in the live buffer.
4. Each hunk is tracked with extmarks so it remains attached as the user edits.
5. The renderer shows per-hunk status, delete guidance, insert guidance, and match or mismatch highlighting.
6. When every tracked hunk exactly matches the diff's new-side text, the module writes a result file and clears the session.

## Entry Points

Main module:

- [manual_apply.lua](/home/neepo/.config/nvim/lua/custom/manual_apply.lua)

Autocmd wiring:

- [init.lua](/home/neepo/.config/nvim/init.lua#L1066)

Public functions:

- `require('custom.manual_apply').is_payload_path(path)`
- `require('custom.manual_apply').run(payload_path)`
- `require('custom.manual_apply').clear_current()`
- `require('custom.manual_apply').skip_current()`
- `require('custom.manual_apply').restore_current()`

## Payload Contract

Accepted payload path:

```text
/tmp/xcodex-manual-apply-*.json
```

Ignored path:

```text
*.result.json
```

Expected request shape:

```json
{
  "kind": "manual_patch_apply_request",
  "approval_id": "example-approval-id",
  "changes": [
    {
      "path": "/absolute/path/to/file",
      "kind": "update",
      "diff": "@@ -10,2 +10,3 @@\n old\n-old2\n+new2\n+new3\n"
    }
  ]
}
```

Current validation rules:

- `kind` must be `manual_patch_apply_request`
- `approval_id` must be a non-empty string
- `changes` must be a non-empty array
- `changes[1].path` selects the target file
- every `change` for that same `path` is parsed and included in the session
- changes for other files are ignored
- diffs must contain at least one unified-diff hunk, unless `change.kind == 'add'`, in which case the raw diff text is treated as full inserted content

Result file:

```text
<payload>.result.json
```

Result shape:

```json
{
  "schema_version": 2,
  "kind": "manual_patch_apply_result",
  "approval_id": "example-approval-id",
  "status": "completed"
}
```

Statuses currently written:

- `completed`
- `dismissed`

## Hunk Model

The implementation parses unified diff hunks into a low-level line model:

- `context` lines
- `delete` lines
- `add` lines
- old and new line-number hints from the `@@ ... @@` header

From that, it derives:

- `old_lines`: context plus deletions, representing the old-side sequence
- `new_lines`: context plus additions, representing the new-side sequence
- `tracked_old_lines`: only the lines that must disappear or change
- `tracked_new_lines`: only the lines that must appear in the final result
- `prefix_context` and `suffix_context`: shared context around the tracked change
- `hint_row`: an approximate placement hint derived from the diff header

This matters because the tracked region is not always the full hunk. Context is used to place the hunk, but only the change span is tracked as editable work.

Examples:

- pure insert: tracked old span is empty, tracked new span contains inserted lines
- pure delete: tracked old span contains deleted lines, tracked new span is empty
- replace: tracked old span contains replaced lines, tracked new span contains replacement lines

## Session Model

The module keeps one active session per buffer in `ACTIVE[buf]`.

Each session stores:

- payload metadata
- target file path
- whether a result file has already been written
- an ordered list of tracked hunks

Each tracked hunk stores:

- parsed hunk data
- a start extmark
- an end extmark
- `insert_started`, which keeps replacement hunks in insert mode once the old block has been cleared

Two namespaces are used:

- `ANCHOR_NS`: durable extmarks that define each tracked hunk range
- `RENDER_NS`: transient extmarks for headers, highlights, overlays, and virtual lines

That separation is central to the current design. Clearing render output does not destroy the tracked ranges.

## Placement Strategy

The module does not trust unified-diff line numbers as exact coordinates.

For each hunk, `build_session_specs()` calls `locate_hunk_range()` and uses this placement order:

1. exact match of the hunk's old-side line sequence
2. context-anchored placement using prefix and or suffix context
3. fallback placement near the diff hint row

Important limits of the current implementation:

- placement is exact-line based, not fuzzy
- removed-span verification is implicit in the exact-match path, but the fallback context path is still heuristic
- overlapping hunks are rejected
- placement is only solved once at session start; later stability comes from extmarks, not re-searching

## Rendering And Hunk Phases

`render_overlay()` reevaluates every hunk after buffer changes and renders the current state from live buffer text inside each tracked range.

Each hunk is summarized into one of three phases:

- `done`
- `delete`
- `insert`

Those phases are derived from the relationship between current tracked text, `tracked_old_lines`, and `tracked_new_lines`.

### Done

If the tracked buffer lines exactly equal `tracked_new_lines`, the hunk is complete.

Rendering:

- header reports completion
- real lines are highlighted as matches

### Delete Phase

Used for:

- pure delete hunks
- replacement hunks before the old tracked text has been cleared

Rendering:

- lines still in the tracked span are highlighted with delete styling
- an end-of-line hint says `delete line`

### Insert Phase

Used for:

- pure insert hunks
- replacement hunks after delete work is complete

Rendering:

- existing inserted lines are compared against expected new lines
- exact matches are highlighted as matches
- partial same-line typing gets overlay guidance and mismatch highlights
- missing remaining lines are shown as virtual lines at the insertion boundary

The insert phase is intentionally sticky for replacement hunks. Once the user has cleared the old tracked block and begun constructing the new block, small mistakes do not flip the hunk back into delete mode.

## User Controls

Buffer-local controls are attached when a session starts.

- `<leader>m`: clear the overlay and write `completed`
- `<leader>.`: jump to next hunk
- `<leader>,`: jump to previous hunk
- `<leader>i`: materialize the next guided insert line near the cursor and enter insert mode
- `u`: restore the last hidden overlay if no session is active, otherwise perform normal undo
- insert-mode `<Tab>`: insert indentation spaces based on `softtabstop`, then `shiftwidth`, then `tabstop`

Two behavior notes matter here:

- `clear_current()` is an explicit force-complete action. It writes `completed` even if the tracked hunks do not currently match the diff.
- `skip_current()` exists as a public function, but the module does not currently bind a default buffer-local key for it.
- `restore_current()` only restores the most recently cleared snapshot for the current buffer. It is not persistent session storage.

## Completion Rules

Automatic completion happens inside `render_overlay()`.

If every hunk's live tracked lines exactly match its `tracked_new_lines`:

1. the module writes `<payload>.result.json` with `status = "completed"`
2. the session is cleared
3. no snapshot is kept for restore

Manual dismissal happens through `skip_current()`, which writes `dismissed` and clears the session without keeping a snapshot.

Manual clear through `clear_current()` also clears the session, but writes `completed` immediately.

## What The System Does Well

- tracks multiple hunks in one file without freezing absolute row coordinates
- avoids placeholder edits in the target buffer
- keeps tracking state separate from render state
- handles insert-heavy edits more cleanly by showing pending lines as virtual guidance
- supports restoring a recently hidden overlay

## Current Constraints

The implementation is narrower than a full patch engine.

- single-file sessions only
- mixed-file payloads are partially supported by ignoring later files
- no fuzzy search or three-way merge behavior
- line-oriented only
- placement fallback can still choose a defensible approximation rather than a verified exact old-span match
- overlapping hunks are rejected
- `clear_current()` conflates hide or finish with forced success

## Relationship To The Other Markdown Files

This document should be treated as the authoritative system description for the current implementation.

The other manual-apply markdown files are still useful, but they serve different roles:

- `ai_integration_sdd.md`: broader integration and historical design context
- `doc/manual_apply_ux_*.md`: scenario-specific UX notes and test prompts
- `doc/manual_apply_ux_index.md`: scenario index

If those files disagree with this document, this document should win unless the code changes.
