local M = {}

local RESULT_SUFFIX = '.result.json'
local ANCHOR_NS = vim.api.nvim_create_namespace 'CodexTrainingApplyAnchors'
local RENDER_NS = vim.api.nvim_create_namespace 'CodexTrainingApplyRender'
local ACTIVE = {}
local training_mode = require 'custom.training_mode'

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Codex Training Mode' })
end

local function ensure_highlights()
  vim.api.nvim_set_hl(0, 'CodexTrainingApplyHeader', { link = 'Title', default = true })
  vim.api.nvim_set_hl(0, 'CodexTrainingApplyBorder', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'CodexTrainingApplyDone', { link = 'DiffAdd', default = true })
  vim.api.nvim_set_hl(0, 'CodexTrainingApplyFailed', { link = 'DiagnosticError', default = true })
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

local function result_path_for_payload(payload_path)
  local result_path = payload_path:gsub('%.json$', RESULT_SUFFIX)
  return result_path
end

local function write_result(payload_path, approval_id, status)
  local payload = {
    schema_version = 1,
    kind = 'training_mode_result',
    approval_id = approval_id,
    status = status,
  }

  local encoded = vim.fn.json_encode(payload)
  local ok, err = pcall(vim.fn.writefile, vim.split(encoded, '\n', { plain = true }), result_path_for_payload(payload_path))
  if not ok then
    notify('Failed to write result file: ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

local function delete_result(payload_path)
  local result_path = result_path_for_payload(payload_path)
  if vim.fn.filereadable(result_path) == 1 then
    vim.fn.delete(result_path)
  end
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
    local old_start, old_count, new_start, new_count = line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

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

local function synthesize_add_hunks(diff)
  local lines = split_lines(diff)
  local hunk = {
    old_start = 1,
    old_count = 0,
    new_start = 1,
    new_count = #lines,
    lines = {},
  }

  for _, line in ipairs(lines) do
    hunk.lines[#hunk.lines + 1] = { kind = 'add', text = line }
  end

  return { hunk }
end

local function parse_change_hunks(change)
  local diff = type(change.diff) == 'string' and change.diff or ''
  local parsed_hunks, parse_err = parse_diff(diff)
  if parsed_hunks then
    return parsed_hunks
  end

  if change.kind == 'add' then
    return synthesize_add_hunks(diff)
  end

  return nil, parse_err
end

local function ensure_hunk_analysis(hunk)
  if hunk.analysis then
    return hunk.analysis
  end

  local old_lines = {}
  local prefix_context = 0
  local suffix_context = 0

  for _, entry in ipairs(hunk.lines) do
    if entry.kind ~= 'add' then
      old_lines[#old_lines + 1] = entry.text
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
  local tracked_old_lines = {}

  if tracked_old_start <= tracked_old_end then
    tracked_old_lines = vim.list_slice(old_lines, tracked_old_start, tracked_old_end)
  end

  hunk.analysis = {
    old_lines = old_lines,
    prefix_context = prefix_context,
    suffix_context = suffix_context,
    tracked_old_lines = tracked_old_lines,
    hint_row = math.max(hunk.old_start - 1 + prefix_context, 0),
  }

  return hunk.analysis
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

local function sort_hunks(hunks)
  table.sort(hunks, function(a, b)
    if a.old_start == b.old_start then
      return a.old_count < b.old_count
    end
    return a.old_start < b.old_start
  end)
end

local function validate_changes(changes)
  if type(changes) ~= 'table' then
    return nil, 'Payload is missing required change data'
  end

  for _, change in ipairs(changes) do
    if type(change) ~= 'table' then
      return nil, 'Payload change must be a table'
    end
    if type(change.path) ~= 'string' or change.path == '' then
      return nil, 'Payload change is missing a valid target path'
    end
    if change.kind ~= 'add' and change.kind ~= 'delete' and change.kind ~= 'update' then
      return nil, 'Payload change has an invalid kind'
    end
    if change.move_path ~= nil and type(change.move_path) ~= 'string' then
      return nil, 'Payload change has an invalid move_path'
    end
    if type(change.diff) ~= 'string' then
      return nil, 'Payload change is missing a diff string'
    end
  end

  return changes
end

local function validate_training(data)
  if type(data.approval_id) ~= 'string' or data.approval_id == '' then
    return nil, 'Payload is missing a valid approval_id'
  end

  if type(data.cwd) ~= 'string' or data.cwd == '' then
    return nil, 'Payload is missing a valid cwd'
  end

  local changes, change_err = validate_changes(data.changes)
  if not changes then
    return nil, change_err
  end

  if type(data.training) ~= 'table' then
    return nil, 'Payload is missing training data'
  end

  local training = data.training
  if training.format ~= nil and type(training.format) ~= 'string' then
    return nil, 'Training format must be a string or null'
  end
  if type(training.summary) ~= 'string' then
    return nil, 'Training summary must be a string'
  end
  if type(training.items) ~= 'table' then
    return nil, 'Training items must be an array'
  end
  if training.raw_text ~= nil and type(training.raw_text) ~= 'string' then
    return nil, 'Training raw_text must be a string or null'
  end

  for _, item in ipairs(training.items) do
    if type(item) ~= 'table' then
      return nil, 'Training item must be a table'
    end
    if item.path ~= nil and type(item.path) ~= 'string' then
      return nil, 'Training item path must be a string or null'
    end
    if type(item.intent) ~= 'string' then
      return nil, 'Training item intent must be a string'
    end
    if type(item.pseudocode) ~= 'table' then
      return nil, 'Training item pseudocode must be an array'
    end
    if type(item.hints) ~= 'table' then
      return nil, 'Training item hints must be an array'
    end
  end

  return {
    approval_id = data.approval_id,
    cwd = data.cwd,
    reason = data.reason,
    changes = changes,
    training = training,
  }
end

local function set_scratch_buffer(buf, name, filetype, lines)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.bo[buf].filetype = filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

local function focus_or_vsplit_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      return true
    end
  end

  vim.cmd 'vsplit'
  vim.api.nvim_win_set_buf(0, buf)
  return true
end

local function get_mark_row(buf, mark_id)
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ANCHOR_NS, mark_id, {})
  if not pos or not pos[1] then
    return nil
  end

  return pos[1]
end

local function clear_code_render(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, RENDER_NS, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf, ANCHOR_NS, 0, -1)
  end
end

local function render_code_overlay(state)
  local buf = state.code_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  clear_code_render(buf)

  local status_text = 'pending'
  local status_group = 'CodexTrainingApplyHeader'
  if state.result_status == 'completed' then
    status_text = 'completed'
    status_group = 'CodexTrainingApplyDone'
  elseif state.result_status == 'failed' or state.result_status == 'cancelled' then
    status_text = state.result_status
    status_group = 'CodexTrainingApplyFailed'
  end

  for _, hunk in ipairs(state.hunks) do
    local start_row = get_mark_row(buf, hunk.start_mark)
    local end_row = get_mark_row(buf, hunk.end_mark)
    if start_row ~= nil and end_row ~= nil then
      vim.api.nvim_buf_set_extmark(buf, RENDER_NS, start_row, 0, {
        virt_lines = {
          {
            { string.format('training target %d/%d [%s]', hunk.index, #state.hunks, status_text), status_group },
          },
          {
            { string.rep('─', 40), 'CodexTrainingApplyBorder' },
          },
        },
        virt_lines_above = true,
        priority = 180,
      })

      vim.api.nvim_buf_set_extmark(buf, RENDER_NS, math.max(end_row, start_row), 0, {
        virt_lines = {
          {
            { string.rep('─', 40), 'CodexTrainingApplyBorder' },
          },
        },
        priority = 180,
      })
    end
  end
end

local function undo_training_decision(buf)
  local state = ACTIVE[buf]
  if not state or not state.result_status then
    return false
  end

  delete_result(state.payload_path)
  state.result_status = nil
  render_code_overlay(state)
  notify('Reverted training mode decision')
  return true
end

local function write_decision(buf, status)
  local state = ACTIVE[buf]
  if not state then
    return false, 'No active training-mode session in this buffer'
  end

  if not write_result(state.payload_path, state.approval_id, status) then
    return false, 'Failed to write training-mode result file'
  end

  state.result_status = status
  render_code_overlay(state)
  notify('Training mode marked ' .. status)
  return true
end

local function attach_buffer(buf)
  if vim.b[buf].codex_training_apply_attached then
    return
  end

  vim.b[buf].codex_training_apply_attached = true

  vim.api.nvim_buf_create_user_command(buf, 'CodexTrainingModeComplete', function()
    local ok, err = write_decision(buf, 'completed')
    if not ok then
      notify(err, vim.log.levels.ERROR)
    end
  end, { desc = 'Mark Codex training mode as completed' })

  vim.api.nvim_buf_create_user_command(buf, 'CodexTrainingModeFail', function()
    local ok, err = write_decision(buf, 'failed')
    if not ok then
      notify(err, vim.log.levels.ERROR)
    end
  end, { desc = 'Mark Codex training mode as failed' })

  vim.api.nvim_buf_create_user_command(buf, 'CodexTrainingModeCancel', function()
    local ok, err = write_decision(buf, 'cancelled')
    if not ok then
      notify(err, vim.log.levels.ERROR)
    end
  end, { desc = 'Mark Codex training mode as cancelled' })

  vim.keymap.set('n', '<leader>ta', function()
    vim.cmd.CodexTrainingModeComplete()
  end, {
    buffer = buf,
    silent = true,
    desc = 'Complete Codex training mode session',
  })

  vim.keymap.set('n', '<leader>tf', function()
    vim.cmd.CodexTrainingModeFail()
  end, {
    buffer = buf,
    silent = true,
    desc = 'Fail Codex training mode session',
  })

  vim.keymap.set('n', '<leader>tb', function()
    local state = ACTIVE[buf]
    if not state or not focus_or_vsplit_buffer(state.guide_buf) then
      notify('Training notes buffer is unavailable', vim.log.levels.ERROR)
    end
  end, {
    buffer = buf,
    silent = true,
    desc = 'Show Codex training notes buffer',
  })

  vim.keymap.set('n', '<leader>td', function()
    local state = ACTIVE[buf]
    if not state or not focus_or_vsplit_buffer(state.diff_buf) then
      notify('Training diff buffer is unavailable', vim.log.levels.ERROR)
    end
  end, {
    buffer = buf,
    silent = true,
    desc = 'Show Codex training diff buffer',
  })

  vim.keymap.set('n', 'u', function()
    if undo_training_decision(buf) then
      return
    end

    vim.cmd.normal { 'u', bang = true }
  end, {
    buffer = buf,
    silent = true,
    desc = 'Undo training decision or buffer edit',
  })

  vim.api.nvim_buf_attach(buf, false, {
    on_detach = function(_, detached_buf)
      ACTIVE[detached_buf] = nil
      vim.b[detached_buf].codex_training_apply_attached = nil
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

  return path:match('^/tmp/xcodex%-training%-mode%-.+%.json$') ~= nil
end

function M.can_handle_payload(path)
  if not M.is_payload_path(path) then
    return false
  end

  local data = read_json_file(path)
  return data and data.kind == 'training_mode_request' or false
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

  if data.kind ~= 'training_mode_request' then
    notify('Payload is missing required training-mode fields', vim.log.levels.ERROR)
    return false
  end

  local validated, validate_err = validate_training(data)
  if not validated then
    notify(validate_err, vim.log.levels.ERROR)
    return false
  end

  local target_path = validated.changes[1].path
  if vim.fn.filereadable(target_path) ~= 1 then
    notify('Target file does not exist: ' .. target_path, vim.log.levels.ERROR)
    return false
  end

  local all_hunks = {}
  for _, change in ipairs(validated.changes) do
    if change.path == target_path then
      local parsed_hunks, parse_err = parse_change_hunks(change)
      if not parsed_hunks then
        notify(parse_err, vim.log.levels.ERROR)
        return false
      end

      for _, hunk in ipairs(parsed_hunks) do
        all_hunks[#all_hunks + 1] = hunk
      end
    end
  end

  sort_hunks(all_hunks)

  vim.cmd 'tabnew'
  local guide_buf = vim.api.nvim_create_buf(false, true)
  local diff_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, guide_buf)
  set_scratch_buffer(
    guide_buf,
    string.format('codex://training/%s/guide', validated.approval_id),
    'markdown',
    training_mode.render_training_lines(validated)
  )
  vim.wo.wrap = true
  vim.wo.linebreak = true

  set_scratch_buffer(
    diff_buf,
    string.format('codex://training/%s/diff', validated.approval_id),
    'diff',
    training_mode.render_change_lines(validated)
  )

  vim.cmd('vsplit ' .. vim.fn.fnameescape(target_path))
  local code_buf = vim.api.nvim_get_current_buf()

  local lines = vim.api.nvim_buf_get_lines(code_buf, 0, -1, false)
  local min_row = 0
  local hunks = {}

  for index, hunk in ipairs(all_hunks) do
    local range = locate_hunk_range(lines, hunk, min_row)
    if range.start_row < min_row then
      notify('Overlapping hunks are not supported in training mode', vim.log.levels.ERROR)
      return false
    end

    local start_mark = vim.api.nvim_buf_set_extmark(code_buf, ANCHOR_NS, range.start_row, 0, { right_gravity = false })
    local end_mark = vim.api.nvim_buf_set_extmark(code_buf, ANCHOR_NS, range.end_row, 0, { right_gravity = true })
    hunks[#hunks + 1] = {
      index = index,
      start_mark = start_mark,
      end_mark = end_mark,
    }

    min_row = math.max(range.end_row, range.start_row)
  end

  ensure_highlights()

  local state = {
    payload_path = payload_path,
    approval_id = validated.approval_id,
    guide_buf = guide_buf,
    diff_buf = diff_buf,
    code_buf = code_buf,
    target_path = target_path,
    hunks = hunks,
    result_status = nil,
  }

  ACTIVE[guide_buf] = state
  ACTIVE[diff_buf] = state
  ACTIVE[code_buf] = state

  attach_buffer(guide_buf)
  attach_buffer(diff_buf)
  attach_buffer(code_buf)
  render_code_overlay(state)

  vim.cmd 'wincmd h'
  notify('Opened training mode session')
  return true
end

function M._debug_state(buf)
  local state = ACTIVE[buf or vim.api.nvim_get_current_buf()]
  if not state then
    return nil
  end

  local extmarks = vim.api.nvim_buf_get_extmarks(state.code_buf, RENDER_NS, 0, -1, { details = true })
  return {
    approval_id = state.approval_id,
    guide_buf = state.guide_buf,
    diff_buf = state.diff_buf,
    code_buf = state.code_buf,
    target_path = state.target_path,
    hunk_count = #state.hunks,
    result_status = state.result_status,
    render_extmark_count = #extmarks,
  }
end

return M
