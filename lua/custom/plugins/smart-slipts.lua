return
{
	'mrjones2014/smart-splits.nvim',
	config = function()
		require('smart-splits').setup({
			default_amount = 5,
			ignored_filetypes = { 'NvimTree', 'toggleterm' },
		})
	end
}
