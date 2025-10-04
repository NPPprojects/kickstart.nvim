return {
	"wfxr/minimap.vim",
	init = function()
		-- Default minimap settings
		vim.g.minimap_width = 10
		vim.g.minimap_auto_start = 0
		vim.g.minimap_auto_start_win_enter = 0

		-- Optional defaults (safe to keep)
		vim.g.minimap_block_filetypes = { "fugitive", "nerdtree", "tagbar", "fzf" }
		vim.g.minimap_block_buftypes = { "nofile", "nowrite", "quickfix", "terminal", "prompt" }
		vim.g.minimap_close_filetypes = { "startify", "netrw", "vim-plug" }
		vim.g.minimap_close_buftypes = {}

		-- Highlight settings
		vim.g.minimap_highlight_range = 1
		vim.g.minimap_highlight_search = 0
		vim.g.minimap_git_colors = 0
		vim.g.minimap_enable_highlight_colorgroup = 1
	end,
	cmd = { "Minimap", "MinimapToggle", "MinimapClose", "MinimapRefresh", "MinimapUpdateHighlight", "MinimapRescan" },
}
