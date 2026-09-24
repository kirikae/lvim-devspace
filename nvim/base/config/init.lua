-- System-wide Neovim config for the nvim-udi DevSpaces image.
--
-- Neovim sources exactly ONE init file: $XDG_CONFIG_HOME/nvim/init.lua if that
-- exists, otherwise the first one found under $XDG_CONFIG_DIRS (here,
-- /etc/xdg). So a workspace whose persistent home carries its own
-- ~/.config/nvim takes over completely and this file is never read — which is
-- the whole point. Nothing in the image has to be unpicked first.
--
-- To build *on top of* these defaults rather than replace them, start your own
-- ~/.config/nvim/init.lua with:
--
--     dofile("/etc/xdg/nvim/init.lua")

vim.g.devspace_config = "/etc/xdg/nvim"

require("devspace.options")
require("devspace.keymaps")
require("devspace.ui")
require("devspace.autocmds")

-- Drop-in layer. Images built on top of nvim-udi-base (nvim-udi-ide is the one
-- in this repo) add their own files here instead of patching the modules
-- above, so a layer can be added or dropped without rewriting the base config.
-- Sorted by filename, so the NN- prefixes control ordering.
for _, file in ipairs(vim.fn.globpath("/etc/xdg/nvim/devspace.d", "*.lua", false, true)) do
  local ok, err = pcall(dofile, file)
  if not ok then
    vim.notify(("devspace.d: %s: %s"):format(vim.fs.basename(file), err), vim.log.levels.WARN)
  end
end
