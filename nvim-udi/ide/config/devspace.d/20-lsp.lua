-- Language servers.
--
-- Neovim 0.11+ resolves server configurations from `lsp/<name>.lua` anywhere
-- on 'runtimepath', so vendoring nvim-lspconfig is enough to get correct
-- commands, root markers and settings — no plugin manager, no setup calls, and
-- nothing fetched at runtime. Completion and the usual keymaps are built in
-- too, which is why this layer ships two vendored plugins rather than a dozen.

local LSPCONFIG_DIR = "/usr/share/nvim/vendor/nvim-lspconfig"

if vim.uv.fs_stat(LSPCONFIG_DIR) then
  vim.opt.runtimepath:append(LSPCONFIG_DIR)
end

-- server name -> the executable nvim-lspconfig expects on PATH. Servers whose
-- executable is missing are never enabled, so this file stays correct if the
-- image is rebuilt with a shorter server list.
local SERVERS = {
  bashls = "bash-language-server",
  clangd = "clangd",
  cssls = "vscode-css-language-server",
  gopls = "gopls",
  html = "vscode-html-language-server",
  jsonls = "vscode-json-language-server",
  lua_ls = "lua-language-server",
  marksman = "marksman",
  pyright = "pyright-langserver",
  rust_analyzer = "rust-analyzer",
  ts_ls = "typescript-language-server",
  yamlls = "yaml-language-server",
}

-- Configuring Lua for Neovim development specifically: without this, editing
-- anything under ~/.config/nvim produces an "undefined global vim" warning on
-- every line.
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
      diagnostics = { globals = { "vim" } },
    },
  },
})

local enabled = {}
for name, exe in pairs(SERVERS) do
  if vim.fn.executable(exe) == 1 then
    enabled[#enabled + 1] = name
  end
end
table.sort(enabled)

-- Recorded so `:lua =vim.g.devspace_lsp_servers` and :checkhealth tell you what
-- the image actually shipped with.
vim.g.devspace_lsp_servers = enabled
vim.lsp.enable(enabled)

local group = vim.api.nvim_create_augroup("devspace-lsp", { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  desc = "Buffer-local LSP setup",
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then
      return
    end

    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = "LSP: " .. desc })
    end

    -- Neovim already maps grn (rename), gra (code action), grr (references),
    -- gri (implementation), gO (symbols) and K (hover), so only the gaps are
    -- filled in here.
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("gy", vim.lsp.buf.type_definition, "Go to type definition")
    map("<leader>f", function()
      vim.lsp.buf.format({ async = true })
    end, "Format buffer")

    if client:supports_method("textDocument/inlayHint") then
      map("<leader>h", function()
        local filter = { bufnr = ev.buf }
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled(filter), filter)
      end, "Toggle inlay hints")
    end

    -- Built-in completion, triggered as you type. This is the piece that would
    -- otherwise need nvim-cmp or blink plus a handful of dependencies.
    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end

    -- Highlight other occurrences of the symbol under the cursor.
    if client:supports_method("textDocument/documentHighlight") then
      local hl_group = vim.api.nvim_create_augroup("devspace-lsp-highlight", { clear = false })
      vim.api.nvim_clear_autocmds({ group = hl_group, buffer = ev.buf })
      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        group = hl_group,
        buffer = ev.buf,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = hl_group,
        buffer = ev.buf,
        callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})
