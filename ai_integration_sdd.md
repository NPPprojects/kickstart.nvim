# AI Integration Spec / Design / Development

## 1. Purpose

The Neovim manual-apply flow is the bridge between a Codex CLI approval and a real editor session.

The old version tried to make multi-hunk editing feel live by:

- precomputing every hunk position up front
- inserting placeholder blank lines into the real buffer
- overlaying expected final text on top of those fixed coordinates

That model works for a single local edit and short replace hunks. It falls apart when multiple hunks are active because every later hunk depends on earlier line-count assumptions staying true while the user is still editing.

The rebuilt system is hunk-centric instead of buffer-geometry-centric:

- each hunk gets its own tracked range in the target buffer
- range boundaries are extmarks, so they move with user edits
- no placeholder lines are inserted into the file
- completion is evaluated per hunk against the live text inside that hunk range

## 2. Old System Review

### 2.1 What It Did Well

- very small dependency-free implementation
- payload handoff from CLI into Neovim was already simple and reliable
- overlay rendering made the expected end state visible without inserting comments
- line-by-line typing feedback was useful for one local edit
- completion writeback through `<payload>.result.json` already matched the CLI workflow

### 2.2 Hard Constraints In The Old Design

- only one target file was practical
- all hunk start rows were calculated once at launch time
- later hunk coordinates depended on placeholder insertion and assumed line deltas
- completion used exact global region checks against those frozen coordinates
- the target buffer was mutated before the user had finished deciding what to do

### 2.3 Failure Modes

- editing an earlier hunk could invalidate every later hunk's assumed row range
- insertion-heavy diffs required placeholder blanks, which changed the real buffer before acceptance
- `clear_current()` wrote `completed`, so dismissal and success were conflated
- the design doc overstated multi-hunk support because rendering multiple hunks is not the same thing as tracking them robustly
- the model had no clean separation between anchor state and render state, so the whole system depended on one shared geometry pass

## 3. Replacement Design

### 3.1 Scope

Implemented now:

- payload-driven handoff from `/tmp/xcodex-manual-apply-*.json`
- validation of payload shape and target path
- support for multiple hunks across one target file
- support for multiple `changes[]` entries only when they all target the same file
- stable per-hunk tracking using extmark anchors
- overlay rendering without modifying the target buffer
- per-hunk status headers plus pending/match/mismatch/delete feedback
- explicit `dismissed` result status
- reversible overlay hide/restore flow
- hunk navigation keymaps

Not implemented:

- multi-file payload sessions
- fuzzy relocation if diff coordinates no longer match the file well
- three-way merge behavior
- automatic patch application
- rich review UI outside the edited buffer

### 3.2 Input Contract

Accepted payload path:

```text
/tmp/xcodex-manual-apply-*.json
```

Result files ending in `.result.json` are ignored.

Expected payload:

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

Rules:

- `kind` must be `manual_patch_apply_request`
- `approval_id` must be a non-empty string
- `changes` must contain at least one change
- every change must target the same absolute file path
- every change must contain a unified diff with at least one hunk

### 3.3 Output Contract

The module writes:

```text
<payload>.result.json
```

Current result shape:

```json
{
  "schema_version": 2,
  "kind": "manual_patch_apply_result",
  "approval_id": "example-approval-id",
  "status": "completed"
}
```

Statuses:

- `completed`: every tracked hunk range exactly matches the diff's new lines
- `dismissed`: the user explicitly skips the request with the dedicated skip action

### 3.4 Runtime Model

Flow:

```text
Codex CLI
-> writes manual-apply payload
-> Neovim opens payload file
-> BufReadPost detects payload path
-> require('custom.manual_apply').run(path)
-> payload is decoded and validated
-> all hunks for the single target file are parsed and sorted
-> target file is opened
-> each hunk gets start/end extmark anchors in the real buffer
-> renderer compares the live text inside each anchored range to the expected new lines
-> overlays show progress without inserting placeholder content
-> when all hunks match, result file is written and the overlay is cleared
```

Key architectural change:

- hunk anchors live in a dedicated namespace
- render overlays live in a separate namespace
- clearing render output no longer destroys the tracking model by accident

### 3.5 UX Controls

Buffer-local controls:

- `<leader>m`: hide the overlay without finalizing the request
- `u`: restore the most recently hidden overlay when no manual-apply session is active
- `<leader>M`: mark the request `dismissed` and clear it
- `]m`: jump to next hunk
- `[m`: jump to previous hunk

## 4. Constraints Of The New System

The rebuild fixes the core multi-hunk instability, but it is still intentionally constrained:

- single-file only
- line-oriented only; no character-precise patch semantics across line boundaries
- no fuzzy search if the file no longer resembles the diff context
- overlapping hunks are rejected
- restore recreates anchors from the last hidden positions; it is not a durable session store

Those constraints are acceptable because they are explicit and mechanically defensible. They do not pretend to solve merge logic with overlay tricks.

## 5. Implementation Notes

Main entry points:

```lua
require('custom.manual_apply').is_payload_path(path)
require('custom.manual_apply').run(payload_path)
require('custom.manual_apply').clear_current()
require('custom.manual_apply').skip_current()
require('custom.manual_apply').restore_current()
```

Main implementation file:

[manual_apply.lua](/home/neepo/.config/nvim/lua/custom/manual_apply.lua)

Autocmd wiring:

[init.lua](/home/neepo/.config/nvim/init.lua#L1066)

## 6. Validation Checklist

Manual checks for the rebuilt system:

- open a valid payload and confirm the target file replaces the payload buffer
- verify multiple hunks render without placeholder line insertion
- edit an early hunk and confirm later hunks stay attached to their own ranges
- verify pending inserted lines appear as virtual lines instead of real blank lines
- confirm `completed` is written only when all hunks match exactly
- confirm `<leader>M` writes `dismissed`
- confirm `<leader>m` hides the overlay and `u` restores it
- confirm `[m` and `]m` navigate between hunks
- confirm multi-file payloads and overlapping hunks fail clearly instead of being handled implicitly
