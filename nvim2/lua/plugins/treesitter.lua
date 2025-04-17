return
{
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function () 
      local configs = require("nvim-treesitter.configs")

      configs.setup({
          sync_install = false,
          auto_install = true,
          highlight = { enable = true },
          indent = { enable = true },  
          incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = "<Enter><Enter>", -- set to `false` to disable one of the mappings
      node_incremental = "<Enter><Enter>",
      scope_incremental = false,
      node_decremental = "<Enter><Backspace>",
    },
        }})
    end
}

