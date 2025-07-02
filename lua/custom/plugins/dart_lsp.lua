-- ~/.config/nvim/lua/custom/plugins/dart-lsp.lua
return {
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			local lspconfig = require("lspconfig")

			lspconfig.dartls.setup({
				-- Optional: you can add settings here later
				-- cmd = {...}, root_dir = ..., etc.
			})
		end,
	},
}
