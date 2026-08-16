return {
	'Salanoid/gitlogdiff.nvim',
	main = 'gitlogdiff',
	dependencies = {
		'sindrets/diffview.nvim',
	},
	cmd = 'GitLogDiff',
	opts = { max_count = 300 },
}
