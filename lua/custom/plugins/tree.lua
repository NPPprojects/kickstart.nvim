return {
	{
		'nvim-tree/nvim-tree.lua',
		dependencies = { 'nvim-tree/nvim-web-devicons' },
		config = function()
			local api = require("nvim-tree.api")
			require("nvim-tree").setup({
				on_attach = function(bufnr)
					local function buf_map(lhs, rhs, desc)
						vim.keymap.set("n", lhs, rhs,
							{ buffer = bufnr, desc = "NvimTree: " .. desc })
					end

					-- Default mappings plus split overrides
					api.config.mappings.default_on_attach(bufnr)

					buf_map("v", api.node.open.vertical_no_picker, "Open in Vertical Split")
					buf_map("h", api.node.open.horizontal_no_picker, "Open in Horizontal Split")
				end,

				view = {
					mappings = {
						list = {}, -- no need to define here for splits
					},
				},

				actions = {
					open_file = {
						quit_on_open = false,
						window_picker = { enable = false },
					},
				},
			})

			vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>', { desc = 'Toggle NvimTree' })
		end,
	},
}
