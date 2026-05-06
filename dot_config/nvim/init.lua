-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "

-- Options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.scrolloff = 8
vim.opt.wrap = false
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = false
vim.opt.signcolumn = "yes"
vim.opt.clipboard = "unnamedplus"

-- netrw (native file explorer)
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3

-- Keymaps
local map = function(lhs, rhs) vim.keymap.set("n", lhs, rhs, { silent = true }) end

map("<leader>e", ":Explore<CR>")
map("<Esc>",     ":nohlsearch<CR>")
map("<leader>v", "<C-w>v")
map("<leader>s", "<C-w>s")
map("<C-h>",     "<C-w>h")
map("<C-l>",     "<C-w>l")
map("<C-j>",     "<C-w>j")
map("<C-k>",     "<C-w>k")
map("<leader>ff", "<cmd>Telescope find_files<CR>")
map("<leader>fg", "<cmd>Telescope live_grep<CR>")
map("<leader>fb", "<cmd>Telescope buffers<CR>")

-- Plugins
require("lazy").setup({
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("telescope").setup({
        defaults = { file_ignore_patterns = { "node_modules", ".git" } },
      })
    end,
  },
})
