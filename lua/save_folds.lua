-- lua/save_folds.lua

local M = {}

function M.setup()
	-- Save folds and cursor position automatically
	vim.opt.viewoptions = { "cursor", "folds", "slash", "unix" }

	vim.api.nvim_create_autocmd("BufWinLeave", {
		pattern = "*",
		command = "mkview",
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		pattern = "*",
		command = "silent! loadview",
	})
end

return M
