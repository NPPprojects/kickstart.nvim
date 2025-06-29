return {
	"kevinhwang91/nvim-ufo",
	dependencies = { "kevinhwang91/promise-async" },
	config = function()
		-- Enable folding globally
		vim.o.foldcolumn = "1" -- Show fold markers
		vim.o.foldlevel = 99 -- Start with all folds open
		vim.o.foldlevelstart = 99
		vim.o.foldenable = true -- Enable folding

		require("ufo").setup({
			provider_selector = function(_, _, _)
				return { "treesitter", "indent" } -- Try treesitter first, then indent
			end,
		})
	end,
}
