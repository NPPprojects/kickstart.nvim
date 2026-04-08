local M = {}

local function read_json_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end

  local decode_ok, data = pcall(vim.fn.json_decode, table.concat(lines, '\n'))
  if not decode_ok or type(data) ~= 'table' then
    return nil
  end

  return data
end

local function is_codex_payload_path(path)
  if type(path) ~= 'string' then
    return false
  end

  if path:sub(- #'.result.json') == '.result.json' then
    return false
  end

  return path:match('^/tmp/xcodex%-manual%-apply%-.+%.json$') ~= nil
    or path:match('^/tmp/xcodex%-training%-mode%-.+%.json$') ~= nil
end

function M.module_for_payload(path)
  if not is_codex_payload_path(path) then
    return nil
  end

  local data = read_json_file(path)
  if not data or type(data.kind) ~= 'string' then
    return nil
  end

  if data.kind == 'manual_patch_apply_request' then
    return 'custom.manual_apply'
  end

  if data.kind == 'training_mode_request' then
    return 'custom.training_apply'
  end

  return nil
end

function M.run(path)
  local module_name = M.module_for_payload(path)
  if not module_name then
    return false
  end

  return require(module_name).run(path)
end

return M
