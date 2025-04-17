vim.g.mapleader = " "
vim.g.maplocalleader = ","
vim.cmd("set expandtab") -- converts tabs to spaces
vim.cmd("set tabstop=2") -- how many spaces are shown per tab
vim.cmd("set softtabstop=2") -- how many spacer are applied when you press tab
vim.cmd("set shiftwidth=2") -- Auto indent with >>
vim.cmd("set conceallevel=2")
vim.opt.smarttab = true
vim.opt.smartindent = true
vim.opt.autoindent = true
-- setting both line numbers to be true and displaying it in a staggered way
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.signcolumn = "number"
vim.opt.undofile = true -- stores undo history of file
vim.opt.showmode = false -- do not show modes in command line since it is already there in status line.

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

--enable finding all subfolders
vim.cmd("set path+=**")
vim.cmd("set wildmenu")

-- ignore case while searching, except when there is a uppercase
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- sign column for lsp
vim.opt.signcolumn = "yes"

vim.opt.cmdheight = 0
-- this will display certain whitespace characters like tabs and spaces
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

vim.opt.scrolloff = 10
