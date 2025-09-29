return {
	-- No external plugin needed, just native vim spell
	{
		"nvim-lua/plenary.nvim", -- dummy dep so lazy.nvim treats this as a module
		config = function()
			-- autocmd for spell checking in markdown, text, gp buffers
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "markdown", "text" },
				callback = function()
					vim.opt_local.spell = true
					vim.opt_local.spelllang = { "en_uk" }
				end,
			})
		end,
	},
}
