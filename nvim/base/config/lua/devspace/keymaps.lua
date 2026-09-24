-- Keymaps. Kept small on purpose — this is a base image someone else's config
-- may sit on top of, so it claims as little of the keyspace as it can get away
-- with and leaves <leader> largely free.

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local map = vim.keymap.set

-- Space is the leader, so make sure it does nothing on its own.
map({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

-- Clear search highlight without clobbering <Esc> in other modes.
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Files and buffers.
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write buffer" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "Close window" })
map("n", "<leader>e", "<cmd>Explore<CR>", { desc = "File explorer (netrw)" })
map("n", "<leader>b", "<cmd>buffers<CR>:buffer<Space>", { desc = "Switch buffer" })
map("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })

-- Window navigation. <C-h/j/k/l> is the near-universal choice and matches the
-- tmux pane bindings most people already have, so the two nest sensibly.
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })

-- Keep the cursor put while joining and centred while paging.
map("n", "J", "mzJ`z", { desc = "Join lines, keep cursor" })
map("n", "<C-d>", "<C-d>zz", { desc = "Half page down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Half page up" })

-- Move the selection around in visual mode.
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Reindent without losing the selection.
map("v", "<", "<gv", { desc = "Outdent" })
map("v", ">", ">gv", { desc = "Indent" })

-- Diagnostics. Neovim 0.11+ already maps ]d / [d, so only the float is added.
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>D", vim.diagnostic.setloclist, { desc = "Diagnostics to loclist" })

-- Terminal: let <Esc> get you back to normal mode instead of into the shell's
-- own escape handling.
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Leave terminal mode" })
