-- lua/save_folds.lua

local M = {}

function M.setup()
	vim.opt.viewoptions = { "cursor", "folds", "slash", "unix" }

	vim.api.nvim_create_autocmd("BufWinLeave", {
		pattern = "*",
		callback = function()
			local bufname = vim.api.nvim_buf_get_name(0)
			if bufname ~= "" and vim.bo.buftype == "" then
				vim.cmd("mkview")
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		pattern = "*",
		callback = function()
			local bufname = vim.api.nvim_buf_get_name(0)
			if bufname ~= "" and vim.bo.buftype == "" then
				vim.cmd("silent! loadview")
			end
		end,
	})
end

return M -- ← THIS must exist!
