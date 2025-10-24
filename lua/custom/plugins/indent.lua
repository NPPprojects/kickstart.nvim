return {
	require('guess-indent').setup {
		auto_cmd = true,
		filetype_exclude = { 'make' }, -- Makefiles need tabs
		buftype_exclude = { 'help', 'nofile', 'terminal', 'prompt' },
		override = {
			expandtab = true, -- force spaces
		},
	}
}
