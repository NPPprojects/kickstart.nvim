return {
	"nvim-flutter/flutter-tools.nvim",
	lazy = false,

	dependencies = {
		"nvim-lua/plenary.nvim",
		"stevearc/dressing.nvim",
	},

	config = function()
		require("flutter-tools").setup({
			ui = {
				border = "rounded",
				notification_style = "native",
			},

			decorations = {
				statusline = { app_version = true, device = true },
			},

			widget_guides = { enabled = true },
			outline = { open_cmd = "30vnew" },

			lsp = {
				-- IMPORTANT:
				-- Do NOT provide on_attach or capabilities, Kickstart handles that.
				--
				color = { enabled = true, background = true },
				settings = {
					showTodos = true,
					renameFilesWithClasses = "prompt",
					updateImportsOnRename = true,
				},
			},

			debugger = {
				enabled = true,
				run_via_dap = true,
			},

			dev_tools = {
				autostart = false,
				auto_open_browser = false,
			},
		})
	end,
}
