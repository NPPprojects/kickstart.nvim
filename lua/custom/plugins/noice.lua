return {
	"folke/noice.nvim",
	opts = {
		cmdline = {
			view = "cmdline_popup",
		},
		views = {
			cmdline_popup = {
				position = {
					row = "50%", -- vertical center
					col = "50%", -- horizontal center
				},
				size = {
					width = 60,
					height = "auto",
				},
			},
		},
	},
}
