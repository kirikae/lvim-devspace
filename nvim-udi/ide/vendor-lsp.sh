#!/bin/bash
# Install the language servers into the image. Runs once, at build time, as root.
#
# Two rules govern everything here:
#
#  1. Nothing may live under /home. A DevSpace with a persistent home mounts a
#     PVC over /home/user, and if that PVC is already populated — which is
#     exactly the "bring your own home directory" case this image is built for
#     — Che does NOT seed it from the image. Anything installed there simply
#     vanishes. That includes the UDI's own Node, which lives in
#     /home/user/.nvm, so this script vendors a private Node rather than
#     depending on it.
#
#  2. Wrappers invoke the vendored Node by absolute path. The npm shims in
#     node_modules/.bin start with `#!/usr/bin/env node`, which would resolve
#     back to whatever Node the user's PATH happens to point at — the very
#     dependency rule 1 exists to remove.
set -euo pipefail

ROOT=/opt/nvim-lsp
BIN="${ROOT}/bin"
NODE_DIR="${ROOT}/node"
NPM_DIR="${ROOT}/npm"

: "${NODE_VERSION:?}" "${LUA_LS_VERSION:?}" "${RUST_ANALYZER_VERSION:?}"
: "${MARKSMAN_VERSION:?}" "${GOPLS_VERSION:?}"
: "${NPM_PACKAGES:?}"

mkdir -p "${BIN}" "${NPM_DIR}"

case "$(uname -m)" in
    x86_64)  node_arch=x64;   luals_arch=linux-x64;   ra_arch=x86_64-unknown-linux-gnu;  marksman_arch=linux-x64  ;;
    aarch64) node_arch=arm64; luals_arch=linux-arm64; ra_arch=aarch64-unknown-linux-gnu; marksman_arch=linux-arm64 ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# --- Node -------------------------------------------------------------------
# Checksums come from the release's own SHASUMS256.txt rather than being pinned
# here, so the arch mapping above stays the only arch-specific thing to edit.
echo "==> node ${NODE_VERSION} (${node_arch})"
node_tar="node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"
curl -fsSL -o "/tmp/${node_tar}" "https://nodejs.org/dist/v${NODE_VERSION}/${node_tar}"
curl -fsSL -o /tmp/SHASUMS256.txt "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"
(cd /tmp && grep " ${node_tar}\$" SHASUMS256.txt | sha256sum -c -)
mkdir -p "${NODE_DIR}"
tar -xJf "/tmp/${node_tar}" -C "${NODE_DIR}" --strip-components=1
rm -f "/tmp/${node_tar}" /tmp/SHASUMS256.txt

# --- npm-based servers ------------------------------------------------------
echo "==> npm servers: ${NPM_PACKAGES}"
# --omit=dev keeps test fixtures and build tooling out of the image; the
# servers only need their runtime dependencies.
( cd "${NPM_DIR}" \
  && "${NODE_DIR}/bin/node" "${NODE_DIR}/bin/npm" install \
       --prefix "${NPM_DIR}" --omit=dev --no-audit --no-fund --loglevel=error \
       ${NPM_PACKAGES} )

# One wrapper per server executable, named exactly as nvim-lspconfig expects to
# find it on PATH, so no cmd overrides are needed in the Lua config.
for exe in bash-language-server yaml-language-server typescript-language-server \
           vscode-json-language-server vscode-css-language-server \
           vscode-html-language-server vscode-eslint-language-server \
           pyright-langserver; do
    target="${NPM_DIR}/node_modules/.bin/${exe}"
    if [[ ! -e "${target}" ]]; then
        echo "ERROR: npm did not provide ${exe}" >&2
        exit 1
    fi
    cat > "${BIN}/${exe}" <<EOF
#!/bin/sh
exec "${NODE_DIR}/bin/node" "${target}" "\$@"
EOF
    chmod 0755 "${BIN}/${exe}"
done

# --- lua-language-server ----------------------------------------------------
echo "==> lua-language-server ${LUA_LS_VERSION}"
mkdir -p "${ROOT}/lua-language-server"
curl -fsSL "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-${luals_arch}.tar.gz" \
  | tar -xz -C "${ROOT}/lua-language-server"
# lua-language-server resolves its own bundled Lua runtime relative to the
# binary, so it must be launched from its install directory, not symlinked.
#
# It also defaults to writing its log and metadata cache *inside* that install
# directory, which is root-owned and read-only for the workspace user: without
# --logpath/--metapath the server dies on startup with a create_directories
# permission error, and Neovim just reports "quit with exit code 1". Redirect
# both into the user's own state directory.
cat > "${BIN}/lua-language-server" <<EOF
#!/bin/sh
state="\${XDG_STATE_HOME:-\${HOME}/.local/state}/lua-language-server"
exec "${ROOT}/lua-language-server/bin/lua-language-server" \\
    --logpath="\${state}/log" \\
    --metapath="\${state}/meta" \\
    "\$@"
EOF
chmod 0755 "${BIN}/lua-language-server"

# --- gopls ------------------------------------------------------------------
echo "==> gopls ${GOPLS_VERSION}"
# The UDI's Go toolchain is in /usr/local, not /home, so it is safe to build
# with. GOPATH and the build caches are throwaway.
env GOPATH=/tmp/go GOCACHE=/tmp/gocache GOBIN="${BIN}" \
    /usr/local/go/bin/go install "golang.org/x/tools/gopls@${GOPLS_VERSION}"
rm -rf /tmp/go /tmp/gocache

# --- rust-analyzer ----------------------------------------------------------
echo "==> rust-analyzer ${RUST_ANALYZER_VERSION}"
curl -fsSL "https://github.com/rust-lang/rust-analyzer/releases/download/${RUST_ANALYZER_VERSION}/rust-analyzer-${ra_arch}.gz" \
  | gunzip > "${BIN}/rust-analyzer"
chmod 0755 "${BIN}/rust-analyzer"

# --- marksman ---------------------------------------------------------------
echo "==> marksman ${MARKSMAN_VERSION}"
curl -fsSL -o "${BIN}/marksman" \
    "https://github.com/artempyanykh/marksman/releases/download/${MARKSMAN_VERSION}/marksman-${marksman_arch}"
chmod 0755 "${BIN}/marksman"

# --- expose on PATH ---------------------------------------------------------
# /usr/local/bin is already on PATH for every shell and for Neovim's
# vim.fn.executable() checks, which is how the Lua config decides which servers
# to enable.
for f in "${BIN}"/*; do
    ln -sf "${f}" "/usr/local/bin/$(basename "${f}")"
done

chmod -R a+rX "${ROOT}"

# --- verify -----------------------------------------------------------------
# clangd comes from dnf (see the Containerfile) rather than an upstream release
# because LLVM publishes no aarch64 Linux build, and one install path for all
# architectures is worth more than a newer clangd.
echo "==> verifying servers are executable"
failed=()
for exe in bash-language-server yaml-language-server typescript-language-server \
           vscode-json-language-server vscode-css-language-server \
           vscode-html-language-server pyright-langserver \
           lua-language-server gopls rust-analyzer marksman clangd; do
    command -v "${exe}" >/dev/null 2>&1 || failed+=("${exe}: not on PATH")
done
if (( ${#failed[@]} > 0 )); then
    printf 'ERROR: %s\n' "${failed[@]}" >&2
    exit 1
fi

# A binary that is present but cannot start — wrong arch, missing shared
# library, broken wrapper — is worse than one that is absent, because the Lua
# config enables it and the failure only surfaces as a silent no-op in a
# workspace. Check the ones that support a cheap version query.
"${BIN}/lua-language-server" --version
"${BIN}/gopls" version
"${BIN}/rust-analyzer" --version
"${BIN}/marksman" --version
clangd --version
"${BIN}/bash-language-server" --version
"${BIN}/typescript-language-server" --version

echo "==> language servers vendored"
