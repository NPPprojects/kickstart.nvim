return {
	'robitx/gp.nvim',
	config = function()
		require('gp').setup {
			agents = {
				{
					name = 'ChatGPT-4',
					chat = true,
					command = true,
					model = { model = 'gpt-4-turbo' },
					system_prompt = 'Answer my questions with confidence',
				},
			},
		}

		-- Multi-file paste helper


		-- Inside your plugin config block
		function PasteFilesToGpChat(files)
			local bufnr = vim.api.nvim_get_current_buf()
			local lang_map = {
				h = "c",
				cpp = "cpp",
				c = "c",
				py = "python",
				lua = "lua",
				js = "javascript",
				ts = "typescript",
				json = "json",
				html = "html",
				css = "css",
				sh = "bash",
				md = "markdown",
			}

			for _, file in ipairs(files) do
				if vim.fn.filereadable(file) == 1 then
					local lines = vim.fn.readfile(file)
					local ext = vim.fn.fnamemodify(file, ":e")
					local lang = lang_map[ext] or ext
					local block = {
						"", "---", "### " .. file, "{{{", "```" .. lang,
					}
					vim.list_extend(block, lines)
					table.insert(block, "```")
					table.insert(block, "}}}")
					vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, block)
				else
					print("File not found: " .. file)
				end
			end
		end

		vim.api.nvim_create_user_command("PasteFiles", function(opts)
			local files = vim.tbl_map(vim.fn.expand, opts.fargs)
			PasteFilesToGpChat(files)
		end, {
			nargs = "+",
			complete = "file",
			desc = "Paste one or more files into the GP buffer",
		})
	end,
}
