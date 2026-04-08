return {
  'nvim-treesitter/nvim-treesitter',
  opts = function(_, opts)
    local query = require 'vim.treesitter.query'

    local register_opts = vim.fn.has 'nvim-0.10' == 1 and { force = true, all = false } or true

    local html_script_type_languages = {
      importmap = 'json',
      module = 'javascript',
      ['application/ecmascript'] = 'javascript',
      ['text/ecmascript'] = 'javascript',
    }

    local non_filetype_match_injection_language_aliases = {
      ex = 'elixir',
      pl = 'perl',
      sh = 'bash',
      uxn = 'uxntal',
      ts = 'typescript',
    }

    local function capture_node(match, capture_id)
      local node = match[capture_id]
      if type(node) == 'table' then
        return node[1]
      end
      return node
    end

    local function parser_from_markdown_info_string(alias)
      local match = vim.filetype.match { filename = 'a.' .. alias }
      return match or non_filetype_match_injection_language_aliases[alias] or alias
    end

    query.add_directive('set-lang-from-mimetype!', function(match, _, bufnr, pred, metadata)
      local node = capture_node(match, pred[2])
      if not node then
        return
      end

      local type_attr_value = vim.treesitter.get_node_text(node, bufnr)
      local configured = html_script_type_languages[type_attr_value]
      if configured then
        metadata['injection.language'] = configured
      else
        local parts = vim.split(type_attr_value, '/', {})
        metadata['injection.language'] = parts[#parts]
      end
    end, register_opts)

    query.add_directive('set-lang-from-info-string!', function(match, _, bufnr, pred, metadata)
      local capture_id = pred[2]
      local node = capture_node(match, capture_id)
      if not node then
        return
      end

      local injection_alias = vim.treesitter.get_node_text(node, bufnr):lower()
      metadata['injection.language'] = parser_from_markdown_info_string(injection_alias)
    end, register_opts)

    query.add_directive('downcase!', function(match, _, bufnr, pred, metadata)
      local capture_id = pred[2]
      local node = capture_node(match, capture_id)
      if not node then
        return
      end

      local text = vim.treesitter.get_node_text(node, bufnr, { metadata = metadata[capture_id] }) or ''
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id].text = string.lower(text)
    end, register_opts)

    return opts
  end,
}
