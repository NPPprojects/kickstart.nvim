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
        old_lines = {},
        new_lines = {},
      }

      i = i + 1
      while i <= #lines and not vim.startswith(lines[i], '@@ ') do
        local body_line = lines[i]
        if body_line == '' then
          -- Trailing newline after the final diff line.
        elseif vim.startswith(body_line, ' ') then
          table.insert(hunk.old_lines, body_line:sub(2))
          table.insert(hunk.new_lines, body_line:sub(2))
        elseif vim.startswith(body_line, '-') and not vim.startswith(body_line, '---') then
          table.insert(hunk.old_lines, body_line:sub(2))
        elseif vim.startswith(body_line, '+') and not vim.startswith(body_line, '+++') then
          table.insert(hunk.new_lines, body_line:sub(2))
        elseif body_line ~= '\\ No newline at end of file' then
          return nil, 'Unsupported diff line in hunk: ' .. body_line
        end
        i = i + 1
      end

      table.insert(hunks, hunk)
    else
      i = i + 1
    end
  end

  if #hunks == 0 then
    return nil, 'Diff does not contain any unified-diff hunks'
  end

  return hunks
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

local function summarize_hunk(hunk, current_lines)
  if lines_match(current_lines, hunk.new_lines) then
    return 'done', 'completed'
  end

  if #current_lines == 0 and #hunk.new_lines > 0 then
    return 'pending', 'insert'
  end

  return 'pending', string.format('%d -> %d lines', #hunk.old_lines, #hunk.new_lines)
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
        old_lines = vim.deepcopy(hunk.old_lines),
        new_lines = vim.deepcopy(hunk.new_lines),
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

  if state then
    if opts.write_status and state.payload_path and state.approval_id and not state.result_written then
      if write_result(state.payload_path, state.approval_id, opts.write_status) then
        state.result_written = true
      end
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
    old_lines = spec.old_lines,
    new_lines = spec.new_lines,
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

render_overlay = function(buf)
  local state = ACTIVE[buf]
  if not state or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  clear_render(buf)

  local completed = true

  for _, hunk in ipairs(state.hunks) do
    local current_lines, start_row = get_hunk_lines(buf, hunk)
    local status, detail = summarize_hunk(hunk, current_lines)
    local header_row = start_row or 0

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

    local display_len = math.max(#current_lines, #hunk.new_lines)
    for i = 1, display_len do
      local row = start_row + i - 1
      local actual = current_lines[i]
      local expected = hunk.new_lines[i]

      if actual ~= nil and expected ~= nil then
        local chunks, mismatch_ranges = render_chunks(expected, actual)
        if #chunks > 0 then
          vim.api.nvim_buf_set_extmark(buf, RENDER_NS, row, 0, {
            virt_text = chunks,
            virt_text_pos = 'overlay',
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

    if #current_lines < #hunk.new_lines then
      local missing = {}
      for i = #current_lines + 1, #hunk.new_lines do
        missing[#missing + 1] = { { hunk.new_lines[i], 'CodexManualApplyPending' } }
      end
      vim.api.nvim_buf_set_extmark(buf, RENDER_NS, start_row + #current_lines, 0, {
        virt_lines = missing,
        priority = 190,
      })
    end

    if not lines_match(current_lines, hunk.new_lines) then
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
  local line_count = vim.api.nvim_buf_line_count(buf)

  for index, hunk in ipairs(hunks) do
    local start_row = math.max(math.min(hunk.old_start - 1, line_count), 0)
    local end_row = math.max(math.min(start_row + hunk.old_count, line_count), start_row)

    if #specs > 0 then
      local prev = specs[#specs]
      if start_row < prev.end_row then
        return nil, 'Overlapping hunks are not supported'
      end
    end

    specs[#specs + 1] = {
      index = index,
      start_row = start_row,
      end_row = end_row,
      old_lines = hunk.old_lines,
      new_lines = hunk.new_lines,
    }
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
