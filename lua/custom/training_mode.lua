local M = {}

local function push(lines, text)
  lines[#lines + 1] = text
end

local function push_list(lines, items, empty_text)
  if type(items) ~= 'table' or vim.tbl_isempty(items) then
    push(lines, empty_text)
    return
  end

  for _, item in ipairs(items) do
    push(lines, '- ' .. item)
  end
end

local function grouped_items(training)
  local groups = {}
  local order = {}

  for _, item in ipairs(training.items or {}) do
    local key = item.path or '[general]'
    if not groups[key] then
      groups[key] = {}
      order[#order + 1] = key
    end
    groups[key][#groups[key] + 1] = item
  end

  return groups, order
end

function M.render_training_lines(payload)
  local lines = {}
  local training = payload.training or {}
  local groups, order = grouped_items(training)

  push(lines, '# Training Mode')
  push(lines, '')
  push(lines, 'Approval ID: ' .. payload.approval_id)
  push(lines, 'Working directory: ' .. payload.cwd)
  push(lines, 'Format: ' .. (training.format or 'unspecified'))
  if type(payload.reason) == 'string' and payload.reason ~= '' then
    push(lines, 'Reason: ' .. payload.reason)
  end
  push(lines, '')
  push(lines, '## Summary')
  push(lines, training.summary or '')

  if #order > 0 then
    push(lines, '')
    push(lines, '## Training Items')
  end

  for _, key in ipairs(order) do
    local label = key == '[general]' and 'General guidance' or key
    push(lines, '')
    push(lines, '### ' .. label)

    for index, item in ipairs(groups[key]) do
      push(lines, '')
      push(lines, string.format('%d. Intent: %s', index, item.intent))
      push(lines, 'Pseudocode:')
      push_list(lines, item.pseudocode, '- No pseudocode provided')
      push(lines, 'Hints:')
      push_list(lines, item.hints, '- No hints provided')
    end
  end

  if type(training.raw_text) == 'string' and training.raw_text ~= '' then
    push(lines, '')
    push(lines, '## Raw Training Notes')
    for _, line in ipairs(vim.split(training.raw_text, '\n', { plain = true })) do
      push(lines, line)
    end
  end

  return lines
end

function M.render_change_lines(payload)
  local lines = {}
  local changes = payload.changes or {}

  push(lines, '# Proposed Changes')

  if vim.tbl_isempty(changes) then
    push(lines, '')
    push(lines, 'No changes were included in this request.')
    return lines
  end

  for index, change in ipairs(changes) do
    push(lines, '')
    push(lines, string.format('## Change %d', index))
    push(lines, 'Path: ' .. change.path)
    push(lines, 'Kind: ' .. change.kind)
    if type(change.move_path) == 'string' and change.move_path ~= '' then
      push(lines, 'Move path: ' .. change.move_path)
    end
    push(lines, '')
    for _, line in ipairs(vim.split(change.diff or '', '\n', { plain = true })) do
      push(lines, line)
    end
  end

  return lines
end

return M
