-- Autocommands, all in one augroup so a user config that opts in via
-- dofile() can drop the lot with a single nvim_del_augroup_by_name("devspace").

local group = vim.api.nvim_create_augroup("devspace", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  desc = "Briefly highlight yanked text",
  callback = function()
    vim.hl.on_yank({ timeout = 150 })
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
  desc = "Restore the last cursor position",
  callback = function(ev)
    -- Skip commit messages: reopening one should start at the top.
    if vim.bo[ev.buf].filetype:match("^git") then
      return
    end
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  desc = "Per-language indentation for languages that insist",
  pattern = { "go", "make", "gitconfig" },
  callback = function()
    vim.bo.expandtab = false
    vim.bo.shiftwidth = 8
    vim.bo.tabstop = 8
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  desc = "4-space indentation where that is the community norm",
  pattern = { "python", "rust", "java", "c", "cpp" },
  callback = function()
    vim.bo.shiftwidth = 4
    vim.bo.softtabstop = 4
    vim.bo.tabstop = 4
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  desc = "Close scratch windows with q",
  pattern = { "help", "qf", "man", "checkhealth", "lspinfo" },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = ev.buf, silent = true })
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  group = group,
  desc = "Create missing parent directories on write",
  callback = function(ev)
    if ev.match:match("^%w%w+://") then
      return
    end
    vim.fn.mkdir(vim.fn.fnamemodify(ev.match, ":p:h"), "p")
  end,
})

vim.api.nvim_create_autocmd("VimResized", {
  group = group,
  desc = "Rebalance splits when the terminal is resized",
  command = "tabdo wincmd =",
})
