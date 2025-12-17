return {
	"NvChad/nvim-colorizer.lua",
	event = "BufReadPre",
	config = function()
		require("colorizer").setup({
			lua = { rgb_fn = true },
			conf = { rgb_fn = true },
			toml = { rgb_fn = true },
			"*",
		}, {
			mode = "background",
		})
	end,
}
