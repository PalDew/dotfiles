vim.g.mapleader = " "
vim.g.maplocalleader = ","
vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.cmd("set conceallevel=2")
-- setting both line numbers to be true and displaying it in a staggered way
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.signcolumn = 'number'

--buffer navigation
vim.keymap.set("n","<leader>wq",":w!<CR>")

---line wrapping disable
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.whichwrap:append("<,>,[,],b,s")

---enable sync with keyboard
-- Needs xclip clipboard to be installed
vim.opt.clipboard = "unnamedplus"

-- to help the virtual edit mode. Remove the limitation.
vim.opt.virtualedit = "block"

vim.opt.termguicolors = true
vim.cmd("syntax on")
vim.cmd("filetype plugin on")
vim.cmd("filetype indent on")

-- select colorscheme
vim.api.nvim_command("colorscheme lunaperche")

-- soft line wrapping

--enable finding all subfolders
vim.cmd("set path+=**")
vim.cmd("set wildmenu")

-- enable netrw forcefully
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
