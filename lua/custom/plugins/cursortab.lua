return {

	"cursortab/cursortab.nvim",
	-- version = "*",  -- Use latest tagged version for more stability
	lazy = false, -- The server is already lazy loaded
	build = "cd server && go build",
	config = function()
		require("cursortab").setup({
			provider = {
				-- Mercury API (hosted)
				--type = "mercuryapi",

				--api_key_env = "MERCURY_AI_TOKEN",

				-- Zeta-2 (best local)
				type = "zeta-2",
				url = "http://127.0.0.1:8001",

				-- Qwen3.5-0.8B (fastest local, defaults to "inline")
				-- url = "http://localhost:8000",

				-- sweep-next-edit-0.5B/1.5B (fastest local)
				-- type = "sweep",
				-- url = "http://localhost:8000",
			},
		})
	end,
}
