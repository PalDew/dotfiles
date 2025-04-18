return {
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = "cd app && npm install",
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
		ft = { "markdown" },
	},

	-- The following is an alternative to the above plugin. Directly renders text in browser.
	--	{
	--		"brianhuster/live-preview.nvim",
	--		dependencies = {
	--			"ibhagwan/fzf-lua",
	--		},
	--	},
}
