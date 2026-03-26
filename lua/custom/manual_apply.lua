local M = {}

local RESULT_SUFFIX = '.result.json'
local ANCHOR_NS = vim.api.nvim_create_namespace 'CodexManualApplyAnchors'
local RENDER_NS = vim.api.nvim_create_namespace 'CodexManualApplyRender'
local ACTIVE = {}
local LAST_CLEARED = {}
local render_overlay

local function ensure_highlights()
  vim.api.nvim_set_hl(0, 'CodexManualApplyPending', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyMatch', { link = 'DiffAdd', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyMismatch', { link = 'DiagnosticError', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyDelete', { link = 'DiffDelete', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyHeader', { link = 'Title', default = true })
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Codex Manual Apply' })
end

local function read_json_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, 'Failed to read file: ' .. path
  end

  local content = table.concat(lines, '\n')
  local decode_ok, data = pcall(vim.fn.json_decode, content)
  if not decode_ok or type(data) ~= 'table' then
    return nil, 'Invalid JSON file: ' .. path
  end

  return data
end

local function split_lines(text)
  if text == '' then
    return {}
  end

  return vim.split(text, '\n', { plain = true })
end

local function parse_hunk_count(raw_count)
  if raw_count == nil or raw_count == '' then
    return 1
  end

  return tonumber(raw_count) or 1
end

local function parse_diff(diff)
  local lines = split_lines(diff)
  local hunks = {}
  local i = 1

  while i <= #lines do
    local line = lines[i]
    local old_start, old_count, new_start, new_count =
      line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

    if old_start then
      local hunk = {
        old_start = tonumber(old_start) or 1,
        old_count = parse_hunk_count(old_count),
        new_start = tonumber(new_start) or 1,
        new_count = parse_hunk_count(new_count),
        lines = {},
      }

      i = i + 1
      while i <= #lines and not vim.startswith(lines[i], '@@ ') do
        local body_line = lines[i]
        if body_line == '' then
          -- Ignore trailing newline after the final diff line.
        elseif vim.startswith(body_line, ' ') then
          hunk.lines[#hunk.lines + 1] = { kind = 'context', text = body_line:sub(2) }
        elseif vim.startswith(body_line, '-') and not vim.startswith(body_line, '---') then
          hunk.lines[#hunk.lines + 1] = { kind = 'delete', text = body_line:sub(2) }
        elseif vim.startswith(body_line, '+') and not vim.startswith(body_line, '+++') then
          hunk.lines[#hunk.lines + 1] = { kind = 'add', text = body_line:sub(2) }
        elseif body_line ~= '\\ No newline at end of file' then
          return nil, 'Unsupported diff line in hunk: ' .. body_line
        end
        i = i + 1
      end

      hunks[#hunks + 1] = hunk
    else
      i = i + 1
    end
  end

  if #hunks == 0 then
    return nil, 'Diff does not contain any unified-diff hunks'
  end

  return hunks
end

local function ensure_hunk_analysis(hunk)
  if hunk.analysis then
    return hunk.analysis
  end

  local old_lines = {}
  local new_lines = {}
  local prefix_context = 0
  local suffix_context = 0

  for _, entry in ipairs(hunk.lines) do
    if entry.kind ~= 'add' then
      old_lines[#old_lines + 1] = entry.text
    end
    if entry.kind ~= 'delete' then
      new_lines[#new_lines + 1] = entry.text
    end
  end

  for _, entry in ipairs(hunk.lines) do
    if entry.kind ~= 'context' then
      break
    end
    prefix_context = prefix_context + 1
  end

  for idx = #hunk.lines, 1, -1 do
    if hunk.lines[idx].kind ~= 'context' then
      break
    end
    suffix_context = suffix_context + 1
  end

  local tracked_old_start = prefix_context + 1
  local tracked_old_end = #old_lines - suffix_context
  local tracked_new_start = prefix_context + 1
  local tracked_new_end = #new_lines - suffix_context
  local tracked_old_lines = {}
  local tracked_new_lines = {}

  if tracked_old_start <= tracked_old_end then
    tracked_old_lines = vim.list_slice(old_lines, tracked_old_start, tracked_old_end)
  end

  if tracked_new_start <= tracked_new_end then
    tracked_new_lines = vim.list_slice(new_lines, tracked_new_start, tracked_new_end)
  end

  hunk.analysis = {
    old_lines = old_lines,
    new_lines = new_lines,
    prefix_context = prefix_context,
    suffix_context = suffix_context,
    tracked_old_lines = tracked_old_lines,
    tracked_new_lines = tracked_new_lines,
    hint_row = math.max(hunk.old_start - 1 + prefix_context, 0),
  }

  return hunk.analysis
end

local function result_path_for_payload(payload_path)
  return payload_path:gsub('%.json$', RESULT_SUFFIX)
end

local function write_result(payload_path, approval_id, status)
  local result_path = result_path_for_payload(payload_path)
  local payload = {
    schema_version = 2,
    kind = 'manual_patch_apply_result',
    approval_id = approval_id,
    status = status,
  }

  local encoded = vim.fn.json_encode(payload)
  local ok, err = pcall(vim.fn.writefile, vim.split(encoded, '\n', { plain = true }), result_path)
  if not ok then
    notify('Failed to write result file: ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

local function get_mark_row(buf, mark_id)
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ANCHOR_NS, mark_id, {})
  if not pos or not pos[1] then
    return nil
  end

  return pos[1]
end

local function get_hunk_rows(buf, hunk)
  local start_row = get_mark_row(buf, hunk.start_mark)
  local end_row = get_mark_row(buf, hunk.end_mark)

  if start_row == nil or end_row == nil then
    return nil, nil
  end

  if end_row < start_row then
    end_row = start_row
  end

  return start_row, end_row
end

local function get_hunk_lines(buf, hunk)
  local start_row, end_row = get_hunk_rows(buf, hunk)
  if start_row == nil or end_row == nil then
    return {}, 0, 0
  end

  return vim.api.nvim_buf_get_lines(buf, start_row, end_row, false), start_row, end_row
end

local function lines_match(actual, expected)
  if #actual ~= #expected then
    return false
  end

  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      return false
    end
  end

  return true
end

local function render_chunks(expected, actual)
  local chunks = {}
  local mismatch_ranges = {}
  local limit = math.min(#expected, #actual)

  for i = 1, limit do
    local expected_char = expected:sub(i, i)
    local actual_char = actual:sub(i, i)
    local group = expected_char == actual_char and 'CodexManualApplyMatch' or 'CodexManualApplyMismatch'
    local display_char = expected_char == actual_char and expected_char or actual_char

    if expected_char ~= actual_char then
      mismatch_ranges[#mismatch_ranges + 1] = { i - 1, i }
      if display_char == ' ' then
        display_char = '_'
      end
    end

    local last = chunks[#chunks]
    if last and last[2] == group then
      last[1] = last[1] .. display_char
    else
      chunks[#chunks + 1] = { display_char, group }
    end
  end

  if #actual < #expected then
    chunks[#chunks + 1] = { expected:sub(#actual + 1), 'CodexManualApplyPending' }
  elseif #actual > #expected then
    mismatch_ranges[#mismatch_ranges + 1] = { #expected, #actual }
  end

  return chunks, mismatch_ranges
end

local function is_prefix_match(expected, actual)
  if #actual > #expected then
    return false
  end

  return expected:sub(1, #actual) == actual
end

local function summarize_hunk(hunk, current_lines)
  local analysis = ensure_hunk_analysis(hunk)

  if lines_match(current_lines, analysis.tracked_new_lines) then
    return 'done', 'completed'
  end

  if #current_lines == 0 and #analysis.tracked_new_lines > 0 then
    return 'pending', 'insert'
  end

  return 'pending', string.format('%d -> %d lines', #analysis.tracked_old_lines, #analysis.tracked_new_lines)
end

local function count_matching_prefix_lines(expected_lines, current_lines)
  local count = 0
  local limit = math.min(#expected_lines, #current_lines)

  for i = 1, limit do
    if is_prefix_match(expected_lines[i], current_lines[i]) then
      count = count + 1
    else
      break
    end
  end

  return count
end

local function is_deletion_heavy(expected_lines, current_lines)
  return #current_lines > #expected_lines
end

local function snapshot_state(buf, state)
  local snapshot = {
    payload_path = state.payload_path,
    approval_id = state.approval_id,
    target_path = state.target_path,
    result_written = state.result_written,
    hunks = {},
  }

  for _, hunk in ipairs(state.hunks) do
    local start_row, end_row = get_hunk_rows(buf, hunk)
    if start_row ~= nil and end_row ~= nil then
      snapshot.hunks[#snapshot.hunks + 1] = {
        index = hunk.index,
        start_row = start_row,
        end_row = end_row,
        hunk = vim.deepcopy(hunk.hunk),
      }
    end
  end

  return snapshot
end

local function clear_render(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, RENDER_NS, 0, -1)
  end
end

local function clear_overlay(buf, opts)
  opts = opts or {}
  local state = ACTIVE[buf]

  if state then
    if opts.write_status or state.result_written then
      LAST_CLEARED[buf] = nil
    else
      LAST_CLEARED[buf] = snapshot_state(buf, state)
    end
  end

  clear_render(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ANCHOR_NS, 0, -1)
  end

  if state and opts.write_status and state.payload_path and state.approval_id and not state.result_written then
    if write_result(state.payload_path, state.approval_id, opts.write_status) then
      state.result_written = true
    end
  end

  ACTIVE[buf] = nil
end

local function create_hunk(buf, spec)
  local start_mark = vim.api.nvim_buf_set_extmark(buf, ANCHOR_NS, spec.start_row, 0, {
    right_gravity = false,
  })
  local end_mark = vim.api.nvim_buf_set_extmark(buf, ANCHOR_NS, spec.end_row, 0, {
    right_gravity = true,
  })

  return {
    index = spec.index,
    hunk = spec.hunk,
    start_mark = start_mark,
    end_mark = end_mark,
  }
end

local function jump_to_hunk(buf, direction)
  local state = ACTIVE[buf]
  if not state or #state.hunks == 0 then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1
  local candidate

  for _, hunk in ipairs(state.hunks) do
    local start_row = get_mark_row(buf, hunk.start_mark)
    if start_row ~= nil then
      if direction > 0 and start_row > cursor and (candidate == nil or start_row < candidate) then
        candidate = start_row
      elseif direction < 0 and start_row < cursor and (candidate == nil or start_row > candidate) then
        candidate = start_row
      end
    end
  end

  if candidate == nil then
    local edge = direction > 0 and state.hunks[1] or state.hunks[#state.hunks]
    candidate = get_mark_row(buf, edge.start_mark) or 0
  end

  vim.api.nvim_win_set_cursor(0, { candidate + 1, 0 })
  return true
end

local function find_sequence_matches(lines, needle, min_row)
  local matches = {}
  min_row = min_row or 0

  if #needle == 0 then
    return matches
  end

  local last_start = #lines - #needle
  for row = math.max(min_row, 0), last_start do
    local ok = true
    for offset = 1, #needle do
      if lines[row + offset] ~= needle[offset] then
        ok = false
        break
      end
    end
    if ok then
      matches[#matches + 1] = row
    end
  end

  return matches
end

local function choose_best_exact_match(lines, hunk, min_row)
  local analysis = ensure_hunk_analysis(hunk)
  if #analysis.old_lines == 0 then
    return nil
  end

  local matches = find_sequence_matches(lines, analysis.old_lines, min_row - analysis.prefix_context)
  local best_row
  local best_score

  for _, row in ipairs(matches) do
    local tracked_start = row + analysis.prefix_context
    if tracked_start >= min_row then
      local score = math.abs(tracked_start - analysis.hint_row)
      if best_score == nil or score < best_score then
        best_row = row
        best_score = score
      end
    end
  end

  if best_row == nil then
    return nil
  end

  local start_row = best_row + analysis.prefix_context
  return {
    start_row = start_row,
    end_row = start_row + #analysis.tracked_old_lines,
  }
end

local function choose_context_anchored_range(lines, hunk, min_row)
  local analysis = ensure_hunk_analysis(hunk)
  local line_count = #lines
  local tracked_old_len = #analysis.tracked_old_lines
  local prefix = vim.list_slice(analysis.old_lines, 1, analysis.prefix_context)
  local suffix = {}

  if analysis.suffix_context > 0 then
    suffix = vim.list_slice(analysis.old_lines, #analysis.old_lines - analysis.suffix_context + 1, #analysis.old_lines)
  end

  local prefix_matches = #prefix > 0 and find_sequence_matches(lines, prefix, min_row - #prefix) or {}
  local suffix_matches = #suffix > 0 and find_sequence_matches(lines, suffix, min_row) or {}
  local best
  local best_score

  if #prefix_matches > 0 and #suffix_matches > 0 then
    local suffix_idx = 1

    for _, prefix_row in ipairs(prefix_matches) do
      local core_start = prefix_row + #prefix
      while suffix_idx <= #suffix_matches and suffix_matches[suffix_idx] < core_start do
        suffix_idx = suffix_idx + 1
      end

      local suffix_row = suffix_matches[suffix_idx]
      if suffix_row then
        local core_end = suffix_row
        if core_start >= min_row and core_end >= core_start then
          local score = math.abs(core_start - analysis.hint_row) + math.abs((core_end - core_start) - tracked_old_len)
          if best_score == nil or score < best_score then
            best = { start_row = core_start, end_row = core_end }
            best_score = score
          end
        end
      end
    end
  elseif #prefix_matches > 0 then
    for _, prefix_row in ipairs(prefix_matches) do
      local start_row = prefix_row + #prefix
      if start_row >= min_row then
        local end_row = math.min(start_row + tracked_old_len, line_count)
        local score = math.abs(start_row - analysis.hint_row)
        if best_score == nil or score < best_score then
          best = { start_row = start_row, end_row = end_row }
          best_score = score
        end
      end
    end
  elseif #suffix_matches > 0 then
    for _, suffix_row in ipairs(suffix_matches) do
      local start_row = math.max(suffix_row - tracked_old_len, min_row)
      local end_row = suffix_row
      if end_row >= start_row then
        local score = math.abs(start_row - analysis.hint_row)
        if best_score == nil or score < best_score then
          best = { start_row = start_row, end_row = end_row }
          best_score = score
        end
      end
    end
  end

  if best then
    return best
  end

  local start_row = math.max(math.min(analysis.hint_row, line_count), min_row)
  return {
    start_row = start_row,
    end_row = math.min(start_row + tracked_old_len, line_count),
  }
end

local function locate_hunk_range(lines, hunk, min_row)
  return choose_best_exact_match(lines, hunk, min_row) or choose_context_anchored_range(lines, hunk, min_row)
end

render_overlay = function(buf)
  local state = ACTIVE[buf]
  if not state or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  clear_render(buf)

  local completed = true

  for _, hunk in ipairs(state.hunks) do
    local analysis = ensure_hunk_analysis(hunk.hunk)
    local current_lines, start_row = get_hunk_lines(buf, hunk)
    local status, detail = summarize_hunk(hunk.hunk, current_lines)
    local header_row = start_row or 0
    local deletion_heavy = is_deletion_heavy(analysis.tracked_new_lines, current_lines)
    local prefix_match_lines = deletion_heavy and count_matching_prefix_lines(analysis.tracked_new_lines, current_lines) or 0

    vim.api.nvim_buf_set_extmark(buf, RENDER_NS, header_row, 0, {
      virt_lines = {
        {
          {
            string.format('manual apply hunk %d/%d [%s: %s]', hunk.index, #state.hunks, status, detail),
            'CodexManualApplyHeader',
          },
        },
      },
      virt_lines_above = true,
      priority = 180,
    })

    local display_len = math.max(#current_lines, #analysis.tracked_new_lines)
    for i = 1, display_len do
      local row = start_row + i - 1
      local actual = current_lines[i]
      local expected = analysis.tracked_new_lines[i]

      if actual ~= nil and expected ~= nil then
        if actual == expected then
          vim.api.nvim_buf_set_extmark(buf, RENDER_NS, row, 0, {
            end_row = row,
            end_col = #actual,
            hl_group = 'CodexManualApplyMatch',
            priority = 199,
          })
        elseif deletion_heavy and i <= prefix_match_lines then
          vim.api.nvim_buf_set_extmark(buf, RENDER_NS, row, 0, {
            end_row = row,
            end_col = #actual,
            hl_group = 'CodexManualApplyMatch',
            priority = 199,
          })
        else
          local chunks, mismatch_ranges = render_chunks(expected, actual)
          if #chunks > 0 then
            vim.api.nvim_buf_set_extmark(buf, RENDER_NS, row, 0, {
              virt_text = chunks,
              virt_text_pos = deletion_heavy and 'eol' or 'overlay',
              hl_mode = 'combine',
              priority = 200,
            })
          end

          for _, range in ipairs(mismatch_ranges) do
            vim.api.nvim_buf_set_extmark(buf, RENDER_NS, row, range[1], {
              end_row = row,
              end_col = range[2],
              hl_group = 'CodexManualApplyMismatch',
              priority = 201,
            })
          end
        end
      elseif actual ~= nil then
        vim.api.nvim_buf_set_extmark(buf, RENDER_NS, row, 0, {
          end_row = row,
          end_col = #actual,
          hl_group = 'CodexManualApplyDelete',
          priority = 200,
        })
        vim.api.nvim_buf_set_extmark(buf, RENDER_NS, row, 0, {
          virt_text = { { ' delete line', 'CodexManualApplyDelete' } },
          virt_text_pos = 'eol',
          priority = 201,
        })
      end
    end

    if #current_lines < #analysis.tracked_new_lines then
      local missing = {}
      for i = #current_lines + 1, #analysis.tracked_new_lines do
        missing[#missing + 1] = { { analysis.tracked_new_lines[i], 'CodexManualApplyPending' } }
      end
      vim.api.nvim_buf_set_extmark(buf, RENDER_NS, start_row + #current_lines, 0, {
        virt_lines = missing,
        priority = 190,
      })
    elseif deletion_heavy then
      local remaining_expected = {}
      for i = prefix_match_lines + 1, #analysis.tracked_new_lines do
        remaining_expected[#remaining_expected + 1] = {
          { 'keep: ', 'CodexManualApplyHeader' },
          { analysis.tracked_new_lines[i], 'CodexManualApplyPending' },
        }
      end

      if #remaining_expected > 0 then
        vim.api.nvim_buf_set_extmark(buf, RENDER_NS, start_row + prefix_match_lines, 0, {
          virt_lines = remaining_expected,
          virt_lines_above = true,
          priority = 190,
        })
      end
    end

    if not lines_match(current_lines, analysis.tracked_new_lines) then
      completed = false
    end
  end

  if completed and not state.result_written then
    if write_result(state.payload_path, state.approval_id, 'completed') then
      state.result_written = true
      clear_overlay(buf)
    end
  end
end

local function attach_buffer(buf)
  if vim.b[buf].codex_manual_apply_attached then
    return
  end

  vim.b[buf].codex_manual_apply_attached = true

  vim.keymap.set('n', '<leader>m', function()
    M.clear_current()
  end, {
    buffer = buf,
    silent = true,
    desc = 'Hide Codex manual apply overlay',
  })

  vim.keymap.set('n', '<leader>M', function()
    M.skip_current()
  end, {
    buffer = buf,
    silent = true,
    desc = 'Skip Codex manual apply request',
  })

  vim.keymap.set('n', ']m', function()
    jump_to_hunk(buf, 1)
  end, {
    buffer = buf,
    silent = true,
    desc = 'Next Codex manual apply hunk',
  })

  vim.keymap.set('n', '[m', function()
    jump_to_hunk(buf, -1)
  end, {
    buffer = buf,
    silent = true,
    desc = 'Previous Codex manual apply hunk',
  })

  vim.keymap.set('n', '<leader>.', function()
    jump_to_hunk(buf, 1)
  end, {
    buffer = buf,
    silent = true,
    desc = 'Next Codex manual apply hunk',
  })

  vim.keymap.set('n', '<leader>,', function()
    jump_to_hunk(buf, -1)
  end, {
    buffer = buf,
    silent = true,
    desc = 'Previous Codex manual apply hunk',
  })

  vim.keymap.set('n', 'u', function()
    if not ACTIVE[buf] and M.restore_current() then
      return
    end

    vim.cmd.normal { 'u', bang = true }
  end, {
    buffer = buf,
    silent = true,
    desc = 'Undo or restore Codex manual apply overlay',
  })

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, changed_buf)
      vim.schedule(function()
        render_overlay(changed_buf)
      end)
    end,
    on_detach = function(_, detached_buf)
      clear_overlay(detached_buf)
      vim.b[detached_buf].codex_manual_apply_attached = nil
    end,
  })
end

local function build_session_specs(buf, hunks)
  local specs = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local min_row = 0

  for index, hunk in ipairs(hunks) do
    local analysis = ensure_hunk_analysis(hunk)
    local range = locate_hunk_range(lines, hunk, min_row)
    if range.start_row < min_row then
      return nil, 'Overlapping hunks are not supported'
    end

    specs[#specs + 1] = {
      index = index,
      start_row = range.start_row,
      end_row = range.end_row,
      hunk = hunk,
    }

    min_row = math.max(range.end_row, range.start_row)

    if #analysis.old_lines == 0 and #analysis.tracked_old_lines == 0 then
      min_row = range.start_row
    end
  end

  return specs
end

function M.clear_current()
  clear_overlay(vim.api.nvim_get_current_buf())
end

function M.skip_current()
  clear_overlay(vim.api.nvim_get_current_buf(), { write_status = 'dismissed' })
end

function M.restore_current()
  local buf = vim.api.nvim_get_current_buf()
  local snapshot = LAST_CLEARED[buf]

  if not snapshot or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local state = {
    payload_path = snapshot.payload_path,
    approval_id = snapshot.approval_id,
    target_path = snapshot.target_path,
    result_written = snapshot.result_written,
    hunks = {},
  }

  for _, spec in ipairs(snapshot.hunks) do
    state.hunks[#state.hunks + 1] = create_hunk(buf, spec)
  end

  ACTIVE[buf] = state
  ensure_highlights()
  render_overlay(buf)
  return true
end

function M.is_payload_path(path)
  if type(path) ~= 'string' then
    return false
  end

  if path:sub(- #RESULT_SUFFIX) == RESULT_SUFFIX then
    return false
  end

  return path:match('^/tmp/xcodex%-manual%-apply%-.+%.json$') ~= nil
end

function M.run(payload_path)
  if not M.is_payload_path(payload_path) then
    return false
  end

  local data, err = read_json_file(payload_path)
  if not data then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  if data.kind ~= 'manual_patch_apply_request' or type(data.changes) ~= 'table' or #data.changes == 0 then
    notify('Payload is missing required manual-apply fields', vim.log.levels.ERROR)
    return false
  end

  if type(data.approval_id) ~= 'string' or data.approval_id == '' then
    notify('Payload is missing a valid approval_id', vim.log.levels.ERROR)
    return false
  end

  local target_path = data.changes[1].path
  if type(target_path) ~= 'string' or target_path == '' then
    notify('Payload change is missing a valid target path', vim.log.levels.ERROR)
    return false
  end

  local all_hunks = {}
  for _, change in ipairs(data.changes) do
    if type(change) ~= 'table' or change.path ~= target_path then
      notify('Manual apply payload must target exactly one file', vim.log.levels.ERROR)
      return false
    end

    local diff = type(change.diff) == 'string' and change.diff or ''
    local parsed_hunks, parse_err = parse_diff(diff)
    if not parsed_hunks then
      notify(parse_err, vim.log.levels.ERROR)
      return false
    end

    for _, hunk in ipairs(parsed_hunks) do
      all_hunks[#all_hunks + 1] = hunk
    end
  end

  table.sort(all_hunks, function(a, b)
    if a.old_start == b.old_start then
      return a.old_count < b.old_count
    end
    return a.old_start < b.old_start
  end)

  if vim.fn.filereadable(target_path) ~= 1 then
    notify('Target file does not exist: ' .. target_path, vim.log.levels.ERROR)
    return false
  end

  vim.cmd('edit ' .. vim.fn.fnameescape(target_path))

  local buf = vim.api.nvim_get_current_buf()
  local specs, spec_err = build_session_specs(buf, all_hunks)
  if not specs then
    notify(spec_err, vim.log.levels.ERROR)
    return false
  end

  clear_overlay(buf)

  local state = {
    payload_path = payload_path,
    approval_id = data.approval_id,
    target_path = target_path,
    result_written = false,
    hunks = {},
  }

  for _, spec in ipairs(specs) do
    state.hunks[#state.hunks + 1] = create_hunk(buf, spec)
  end

  ACTIVE[buf] = state
  ensure_highlights()
  attach_buffer(buf)
  render_overlay(buf)

  local first_row = get_mark_row(buf, state.hunks[1].start_mark) or 0
  vim.api.nvim_win_set_cursor(0, { first_row + 1, 0 })
  notify(string.format('Tracking %d manual apply hunk(s)', #state.hunks))

  return true
end

return M
