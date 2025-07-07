return {
	"folke/noice.nvim",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"rcarriga/nvim-notify",
	},
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
		routes = {
			{
				view = "notify",
				filter = { event = "msg_showmode" }, -- show messages like "recording @q"
			},
		},
	},
}
