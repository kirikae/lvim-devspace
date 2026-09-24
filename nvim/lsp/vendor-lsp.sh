#!/bin/bash
# Install the language servers into the image. Runs once, at build time, as
# root, in the builder-lsp stage.
#
# Everything lands under /opt/nvim-lsp, which the lsp stage copies out as a
# single tree — so this script must leave that directory self-contained, with no
# dependency on anything else the builder happens to have installed.
#
# Two rules govern the layout:
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
#
# Every host it fetches from is an environment variable with an upstream
# default, so the whole thing can be pointed at a mirror. See the header of
# ../Containerfile.
set -euo pipefail

ROOT=/opt/nvim-lsp
BIN="${ROOT}/bin"
NODE_DIR="${ROOT}/node"
NPM_DIR="${ROOT}/npm"

: "${NODE_VERSION:?}" "${LUA_LS_VERSION:?}" "${RUST_ANALYZER_VERSION:?}"
: "${MARKSMAN_VERSION:?}" "${GOPLS_VERSION:?}"
: "${NPM_PACKAGES:?}"

GITHUB_RELEASES_URL="${GITHUB_RELEASES_URL:-https://github.com}"
NODEJS_DIST_URL="${NODEJS_DIST_URL:-https://nodejs.org/dist}"
NPM_REGISTRY_URL="${NPM_REGISTRY_URL:-https://registry.npmjs.org}"
export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"
export GOSUMDB="${GOSUMDB:-sum.golang.org}"
# A build argument with no default still arrives as an empty environment
# variable, which is not the same thing as "unset" to every tool that reads it.
# Empty here means "leave Go's own default alone".
if [[ -n "${GOTOOLCHAIN:-}" ]]; then
    export GOTOOLCHAIN
else
    unset GOTOOLCHAIN
fi

# The version checks at the bottom of this script run as root, and the
# lua-language-server wrapper writes its log and metadata under $HOME — which
# the UDI sets to /home/user. Left alone, root would create
# /home/user/.local/state/lua-language-server owned by root and mode 0755, and
# the workspace user could then neither write it at runtime nor delete it in
# the Containerfile's cleanup step. Same reasoning as vendor-treesitter.sh.
export HOME=/tmp/vendor-lsp-home
mkdir -p "${HOME}"

mkdir -p "${BIN}" "${NPM_DIR}"

case "$(uname -m)" in
    x86_64)  node_arch=x64;   luals_arch=linux-x64;   ra_arch=x86_64-unknown-linux-gnu;  marksman_arch=linux-x64  ;;
    aarch64) node_arch=arm64; luals_arch=linux-arm64; ra_arch=aarch64-unknown-linux-gnu; marksman_arch=linux-arm64 ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# --- Node -------------------------------------------------------------------
# Checksums come from the release's own SHASUMS256.txt rather than being pinned
# here, so the arch mapping above stays the only arch-specific thing to edit.
echo "==> node ${NODE_VERSION} (${node_arch}) from ${NODEJS_DIST_URL}"
node_tar="node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"
curl -fsSL -o "/tmp/${node_tar}" "${NODEJS_DIST_URL}/v${NODE_VERSION}/${node_tar}"
curl -fsSL -o /tmp/SHASUMS256.txt "${NODEJS_DIST_URL}/v${NODE_VERSION}/SHASUMS256.txt"
(cd /tmp && grep " ${node_tar}\$" SHASUMS256.txt | sha256sum -c -)
mkdir -p "${NODE_DIR}"
tar -xJf "/tmp/${node_tar}" -C "${NODE_DIR}" --strip-components=1
rm -f "/tmp/${node_tar}" /tmp/SHASUMS256.txt

# --- npm-based servers ------------------------------------------------------
echo "==> npm servers from ${NPM_REGISTRY_URL}: ${NPM_PACKAGES}"
# --omit=dev keeps test fixtures and build tooling out of the image; the
# servers only need their runtime dependencies.
( cd "${NPM_DIR}" \
  && "${NODE_DIR}/bin/node" "${NODE_DIR}/bin/npm" install \
       --prefix "${NPM_DIR}" --registry "${NPM_REGISTRY_URL}" \
       --omit=dev --no-audit --no-fund --loglevel=error \
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
curl -fsSL "${GITHUB_RELEASES_URL}/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-${luals_arch}.tar.gz" \
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
echo "==> gopls ${GOPLS_VERSION} via GOPROXY=${GOPROXY}"
# The UDI's Go toolchain is in /usr/local, not /home, so it is safe to build
# with. GOPATH and the build caches are throwaway.
env GOPATH=/tmp/go GOCACHE=/tmp/gocache GOBIN="${BIN}" \
    /usr/local/go/bin/go install "golang.org/x/tools/gopls@${GOPLS_VERSION}"
rm -rf /tmp/go /tmp/gocache

# --- rust-analyzer ----------------------------------------------------------
echo "==> rust-analyzer ${RUST_ANALYZER_VERSION}"
curl -fsSL "${GITHUB_RELEASES_URL}/rust-lang/rust-analyzer/releases/download/${RUST_ANALYZER_VERSION}/rust-analyzer-${ra_arch}.gz" \
  | gunzip > "${BIN}/rust-analyzer"
chmod 0755 "${BIN}/rust-analyzer"

# --- marksman ---------------------------------------------------------------
echo "==> marksman ${MARKSMAN_VERSION}"
curl -fsSL -o "${BIN}/marksman" \
    "${GITHUB_RELEASES_URL}/artempyanykh/marksman/releases/download/${MARKSMAN_VERSION}/marksman-${marksman_arch}"
chmod 0755 "${BIN}/marksman"

# --- trim -------------------------------------------------------------------
# npm itself, the C headers and the docs are build-time material: the wrappers
# above call node directly and nothing in a workspace runs `npm` out of this
# private runtime. Removing them here rather than in the Containerfile means
# they never enter the layer the lsp stage copies.
rm -rf "${NODE_DIR}/lib/node_modules/npm" \
       "${NODE_DIR}/lib/node_modules/corepack" \
       "${NODE_DIR}/bin/npm" "${NODE_DIR}/bin/npx" "${NODE_DIR}/bin/corepack" \
       "${NODE_DIR}/include" \
       "${NODE_DIR}/share"

# --- expose on PATH ---------------------------------------------------------
# /usr/local/bin is already on PATH for every shell and for Neovim's
# vim.fn.executable() checks, which is how the Lua config decides which servers
# to enable. The lsp stage recreates these links against the copied tree; they
# are made here so the verification below exercises the real PATH lookup.
for f in "${BIN}"/*; do
    ln -sf "${f}" "/usr/local/bin/$(basename "${f}")"
done

chmod -R a+rX "${ROOT}"

# --- verify -----------------------------------------------------------------
# clangd is not checked here: it comes from dnf in the lsp stage rather than
# from this script, because LLVM publishes no aarch64 Linux build and one
# install path for all architectures is worth more than a newer clangd.
# lsp/verify.lua covers it in the shipping image.
echo "==> verifying servers are executable"
failed=()
for exe in bash-language-server yaml-language-server typescript-language-server \
           vscode-json-language-server vscode-css-language-server \
           vscode-html-language-server pyright-langserver \
           lua-language-server gopls rust-analyzer marksman; do
    command -v "${exe}" >/dev/null 2>&1 || failed+=("${exe}: not on PATH")
done
if (( ${#failed[@]} > 0 )); then
    printf 'ERROR: %s\n' "${failed[@]}" >&2
    exit 1
fi

# A binary that is present but cannot start — wrong arch, missing shared
# library, broken wrapper — is worse than one that is absent, because the Lua
# config enables it and the failure only surfaces as a silent no-op in a
# workspace. Check the ones that support a cheap version query. This also
# catches an over-eager trim above: node is exercised by the two npm wrappers.
"${BIN}/lua-language-server" --version
"${BIN}/gopls" version
"${BIN}/rust-analyzer" --version
"${BIN}/marksman" --version
"${BIN}/bash-language-server" --version
"${BIN}/typescript-language-server" --version

rm -rf "${HOME}"

echo "==> language servers vendored into ${ROOT}"
