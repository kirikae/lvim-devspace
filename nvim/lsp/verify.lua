-- Build-time acceptance test for the IDE layer. Run by the final step of
-- ide/Containerfile as the workspace user, so it exercises the image the way a
-- DevSpace will.
--
-- This deliberately starts real language servers rather than checking that the
-- binaries exist. A server can be present on PATH, answer --version, and still
-- die the moment Neovim speaks to it — lua-language-server does exactly that
-- if its log and metadata directories aren't writable, and the only symptom is
-- a silent "no LSP" in the workspace. Catch it here instead.

local failures = {}

local function check(name, ok, detail)
  if not ok then
    failures[#failures + 1] = ("%s: %s"):format(name, detail or "failed")
  end
  io.write(("%-28s %s\n"):format(name, ok and "ok" or ("FAIL " .. (detail or ""))))
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
-- A .git directory is the root marker most servers fall back to.
vim.fn.mkdir(root .. "/.git", "p")
vim.fn.writefile({ "module example.com/m", "", "go 1.22" }, root .. "/go.mod")
vim.fn.writefile({ "{}" }, root .. "/package.json")

-- Every server the image claims to ship must attach to a buffer of its
-- language. Keep one representative file per server.
local cases = {
  { server = "lua_ls", file = "check.lua", lines = { "local x = 1" } },
  { server = "pyright", file = "check.py", lines = { "import os" } },
  { server = "gopls", file = "check.go", lines = { "package main", "", "func main() {}" } },
  { server = "bashls", file = "check.sh", lines = { "#!/bin/bash", "echo hi" } },
  { server = "yamlls", file = "check.yaml", lines = { "foo: bar" } },
  { server = "jsonls", file = "check.json", lines = { "{}" } },
  { server = "ts_ls", file = "check.ts", lines = { "const x: number = 1;" } },
  { server = "clangd", file = "check.c", lines = { "int main(void) { return 0; }" } },
  { server = "rust_analyzer", file = "check.rs", lines = { "fn main() {}" } },
  { server = "marksman", file = "check.md", lines = { "# Title" } },
  { server = "cssls", file = "check.css", lines = { "a { color: red; }" } },
  { server = "html", file = "check.html", lines = { "<!doctype html><title>t</title>" } },
}

for _, case in ipairs(cases) do
  local path = ("%s/%s"):format(root, case.file)
  vim.fn.writefile(case.lines, path)
  vim.cmd.edit(path)
  local buf = vim.api.nvim_get_current_buf()
  local attached = vim.wait(60000, function()
    for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
      if c.name == case.server then
        return true
      end
    end
    return false
  end, 200)
  local got = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    got[#got + 1] = c.name
  end
  check("lsp/" .. case.server, attached,
    ("did not attach to %s (clients: %s)"):format(case.file, table.concat(got, ",")))

  -- The parser must produce a real tree, which proves both the .so and the
  -- vendored queries are in place.
  local parser = vim.treesitter.get_parser(buf)
  local tree = parser and parser:parse()[1]
  check("treesitter/" .. vim.bo[buf].filetype, tree ~= nil and tree:root():child_count() >= 0,
    "no syntax tree")
end

-- Every language listed in parsers.txt should have loaded, not just the ones
-- with a matching test file above.
local parser_dir = "/usr/share/nvim/vendor/treesitter/parser"
local count = #vim.fn.readdir(parser_dir)
check("treesitter/parser count", count >= 35, ("only %d parsers in %s"):format(count, parser_dir))

check("lsp/enabled list", #(vim.g.devspace_lsp_servers or {}) == #cases,
  ("expected %d servers, got %d"):format(#cases, #(vim.g.devspace_lsp_servers or {})))

vim.fn.delete(root, "rf")

if #failures > 0 then
  io.write("\nFAILED:\n  " .. table.concat(failures, "\n  ") .. "\n")
  vim.cmd("cquit 1")
end
io.write("\nall checks passed\n")
