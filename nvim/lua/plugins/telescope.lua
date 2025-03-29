return {
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>af", builtin.find_files, {})
      vim.keymap.set("n", "<leader>gf", builtin.live_grep, {})
      vim.keymap.set("n", "<leader>bf", builtin.buffers, {})
      vim.keymap.set("n", "<leader>gif", builtin.git_files, {})
      vim.keymap.set("n", "<leader>of", builtin.oldfiles, {})
    end,
  },
  {
    "nvim-telescope/telescope-ui-select.nvim",
    config = function()
      require("telescope").setup({
        extensions = { ["ui-select"] = { require("telescope.themes").get_dropdown({}) } },
      })
      require("telescope").load_extension("ui-select")
    end,
  },
}
