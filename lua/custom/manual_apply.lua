local M = {}

local PAYLOAD_PATTERN = '^/tmp/xcodex%-manual%-apply%-.+[^%.result]%.json$'
local RESULT_SUFFIX = '.result.json'
local NS = vim.api.nvim_create_namespace 'CodexManualApply'
local ACTIVE = {}
local LAST_CLEARED = {}
local render_overlay

local function ensure_highlights()
  vim.api.nvim_set_hl(0, 'CodexManualApplyPending', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyMatch', { link = 'DiffAdd', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyMismatch', { link = 'DiagnosticError', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyDelete', { link = 'DiffDelete', default = true })
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

local function read_payload(payload_path)
  return read_json_file(payload_path)
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

  for i, line in ipairs(lines) do
    local old_start, old_count, new_start, new_count =
      line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

    if old_start then
      local parsed_old_count = parse_hunk_count(old_count)
      local parsed_new_count = parse_hunk_count(new_count)
      local target_lines = {}

      for body_index = i + 1, #lines do
        local body_line = lines[body_index]
        if vim.startswith(body_line, '@@ ') then
          break
        end

        if vim.startswith(body_line, ' ') then
          table.insert(target_lines, body_line:sub(2))
        elseif vim.startswith(body_line, '+') and not vim.startswith(body_line, '+++') then
          table.insert(target_lines, body_line:sub(2))
        end
      end

      local start_line = parsed_old_count == 0 and tonumber(new_start) or tonumber(old_start)
      return start_line or 1, parsed_old_count, target_lines
    end
  end

  return 1, 0, lines
end

local function result_path_for_payload(payload_path)
  return payload_path:gsub('%.json$', RESULT_SUFFIX)
end

local function write_result(payload_path, approval_id, status)
  local result_path = result_path_for_payload(payload_path)
  local payload = {
    schema_version = 1,
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

local function gen_diff_chunks(expected, typed)
  local chunks = {}
  local typed_len = #typed
  local matched = true
  local mismatch_ranges = {}

  if typed_len > 0 then
    local typed_chunks = {}

    for i = 1, math.min(#expected, typed_len) do
      local expected_char = expected:sub(i, i)
      local typed_char = typed:sub(i, i)
      local hl = expected_char == typed_char and 'CodexManualApplyMatch' or 'CodexManualApplyMismatch'
      local display_char = expected_char == typed_char and expected_char or typed_char

      if expected_char ~= typed_char then
        matched = false
        table.insert(mismatch_ranges, { i - 1, i })
        if display_char == ' ' then
          display_char = '_'
        end
      end

      local last = typed_chunks[#typed_chunks]
      if last and last[2] == hl then
        last[1] = last[1] .. display_char
      else
        table.insert(typed_chunks, { display_char, hl })
      end
    end

    chunks = typed_chunks
  end

  if typed_len < #expected then
    table.insert(chunks, { expected:sub(typed_len + 1), 'CodexManualApplyPending' })
    matched = false
  elseif typed_len > #expected then
    matched = false
    table.insert(mismatch_ranges, { #expected, typed_len })
  end

  return chunks, mismatch_ranges, matched and typed == expected
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

local function region_matches(buf, state)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local actual = vim.api.nvim_buf_get_lines(
    buf,
    state.start_row,
    math.min(state.start_row + #state.target_lines, line_count),
    false
  )

  if not lines_match(actual, state.target_lines) then
    return false
  end

  if state.trailing_anchor ~= nil then
    local anchor_row = state.start_row + #state.target_lines
    local anchor = vim.api.nvim_buf_get_lines(buf, anchor_row, anchor_row + 1, false)[1]
    return anchor == state.trailing_anchor
  end

  if state.expected_line_count ~= nil then
    return line_count == state.expected_line_count
  end

  return true
end

local function clear_overlay(buf, opts)
  opts = opts or {}
  local state = ACTIVE[buf]

  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end

  if state then
    LAST_CLEARED[buf] = vim.deepcopy(state)
    if opts.write_status and state.payload_path and state.approval_id and not state.result_written then
      if write_result(state.payload_path, state.approval_id, opts.write_status) then
        state.result_written = true
      end
    end
  end

  ACTIVE[buf] = nil
end

function M.clear_current()
  clear_overlay(vim.api.nvim_get_current_buf(), { write_status = 'completed' })
end

function M.restore_current()
  local buf = vim.api.nvim_get_current_buf()
  local state = LAST_CLEARED[buf]

  if not state or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  ACTIVE[buf] = vim.deepcopy(state)
  ensure_highlights()
  render_overlay(buf)
  return true
end

render_overlay = function(buf)
  local state = ACTIVE[buf]
  if not state or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local target_len = #state.target_lines
  local display_len = math.max(target_len, state.old_line_count)

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  for i = 1, display_len do
    local row = state.start_row + i - 1
    local expected = state.target_lines[i]

    if expected ~= nil then
      local typed = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      local chunks, mismatch_ranges = gen_diff_chunks(expected, typed)

      if #chunks > 0 then
        vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
          virt_text = chunks,
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
          priority = 200,
        })
      end

      for _, range in ipairs(mismatch_ranges) do
        vim.api.nvim_buf_set_extmark(buf, NS, row, range[1], {
          end_row = row,
          end_col = range[2],
          hl_group = 'CodexManualApplyMismatch',
          priority = 201,
        })
      end
    elseif row < line_count then
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
        end_row = row,
        end_col = #line,
        hl_group = 'CodexManualApplyDelete',
        priority = 200,
      })
      vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
        virt_text = { { ' delete line', 'CodexManualApplyDelete' } },
        virt_text_pos = 'eol',
        priority = 201,
      })
    end
  end

  if region_matches(buf, state) then
    if state.payload_path and state.approval_id and not state.result_written then
      if write_result(state.payload_path, state.approval_id, 'completed') then
        state.result_written = true
      else
        return
      end
    end
    clear_overlay(buf)
  end
end

local function attach_overlay(
  buf,
  start_row,
  old_line_count,
  target_lines,
  trailing_anchor,
  expected_line_count,
  payload_path,
  approval_id
)
  clear_overlay(buf)

  ACTIVE[buf] = {
    start_row = start_row,
    old_line_count = old_line_count,
    target_lines = target_lines,
    trailing_anchor = trailing_anchor,
    expected_line_count = expected_line_count,
    payload_path = payload_path,
    approval_id = approval_id,
    result_written = false,
  }

  ensure_highlights()
  render_overlay(buf)

  if vim.b[buf].codex_manual_apply_attached then
    return
  end

  vim.b[buf].codex_manual_apply_attached = true
  vim.keymap.set('n', '<leader>m', function()
    M.clear_current()
  end, {
    buffer = buf,
    silent = true,
    desc = 'Clear Codex manual apply overlay',
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

  local data, err = read_payload(payload_path)
  if not data then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  if data.kind ~= 'manual_patch_apply_request' or type(data.changes) ~= 'table' or type(data.changes[1]) ~= 'table' then
    notify('Payload is missing required manual-apply fields', vim.log.levels.ERROR)
    return false
  end

  if type(data.approval_id) ~= 'string' or data.approval_id == '' then
    notify('Payload is missing a valid approval_id', vim.log.levels.ERROR)
    return false
  end

  local change = data.changes[1]
  if type(change.path) ~= 'string' or change.path == '' then
    notify('Payload change is missing a valid target path', vim.log.levels.ERROR)
    return false
  end

  if vim.fn.filereadable(change.path) ~= 1 then
    notify('Target file does not exist: ' .. change.path, vim.log.levels.ERROR)
    return false
  end

  local diff = type(change.diff) == 'string' and change.diff or ''
  vim.cmd('edit ' .. vim.fn.fnameescape(change.path))

  local buf = vim.api.nvim_get_current_buf()
  local original_line_count = vim.api.nvim_buf_line_count(0)
  local start_line, old_line_count, target_lines = parse_diff(diff)
  start_line = math.max(1, math.min(start_line, original_line_count + 1))

  local start_row = start_line - 1
  local trailing_anchor = vim.api.nvim_buf_get_lines(buf, start_row + old_line_count, start_row + old_line_count + 1, false)[1]
  local expected_line_count = original_line_count - old_line_count + #target_lines
  local placeholder_count = math.max(#target_lines - old_line_count, 0)
  if placeholder_count > 0 then
    vim.api.nvim_buf_set_lines(buf, start_row, start_row, false, vim.fn['repeat']({ '' }, placeholder_count))
  end

  attach_overlay(
    buf,
    start_row,
    old_line_count,
    target_lines,
    trailing_anchor,
    expected_line_count,
    payload_path,
    data.approval_id
  )
  vim.api.nvim_win_set_cursor(0, { start_line, 0 })

  return true
end

return M
