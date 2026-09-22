#!/bin/bash
# Compile the Tree-sitter parsers listed in parsers.txt into the image.
#
# Runs once, at image build time, as root. Everything lands under
# /usr/share/nvim/vendor so it survives a persistent /home/user being mounted
# over the top of the image's own home directory.
set -euo pipefail

VENDOR_DIR=/usr/share/nvim/vendor
PLUGIN_DIR="${VENDOR_DIR}/nvim-treesitter"
INSTALL_DIR="${VENDOR_DIR}/treesitter"
PARSER_LIST="${1:?usage: vendor-treesitter.sh <parsers.txt>}"

: "${NVIM_TREESITTER_REF:?NVIM_TREESITTER_REF must be set}"

# Root's Neovim must not write into /home/user — see the note in
# ../base/Containerfile about root-owned .local breaking the workspace user.
export HOME=/tmp/vendor-home
mkdir -p "${HOME}"

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

# Parsers are loaded by every user in the workspace; make them world-readable
# and strip the build-time revision bookkeeping.
chmod -R a+rX "${VENDOR_DIR}"
rm -rf "${HOME}"

echo "==> ${#LANGS[@]} parsers vendored"
