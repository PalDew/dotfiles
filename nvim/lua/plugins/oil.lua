return {
  "stevearc/oil.nvim",
  config = function()
    local oil = require("oil")
    oil.setup({show_hidden = true,
    is_hidden_file = function(name, bufnr)
      return vim.startswith(name, ".")
    end,})
    vim.keymap.set("n", "<C-n>", oil.toggle_float, {})
  end,
}
