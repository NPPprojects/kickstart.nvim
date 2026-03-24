# AI Integration Spec / Design / Development

## 1. Specification

### 1.1 Feature Name

Manual Patch Apply for Neovim Integration

### 1.2 Purpose

This feature provides a manual patch-application workflow between Codex CLI and Neovim.

Instead of applying an AI patch directly, the CLI hands Neovim a structured payload. Neovim opens the target file, places the cursor at the target region, and overlays the expected final text so the user can type or adjust the change manually.

### 1.3 Current Scope

Implemented today:

- payload-driven handoff from a temporary JSON file into Neovim
- automatic detection of manual-apply payload buffers on `BufReadPost`
- validation of payload shape, `approval_id`, and target file existence
- unified-diff parsing for the first hunk in the first change
- in-buffer overlay rendering using extmarks
- placeholder blank-line insertion when the target replacement is longer than the replaced region
- live comparison between typed buffer content and expected target lines
- automatic completion detection and result-file writeback
- manual overlay clear and undo-based restore behavior

Not implemented:

- automatic patch application
- multi-change or multi-file navigation
- full diff review UI
- exact deletion assistance beyond highlighting replaced/deleted lines
- synchronization of user edits back into Codex beyond completion status

### 1.4 Goals

- Open the correct file from a Codex CLI action
- Move the cursor to the relevant change location
- Show the intended final text without modifying it into the buffer as comments
- Let the user type, revise, or ignore the suggestion
- Report manual-apply completion state back through a result file
- Keep the implementation dependency-free and editor-native

### 1.5 Input Contract

The module only accepts payload paths matching:

```text
/tmp/xcodex-manual-apply-*.json
```

It explicitly ignores result files ending in `.result.json`.

Expected request payload:

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

Required top-level fields:

- `kind`, must be `manual_patch_apply_request`
- `approval_id`, non-empty string
- `changes`, array with at least one entry

Required fields on `changes[1]`:

- `path`, absolute file path to edit
- `diff`, unified diff text

Current implementation notes:

- only `changes[1]` is used
- `change.kind` is currently ignored
- only the first diff hunk is parsed for positioning/rendering

### 1.6 Output Contract

When the manual apply is completed or explicitly cleared, Neovim writes:

```text
<payload>.result.json
```

Current result shape:

```json
{
  "schema_version": 1,
  "kind": "manual_patch_apply_result",
  "approval_id": "example-approval-id",
  "status": "completed"
}
```

Currently emitted statuses:

- `completed`, when the target region matches the expected post-patch content

The clear path also requests a `completed` write today, so there is not yet a distinct cancelled/skipped status.

### 1.7 Success Criteria

The feature is successful if:

- opening a manual-apply payload reliably opens the target file
- the cursor lands at the parsed hunk start or a clamped nearby line
- the expected edit is visible immediately as an overlay
- the overlay updates as the user types
- completion is detected once the edited region matches the expected lines
- a result file is written for the associated `approval_id`

## 2. Design

### 2.1 Runtime Flow

```text
Codex CLI
-> writes /tmp/xcodex-manual-apply-*.json
-> Neovim opens that payload file
-> BufReadPost autocmd detects a manual-apply payload path
-> require('custom.manual_apply').run(path)
-> payload is validated and decoded
-> first change and first hunk are parsed
-> target file is opened
-> overlay state is attached to the target buffer
-> cursor moves to the target line
-> user edits the real buffer contents
-> on each buffer change, overlay re-renders and compares actual vs expected text
-> when the region matches, result file is written and overlay is cleared
```

### 2.2 Integration Point

The entry wiring lives in [init.lua](/home/neepo/.config/nvim/init.lua#L1066):

- a `BufReadPost` autocmd checks whether the opened buffer path is a manual-apply payload
- if so, it schedules `require('custom.manual_apply').run(path)`

The main implementation lives in [manual_apply.lua](/home/neepo/.config/nvim/lua/custom/manual_apply.lua).

### 2.3 Core Components

#### Payload Gate

`is_payload_path(path)` accepts only the expected `/tmp/xcodex-manual-apply-*.json` request files and rejects `.result.json`.

#### Payload Reader

`read_json_file()` uses `vim.fn.readfile()` and `vim.fn.json_decode()` with protected calls and returns structured errors on read/decode failure.

#### Diff Parser

`parse_diff(diff)`:

- finds the first hunk header matching `@@ -old_start,old_count +new_start,new_count @@`
- parses old and new counts with a default count of `1`
- builds `target_lines` from context lines (` ` prefix) plus added lines (`+` prefix, excluding `+++`)
- ignores removed lines when building the expected final text
- returns `(start_line, old_line_count, target_lines)`
- falls back to `(1, 0, raw_diff_lines)` if no hunk is parsed

This means the overlay represents the expected final content of the replaced region, not a literal visual diff.

#### Overlay Renderer

The renderer uses extmarks in the `CodexManualApply` namespace.

Highlights:

- `CodexManualApplyPending` for not-yet-typed expected text
- `CodexManualApplyMatch` for typed text matching the expected content
- `CodexManualApplyMismatch` for incorrect typed characters
- `CodexManualApplyDelete` for lines expected to be removed

Rendering behavior:

- expected text is shown with `virt_text_pos = 'overlay'`
- typed characters are compared character-by-character against expected text
- mismatched spans also receive explicit highlight extmarks
- extra old lines beyond the new target region are highlighted as deletions with ` delete line` virtual text

#### Buffer State Tracker

Per-buffer state is stored in `ACTIVE[buf]` and includes:

- `start_row`
- `old_line_count`
- `target_lines`
- `trailing_anchor`
- `expected_line_count`
- `payload_path`
- `approval_id`
- `result_written`

`LAST_CLEARED[buf]` stores the most recently cleared overlay so it can be restored with the custom undo behavior.

### 2.4 Buffer Mutation Strategy

The module does not insert a comment block.

Instead:

- it opens the real target file
- computes the expected replacement region from the diff
- inserts blank placeholder lines only when the new content is longer than the replaced region
- leaves the actual edit to the user
- uses overlay extmarks so the expected text remains visible while typing

This keeps the real file contents close to the intended final edit workflow and avoids filetype-specific comment handling.

### 2.5 Completion Detection

`region_matches()` treats the manual apply as complete when:

- the buffer lines in the tracked region exactly equal `target_lines`
- and either the trailing anchor line still matches, or the total line count matches the expected line count

When a match is detected:

- `<payload>.result.json` is written with status `completed`
- the overlay namespace is cleared
- active state for that buffer is removed

### 2.6 User Controls

Current buffer-local controls:

- `<leader>m` clears the active overlay
- `u` restores the most recently cleared overlay if none is active; otherwise it performs normal undo

The buffer also attaches an `on_lines` callback to re-render after edits and an `on_detach` callback to clear stored overlay state.

### 2.7 Error Handling

Current failures are surfaced through `vim.notify()` with title `Codex Manual Apply`.

Handled cases:

- unreadable payload file
- invalid JSON payload
- missing required top-level fields
- missing or empty `approval_id`
- missing or empty target path
- target file does not exist
- result-file write failure

Invalid or incomplete diff content is handled best-effort through parser fallback rather than a hard failure.

## 3. Development Status

### 3.1 What Changed From The Original Draft

The original draft described inserting a visible comment block near the target line. The current implementation replaced that approach with extmark overlays and live buffer comparison.

That change materially improved the workflow:

- no filetype-aware comment logic is needed
- the buffer stays editable in-place
- the user sees match, mismatch, and deletion cues while typing
- completion can be derived from actual buffer state

### 3.2 Current Implementation Shape

The implemented API surface is:

```lua
require('custom.manual_apply').is_payload_path(path)
require('custom.manual_apply').run(payload_path)
require('custom.manual_apply').clear_current()
require('custom.manual_apply').restore_current()
```

The main execution path in [manual_apply.lua](/home/neepo/.config/nvim/lua/custom/manual_apply.lua#L374):

1. reject non-manual-apply paths
2. decode and validate payload
3. open `changes[1].path`
4. parse the first diff hunk
5. compute anchors and expected line count
6. insert placeholder lines when needed
7. attach overlay state and buffer callbacks
8. move cursor to the target line

### 3.3 Known Limitations

- only the first change entry is processed
- only the first hunk is used for placement/rendering
- removed lines are indicated visually, but the module does not guide deletion character-by-character
- clear currently writes `completed` instead of a distinct aborted/skipped status
- placeholder blank lines modify the target buffer before the user finishes the edit
- payload-path recognition is tied to the `/tmp/xcodex-manual-apply-*.json` naming convention

### 3.4 Validation Guidance

Useful manual checks for the current implementation:

- open a valid payload and confirm the target file is opened instead of the payload
- verify cursor placement for replace, insert, and pure-addition hunks
- type the expected text and confirm pending/match/mismatch highlights update live
- confirm deletion-only portions are marked with delete highlights
- confirm completion writes `<payload>.result.json`
- clear the overlay with `<leader>m` and restore it with `u`
- verify invalid payloads and missing files surface notifications instead of crashing

### 3.5 Next Logical Extensions

- add distinct `cancelled` or `skipped` result statuses
- support multiple hunks and multiple changes
- improve deletion guidance for shrinking edits
- provide explicit commands for accept/skip/reopen
- make payload-path matching configurable if the CLI path convention changes

## 4. Summary

The implemented system is no longer a proposal for inserted suggestion comments. It is a working manual-apply overlay pipeline:

- Codex hands Neovim a structured request file
- Neovim opens the target file and overlays the expected final text
- the user performs the edit directly in the real buffer
- the module detects completion and writes a result file back for the originating approval

The current design is minimal, fast, and already aligned with a precision-edit workflow, but it is intentionally scoped to single-change, first-hunk handling.
