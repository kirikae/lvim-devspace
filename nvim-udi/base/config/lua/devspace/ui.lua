-- Appearance. No colourscheme is chosen here: Neovim's built-in default is
-- legible on both 256-colour and true-colour terminals, and picking something
-- else for someone is exactly the kind of decision a base image shouldn't make.

vim.opt.background = "dark"

-- netrw is the only file browser in the base image, so make it behave like
-- something you'd want to use rather than the 1990s default.
vim.g.netrw_banner = 0
vim.g.netrw_liststyle = 3
vim.g.netrw_winsize = 25

-- Statusline: path, modified/readonly flags, filetype, then the LSP and
-- diagnostic segments. Both stay empty on the base image and fill in by
-- themselves once the IDE layer attaches a language server, so the two images
-- share one statusline definition.
local function diagnostics()
  local parts = {}
  for label, severity in pairs({
    E = vim.diagnostic.severity.ERROR,
    W = vim.diagnostic.severity.WARN,
  }) do
    local n = #vim.diagnostic.get(0, { severity = severity })
    if n > 0 then
      table.insert(parts, ("%s%d"):format(label, n))
    end
  end
  table.sort(parts)
  return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
end

local function lsp_clients()
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    table.insert(names, client.name)
  end
  return #names > 0 and (" [" .. table.concat(names, ",") .. "]") or ""
end

function _G.devspace_statusline()
  return table.concat({
    " %f",
    "%m%r",
    "%=",
    "%y",
    lsp_clients(),
    diagnostics(),
    "  %l:%c  %P ",
  })
end

vim.opt.statusline = "%!v:lua.devspace_statusline()"
vim.opt.laststatus = 3
