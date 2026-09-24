-- Editor defaults. Deliberately plugin-free: everything here is a built-in
-- option, so the base image starts instantly and can never break on an
-- upstream plugin change.

local o = vim.opt

-- Files and undo. undodir defaults to stdpath("state")/undo, which lives in
-- $HOME — so undo history persists across workspace restarts whenever the
-- DevSpace has a persistent home, and quietly doesn't when it doesn't.
o.undofile = true
o.swapfile = false
o.backup = false
o.updatetime = 250
o.timeoutlen = 400

-- Indentation: 2-space soft tabs, overridden per-filetype below and by any
-- .editorconfig in the project (Neovim honours those out of the box).
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.smartindent = true
o.shiftround = true

-- Search.
o.ignorecase = true
o.smartcase = true
o.incsearch = true
o.hlsearch = true

-- Display.
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.wrap = false
o.linebreak = true
o.scrolloff = 6
o.sidescrolloff = 8
o.splitright = true
o.splitbelow = true
o.showmode = false
o.termguicolors = false
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣", extends = "›", precedes = "‹" }
o.fillchars = { eob = " " }

-- True colour only when the terminal actually claims it. ttyd sets
-- COLORTERM=truecolor, but tmux drops it unless its own config opts in (see
-- the README). Guessing wrong here is what produces washed-out or invisible
-- text in a web terminal, so only turn it on when told.
if vim.env.COLORTERM == "truecolor" or vim.env.COLORTERM == "24bit" then
  o.termguicolors = true
end

-- Completion and diagnostics behaviour.
o.completeopt = { "menu", "menuone", "noselect", "popup" }
o.pumheight = 12
o.confirm = true
o.mouse = "a"

-- Clipboard over OSC 52. There is no X display in a DevSpace container, so the
-- only way a yank can reach the laptop's clipboard is for the terminal
-- emulator to carry it — which ttyd/xterm.js does. Paste deliberately reads
-- the unnamed register rather than issuing an OSC 52 read: browsers almost
-- universally refuse the read, and nvim would block waiting for a reply that
-- never comes.
local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
if ok then
  local function paste()
    return vim.split(vim.fn.getreg('"'), "\n")
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
  o.clipboard = "unnamedplus"
end

-- Ask the built-in grep to use ripgrep, which the image installs.
if vim.fn.executable("rg") == 1 then
  o.grepprg = "rg --vimgrep --smart-case"
  o.grepformat = "%f:%l:%c:%m"
end

vim.diagnostic.config({
  severity_sort = true,
  virtual_text = { spacing = 2, prefix = "●" },
  float = { border = "rounded", source = true },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "E",
      [vim.diagnostic.severity.WARN] = "W",
      [vim.diagnostic.severity.INFO] = "I",
      [vim.diagnostic.severity.HINT] = "H",
    },
  },
})
