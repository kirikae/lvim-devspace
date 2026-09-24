-- Tree-sitter, from parsers compiled into the image at build time.
--
-- Loaded by /etc/xdg/nvim/init.lua, so it applies on a fresh workspace and is
-- skipped entirely once the user has their own ~/.config/nvim.

local PLUGIN_DIR = "/usr/share/nvim/vendor/nvim-treesitter"
local VENDOR_PARSERS = "/usr/share/nvim/vendor/treesitter"

if not vim.uv.fs_stat(VENDOR_PARSERS) then
  return
end

-- The vendored parsers and queries only need to be on 'runtimepath' for
-- vim.treesitter to find them; the plugin itself is a build-time tool.
vim.opt.runtimepath:append(VENDOR_PARSERS)

-- Keeping the plugin available means :TSInstall still works for a language
-- that wasn't vendored. Point its install directory at the user's own data
-- directory: /usr/share is root-owned, and anything installed at runtime
-- should belong to the workspace anyway. setup() prepends that directory to
-- 'runtimepath', so user-installed parsers take precedence over vendored ones.
if vim.uv.fs_stat(PLUGIN_DIR) then
  vim.opt.runtimepath:append(PLUGIN_DIR)
  pcall(function()
    require("nvim-treesitter").setup({
      install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site"),
    })
  end)
end

-- Filetypes that have no grammar of their own but parse correctly with
-- another. Neovim only maps help and checkhealth by default.
vim.treesitter.language.register("json", { "jsonc" })
vim.treesitter.language.register("bash", { "zsh", "sh" })

local group = vim.api.nvim_create_augroup("devspace-treesitter", { clear = true })

-- Above this size, Tree-sitter's initial parse is slow enough to be felt on
-- every keystroke. Minified bundles and vendored blobs are the usual culprits,
-- and syntax highlighting is not what anyone opens those for.
local MAX_FILESIZE = 512 * 1024

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  desc = "Start Tree-sitter highlighting where a parser is available",
  callback = function(ev)
    local size = vim.uv.fs_stat(vim.api.nvim_buf_get_name(ev.buf))
    if size and size.size > MAX_FILESIZE then
      return
    end
    -- Fails for any filetype with no vendored parser, which is expected and
    -- not worth a message: those buffers keep regex syntax highlighting.
    if not pcall(vim.treesitter.start, ev.buf) then
      return
    end
    -- Folds follow the syntax tree, but stay open until explicitly asked for.
    vim.wo[0][0].foldmethod = "expr"
    vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
    vim.wo[0][0].foldenable = false
  end,
})
