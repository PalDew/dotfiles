return {
	"ibhagwan/fzf-lua",
	-- optional for icon support
	dependencies = { "echasnovski/mini.icons" },
	opts = {},
	keys = {
		{
			"<leader>af",
			function()
				require("fzf-lua").files()
			end,
			desc = "find files in current directory",
		},
		{
			"<leader>gf",
			function()
				require("fzf-lua").live_grep_native()
			end,
			desc = "Live grep in current directory",
		},
		{
			"<leader>bf",
			function()
				require("fzf-lua").buffers()
			end,
			desc = "Buffer Search",
		},
		{
			"<leader>cf",
			function()
				require("fzf-lua").files({ cwd = vim.fn.stdpath("config") })
			end,
			desc = "Seach Configuration Files",
		},
		{
			"<leader>bif",
			function()
				require("fzf-lua").builtin()
			end,
			desc = "Builtin Fzf finder commands",
		},
	},
}
