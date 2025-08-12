return {
	"folke/noice.nvim",
	dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
	opts = {
		messages = { enabled = false }, -- <— turn off Noice message UI
		cmdline = { view = "cmdline_popup" },
		views = {
			cmdline_popup = {
				position = { row = "50%", col = "50%" },
				size = { width = 60, height = "auto" },
			},
		},
		routes = {
			-- Show normal messages (incl. :! output) in a split, not a popup
			{ view = "notify", filter = { event = "msg_showmode" } },
		},
	},
}
