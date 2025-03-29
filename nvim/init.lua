local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out,                            "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("vim-options")
require("lazy").setup({
  spec = { { import = "plugins" } } })



-- This is how the above code works:
-- If you want to specify a variable, you can either do it the normal way. Like a = 2
-- by default, this is a global variable in lua.
-- That is why we mark them as local.
--
-- In line 1, the lazypath is a local variable. It is available only within the file.
-- vim.fn is a bridge between vim scripting language and lua
-- The standard path function is calling the path of data variable. Using :echo stdpath("data") will tell you where lazy stores the data
-- The .. operator is string concatenation. It write the path To stdpath("data")/lazy/lazy.nvim
--
-- Line 2
-- If there is no path returned that lazy demands.
-- Then git clone from the repository, to the lazypath variable.
-- If that operation fails, display failed to clone lazy.
--
-- Line 15 is the run time path.
-- This is the path that neovim will check for things like syntax highlighting, or auto-completion, etc.
-- All the things required by the plugin, will be searched by the lazy.
-- rtp returns an aray of strings.
--
-- Line 18 and 19 look for other lua files and folders.
