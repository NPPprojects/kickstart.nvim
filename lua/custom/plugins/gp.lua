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

		function PasteFilesToGpChat(files)
			local bufnr = vim.api.nvim_get_current_buf()

			-- Manual extension-to-language mapping
			local lang_map = {
				h = "c", -- assume C for .h
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
					local joined = table.concat(lines, '\n')

					local ext = vim.fn.fnamemodify(file, ':e')
					local lang = lang_map[ext] or ext -- fallback to ext itself if unknown

					local block = {
						'',
						'---',
						'### ' .. file,
						'{{{',
						'```' .. lang,
					}

					vim.list_extend(block, vim.split(joined, '\n'))
					table.insert(block, '```')
					table.insert(block, '}}}')

					vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, block)
				else
					print('File not found: ' .. file)
				end
			end
		end
	end,
}
