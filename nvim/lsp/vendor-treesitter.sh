#!/bin/bash
# Compile the Tree-sitter parsers listed in parsers.txt into the image.
#
# Runs once, at image build time, as root, in the builder-lsp stage. Everything
# lands under /usr/share/nvim/vendor, which the lsp stage copies out wholesale —
# so this script must leave that tree, and only that tree, in a finished state.
#
# /usr/share rather than /home/user is deliberate: a DevSpace with a persistent
# home mounts a PVC over /home/user and anything the image put there disappears.
set -euo pipefail

VENDOR_DIR=/usr/share/nvim/vendor
PLUGIN_DIR="${VENDOR_DIR}/nvim-treesitter"
INSTALL_DIR="${VENDOR_DIR}/treesitter"
PARSER_LIST="${1:?usage: vendor-treesitter.sh <parsers.txt>}"

: "${NVIM_TREESITTER_REF:?NVIM_TREESITTER_REF must be set}"
GITHUB_REPOS_URL="${GITHUB_REPOS_URL:-https://github.com}"
# Where the 40 grammar source archives come from. Separate from
# GITHUB_REPOS_URL because these are fetched by curl as
# <url>/archive/<rev>.tar.gz, not cloned — a git mirror does not necessarily
# serve them. Same host upstream, so it defaults to following GITHUB_REPOS_URL.
TREESITTER_GRAMMAR_URL="${TREESITTER_GRAMMAR_URL:-}"
: "${TREESITTER_GRAMMAR_URL:=${GITHUB_REPOS_URL}}"

# Root's Neovim must not write into /home/user — see the note in the base stage
# of ../Containerfile about root-owned .local breaking the workspace user.
export HOME=/tmp/vendor-home
mkdir -p "${HOME}"

# The clone URL is the canonical one on purpose: /etc/gitconfig carries a
# url.<mirror>.insteadOf rule, so a mirror is honoured here without this script
# knowing about it.
echo "==> cloning nvim-treesitter @ ${NVIM_TREESITTER_REF}"
git clone --quiet --filter=blob:none \
    https://github.com/nvim-treesitter/nvim-treesitter "${PLUGIN_DIR}"
git -C "${PLUGIN_DIR}" checkout --quiet "${NVIM_TREESITTER_REF}"
# The git metadata is a good fraction of the plugin's size and nothing reads it
# at runtime; record the pin as a plain file instead.
echo "${NVIM_TREESITTER_REF}" > "${PLUGIN_DIR}/.vendored-ref"
rm -rf "${PLUGIN_DIR}/.git" "${PLUGIN_DIR}/tests"

mapfile -t LANGS < <(grep -vE '^\s*(#|$)' "${PARSER_LIST}")
echo "==> compiling ${#LANGS[@]} parsers into ${INSTALL_DIR}"

# nvim-treesitter's install() is async and returns a task; -l runs the script
# with an event loop, and wait() blocks until every parser is done. Without the
# wait the build would exit while compilers are still running.
LANGS_LUA="$(printf '"%s",' "${LANGS[@]}")"
cat > /tmp/vendor-treesitter.lua <<LUA
vim.opt.runtimepath:prepend("${PLUGIN_DIR}")
local nts = require("nvim-treesitter")
nts.setup({ install_dir = "${INSTALL_DIR}" })

-- Grammar sources. Each parser carries its own upstream URL in
-- nvim-treesitter's parser table, and install() fetches it with curl as
-- <url>/archive/<revision>.tar.gz. That is not a git operation, so the
-- url.<mirror>.insteadOf rule in /etc/gitconfig does NOT apply to it and the
-- URLs have to be rewritten here instead.
--
-- This fails the build rather than warning: a mirror that silently did not
-- apply means every grammar below is about to be fetched from the internet,
-- which on the network this argument exists for is a long timeout rather than a
-- useful error.
local mirror = "${TREESITTER_GRAMMAR_URL}"
if mirror ~= "" and mirror ~= "https://github.com" then
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if not ok then
    error("a grammar mirror is set but nvim-treesitter.parsers could not be loaded")
  end
  local rewritten = 0
  for _, cfg in pairs(parsers) do
    local info = type(cfg) == "table" and cfg.install_info or nil
    if type(info) == "table" and type(info.url) == "string" then
      -- A function replacement, not a string: gsub reads %1 and friends out of
      -- a string replacement, and a mirror URL is allowed to contain a percent.
      local url, n = info.url:gsub("^https://github%.com", function()
        return mirror
      end)
      if n > 0 then
        info.url = url
        rewritten = rewritten + 1
      end
    end
  end
  if rewritten == 0 then
    error("a grammar mirror is set but no grammar URLs were rewritten")
  end
  print(("==> rewrote %d grammar URLs to %s"):format(rewritten, mirror))
end

local requested = { ${LANGS_LUA} }

-- install() ignores names it doesn't recognise and still reports success, so a
-- typo — or an alias like "jsonc", which is a filetype rather than a grammar —
-- would otherwise produce an image quietly missing a language. Check the names
-- against the plugin's own list first and fail with a usable message.
local available = {}
for _, lang in ipairs(require("nvim-treesitter.config").get_available()) do
  available[lang] = true
end
local unknown = {}
for _, lang in ipairs(requested) do
  if not available[lang] then
    unknown[#unknown + 1] = lang
  end
end
if #unknown > 0 then
  error("not tree-sitter grammars: " .. table.concat(unknown, ", "))
end

if nts.install(requested, { summary = true }):wait(1800000) == false then
  error("tree-sitter parser installation reported failure")
end
LUA
nvim --headless -l /tmp/vendor-treesitter.lua
rm -f /tmp/vendor-treesitter.lua

# install() logs failures per-language but still succeeds overall, so verify
# every requested parser actually produced a .so rather than trusting the exit
# code. A silently missing parser would show up much later as "no highlighting
# for X" in a workspace, which is a miserable thing to debug.
missing=()
for lang in "${LANGS[@]}"; do
    [[ -f "${INSTALL_DIR}/parser/${lang}.so" ]] || missing+=("${lang}")
done
if (( ${#missing[@]} > 0 )); then
    echo "ERROR: parsers failed to build: ${missing[*]}" >&2
    exit 1
fi

# Parsers are loaded by every user in the workspace; make them world-readable.
chmod -R a+rX "${VENDOR_DIR}"
rm -rf "${HOME}"

echo "==> ${#LANGS[@]} parsers vendored"
