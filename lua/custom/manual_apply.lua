local M = {}

local PAYLOAD_PATTERN = '^/tmp/xcodex%-manual%-apply%-.+%.json$'
local NS = vim.api.nvim_create_namespace 'CodexManualApply'
local ACTIVE = {}
local LAST_CLEARED = {}
local render_overlay

local function ensure_highlights()
  vim.api.nvim_set_hl(0, 'CodexManualApplyPending', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyMatch', { link = 'DiffAdd', default = true })
  vim.api.nvim_set_hl(0, 'CodexManualApplyMismatch', { link = 'DiagnosticError', default = true })
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Codex Manual Apply' })
end

local function read_payload(payload_path)
  local ok, lines = pcall(vim.fn.readfile, payload_path)
  if not ok then
    return nil, 'Failed to read payload file: ' .. payload_path
  end

  local content = table.concat(lines, '\n')
  local decode_ok, data = pcall(vim.fn.json_decode, content)
  if not decode_ok or type(data) ~= 'table' then
    return nil, 'Invalid JSON payload: ' .. payload_path
  end

  return data
end

local function split_lines(text)
  if text == '' then
    return {}
  end

  return vim.split(text, '\n', { plain = true })
end

local function parse_diff(diff)
  local start_line = tonumber(diff:match('@@ %-%d+,?%d* %+(%d+),?%d* @@')) or 1
  local added_lines = {}

  for _, line in ipairs(split_lines(diff)) do
    if vim.startswith(line, '+++') then
    elseif vim.startswith(line, '+') then
      table.insert(added_lines, line:sub(2))
    end
  end

  if #added_lines > 0 then
    return start_line, added_lines
  end

  return start_line, split_lines(diff)
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

local function clear_overlay(buf)
  local state = ACTIVE[buf]
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end
  if state then
    LAST_CLEARED[buf] = vim.deepcopy(state)
  end
  ACTIVE[buf] = nil
end

function M.clear_current()
  clear_overlay(vim.api.nvim_get_current_buf())
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
  local all_matched = true

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  for i, expected in ipairs(state.lines) do
    local row = state.start_row + i - 1
    if row >= line_count then
      all_matched = false
      break
    end

    local typed = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
    local chunks, mismatch_ranges, matched = gen_diff_chunks(expected, typed)
    all_matched = all_matched and matched

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
  end

  if all_matched then
    clear_overlay(buf)
  end
end

local function attach_overlay(buf, start_row, lines)
  clear_overlay(buf)

  ACTIVE[buf] = {
    start_row = start_row,
    lines = lines,
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
  return type(path) == 'string' and path:match(PAYLOAD_PATTERN) ~= nil
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
  local start_line, added_lines = parse_diff(diff)
  if #added_lines == 0 then
    added_lines = { '' }
  end

  vim.cmd('edit ' .. vim.fn.fnameescape(change.path))

  local buf = vim.api.nvim_get_current_buf()
  local line_count = vim.api.nvim_buf_line_count(0)
  start_line = math.max(1, math.min(start_line, line_count + 1))
  vim.api.nvim_buf_set_lines(buf, start_line - 1, start_line - 1, false, vim.fn['repeat']({ '' }, #added_lines))
  attach_overlay(buf, start_line - 1, added_lines)
  vim.api.nvim_win_set_cursor(0, { start_line, 0 })

  return true
end

return M
