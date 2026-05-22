return {
	{
		'cursortab/cursortab.nvim',
		lazy = false,
		build = 'cd server && go build',
		config = function()
			-- CursorTab's daemon can keep headless Neovim alive.
			if #vim.api.nvim_list_uis() == 0 then
				return
			end

			require('cursortab').setup {
				provider = {
					type = 'mercuryapi',
					api_key_env = 'MERCURY_AI_TOKEN',
				},
				blink = {
					enabled = true,
					ghost_text = false,
				},
			}
		end,
	},
}
