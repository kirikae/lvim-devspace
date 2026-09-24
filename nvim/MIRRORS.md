# Mirror manifest

Every remote artifact this build fetches, at the pins currently set in
[`Containerfile`](Containerfile). This is the list you hand to whoever
populates an internal mirror, and the thing to re-read when a pin moves.

It is excluded from the build context by [`.dockerignore`](.dockerignore): it
documents the build, it is never read by it. Nothing here is a second source of
truth — every version below is quoted from a `Containerfile` `ARG`, and the
build fails loudly rather than silently reaching upstream if a redirect does not
apply.

**Totals:** 1 container image · 2 git repositories · 8 release assets (4
artifacts × 2 architectures) · 38 grammar source archives · 2 Node files · 2
package ecosystems.

## How a mirror is addressed

Each build argument is a **base URL**; the path below it must match upstream
byte for byte. A path-preserving reverse proxy or artifact repository is
therefore sufficient, and no argument ever needs a per-artifact override.

| Build argument | Default | Path appended below it |
| --- | --- | --- |
| `BASE_IMAGE` | `quay.io/devfile/universal-developer-image:ubi9-latest` | — (a full image reference) |
| `GITHUB_REPOS_URL` | `https://github.com` | `/<org>/<repo>` |
| `GITHUB_RELEASES_URL` | `https://github.com` | `/<org>/<repo>/releases/download/<tag>/<asset>` |
| `TREESITTER_GRAMMAR_URL` | follows `GITHUB_REPOS_URL` | `/<org>/<repo>/archive/<revision>.tar.gz` |
| `NODEJS_DIST_URL` | `https://nodejs.org/dist` | `/v<version>/<file>` |
| `NPM_REGISTRY_URL` | `https://registry.npmjs.org` | a registry API |
| `GOPROXY` | `https://proxy.golang.org,direct` | a module proxy |
| `GOSUMDB` | `sum.golang.org` | a checksum database (`off` to disable) |

There are three GitHub arguments rather than one because three different
mechanisms fetch from GitHub, and a redirect for one does not apply to the
others. See **Why three GitHub arguments** at the end.

---

## 1. Container image

Pulled by `FROM`, so it must be in a registry the builder can reach.

| Image |
| --- |
| `quay.io/devfile/universal-developer-image:ubi9-latest` |

---

## 2. Git repositories — `GITHUB_REPOS_URL`

Cloned with `git clone`. Redirected by a `url.<mirror>.insteadOf` rule written
into `/etc/gitconfig` in the `base` stage, so the clone commands keep their
canonical URLs and submodules follow the same redirect.

A blobless clone (`--filter=blob:none`) is used, so the mirror must be a real
git remote, not a tarball service.

| Repository | Ref | `ARG` |
| --- | --- | --- |
| `https://github.com/nvim-treesitter/nvim-treesitter` | `f603a2f4da48728f80257fb5fbb90145fd1dc173` | `NVIM_TREESITTER_REF` |
| `https://github.com/neovim/nvim-lspconfig` | `v2.11.0` | `NVIM_LSPCONFIG_REF` |

---

## 3. Release assets — `GITHUB_RELEASES_URL`

Fetched with `curl`. Both architectures are listed; a build fetches only the one
it is running on, but a mirror serving both is what makes the `Containerfile`
usable on either.

| Path below the base URL | `ARG` |
| --- | --- |
| `/neovim/neovim/releases/download/v0.12.5/nvim-linux-x86_64.tar.gz` | `NEOVIM_VERSION` |
| `/neovim/neovim/releases/download/v0.12.5/nvim-linux-arm64.tar.gz` | `NEOVIM_VERSION` |
| `/LuaLS/lua-language-server/releases/download/3.19.1/lua-language-server-3.19.1-linux-x64.tar.gz` | `LUA_LS_VERSION` |
| `/LuaLS/lua-language-server/releases/download/3.19.1/lua-language-server-3.19.1-linux-arm64.tar.gz` | `LUA_LS_VERSION` |
| `/rust-lang/rust-analyzer/releases/download/2026-09-21/rust-analyzer-x86_64-unknown-linux-gnu.gz` | `RUST_ANALYZER_VERSION` |
| `/rust-lang/rust-analyzer/releases/download/2026-09-21/rust-analyzer-aarch64-unknown-linux-gnu.gz` | `RUST_ANALYZER_VERSION` |
| `/artempyanykh/marksman/releases/download/2026-02-08/marksman-linux-x64` | `MARKSMAN_VERSION` |
| `/artempyanykh/marksman/releases/download/2026-02-08/marksman-linux-arm64` | `MARKSMAN_VERSION` |

The two Neovim tarballs are additionally checksummed against
`NEOVIM_SHA256_X86_64` / `NEOVIM_SHA256_ARM64`, so a mirror serving the wrong
bytes fails the build rather than shipping.

---

## 4. Tree-sitter grammar archives — `TREESITTER_GRAMMAR_URL`

**Not git.** nvim-treesitter fetches each grammar with `curl` as
`<repo url>/archive/<revision>.tar.gz`, so the `insteadOf` rule in section 2
does not apply — these URLs are rewritten in
[`lsp/vendor-treesitter.sh`](lsp/vendor-treesitter.sh) instead. The mirror must
serve GitHub's repository-archive endpoint, or `TREESITTER_GRAMMAR_URL` must
point somewhere that does.

The revisions are pinned by nvim-treesitter at `f603a2f4da48728f80257fb5fbb90145fd1dc173`, not by
this repository, so **this table changes whenever `NVIM_TREESITTER_REF` moves**.
Regenerate it with the command at the end of this file.

38 repositories, 41 parsers. Languages marked † are not in
[`lsp/parsers.txt`](lsp/parsers.txt) — they are additional grammars built from a
repository that is already being fetched for something else.

| Repository (below the base URL) | Revision | Languages |
| --- | --- | --- |
| `camdencheek/tree-sitter-dockerfile` | `971acdd908568b4531b0ba28a445bf0bb720aba5` | dockerfile |
| `camdencheek/tree-sitter-go-mod` | `2e886870578eeba1927a2dc4bd2e2b3f598c5f9a` | gomod |
| `derekstride/tree-sitter-sql` | `39fdb006403747241244326e8af3b3e96b85381c` | sql |
| `flurie/tree-sitter-jq` | `c204e36d2c3c6fce1f57950b12cabcc24e5cc4d9` | jq |
| `gbprod/tree-sitter-gitcommit` | `55a265cf763ec15d6e2d96bb206e3f5e30d82bae` | gitcommit |
| `Joakker/tree-sitter-json5` | `248b8564567087d7866be76569b182f6dd7e14e9` | json5 |
| `justinmk/tree-sitter-ini` | `e4018b5176132b4f3c5d6e61cea383f42288d0f5` | ini |
| `MichaHoffmann/tree-sitter-hcl` | `64ad62785d442eb4d45df3a1764962dafd5bc98b` | terraform |
| `neovim/tree-sitter-vimdoc` | `23daa416c1ff5d15f59a1aa648f031d6e3ee15c5` | vimdoc |
| `omertuc/tree-sitter-go-work` | `949a8a470559543857a62102c84700d291fc984c` | gowork |
| `shunsambongi/tree-sitter-gitignore` | `f4685bf11ac466dd278449bcfe5fd014e94aa504` | gitignore |
| `the-mikedavis/tree-sitter-git-config` | `3a61756a81a86291a0f48e3eeeaa0692b9981aa9` | git_config |
| `the-mikedavis/tree-sitter-git-rebase` | `32686d6b72980b36f876ae2d07719c9c3ed154e2` | git_rebase |
| `tree-sitter-grammars/tree-sitter-diff` | `ada384ac7bfc1307f32de474620120add29998fb` | diff |
| `tree-sitter-grammars/tree-sitter-go-sum` | `27816eb6b7315746ae9fcf711e4e1396dc1cf237` | gosum |
| `tree-sitter-grammars/tree-sitter-hcl` | `64ad62785d442eb4d45df3a1764962dafd5bc98b` | hcl |
| `tree-sitter-grammars/tree-sitter-lua` | `10fe0054734eec83049514ea2e718b2a56acd0c9` | lua |
| `tree-sitter-grammars/tree-sitter-luadoc` | `4d04632a3a398b78af52e83be074883e722f40be` | luadoc |
| `tree-sitter-grammars/tree-sitter-make` | `70613f3d812cbabbd7f38d104d60a409c4008b43` | make |
| `tree-sitter-grammars/tree-sitter-markdown` | `a0a00f817d02412bd92c54d316f164d827b57b5c` | markdown, markdown_inline |
| `tree-sitter-grammars/tree-sitter-query` | `8e9e223812ff30854fbc912adbec696ba5f0e023` | query |
| `tree-sitter-grammars/tree-sitter-toml` | `64b56832c2cffe41758f28e05c756a3a98d16f41` | toml |
| `tree-sitter-grammars/tree-sitter-vim` | `039c8d0aa1deae00ddeb0374dd70bcc0ec56938d` | vim |
| `tree-sitter-grammars/tree-sitter-xml` | `5000ae8f22d11fbe93939b05c1e37cf21117162d` | dtd †, xml |
| `tree-sitter-grammars/tree-sitter-yaml` | `a1c4812a73ec5e089de8e441fdea3a921e8d5079` | yaml |
| `tree-sitter/tree-sitter-bash` | `a06c2e4415e9bc0346c6b86d401879ffb44058f7` | bash |
| `tree-sitter/tree-sitter-c` | `b780e47fc780ddc8da13afa35a3f4ed5c157823d` | c |
| `tree-sitter/tree-sitter-cpp` | `c009222808634c1014f82438d4883753516a2c24` | cpp |
| `tree-sitter/tree-sitter-css` | `dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f` | css |
| `tree-sitter/tree-sitter-go` | `2346a3ab1bb3857b48b29d779a1ef9799a248cd7` | go |
| `tree-sitter/tree-sitter-html` | `73a3947324f6efddf9e17c0ea58d454843590cc0` | html |
| `tree-sitter/tree-sitter-java` | `e10607b45ff745f5f876bfa3e94fbcc6b44bdc11` | java |
| `tree-sitter/tree-sitter-javascript` | `58404d8cf191d69f2674a8fd507bd5776f46cb11` | javascript |
| `tree-sitter/tree-sitter-json` | `254c42a6476413b776221e03982ac8ae159eeb72` | json |
| `tree-sitter/tree-sitter-python` | `v0.25.0` | python |
| `tree-sitter/tree-sitter-regex` | `b2ac15e27fce703d2f37a79ccd94a5c0cbe9720b` | regex |
| `tree-sitter/tree-sitter-rust` | `77a3747266f4d621d0757825e6b11edcbf991ca5` | rust |
| `tree-sitter/tree-sitter-typescript` | `75b3874edb2dc714fb1fd77a32013d0f8699989f` | tsx, typescript |

---

## 5. Node.js — `NODEJS_DIST_URL`

Fetched with `curl`. The checksum file is fetched too and verified against the
tarball, so the mirror must carry both.

| Path below the base URL |
| --- |
| `/v22.23.2/node-v22.23.2-linux-x64.tar.xz` |
| `/v22.23.2/node-v22.23.2-linux-arm64.tar.xz` |
| `/v22.23.2/SHASUMS256.txt` |

Pinned by `NODE_VERSION`.

---

## 6. Package ecosystems

These two cannot be reduced to a file list: both resolve transitive
dependencies at build time. They need a mirror that *proxies* the upstream
registry rather than one seeded with named files.

### npm — `NPM_REGISTRY_URL`

Top-level packages, from `NPM_PACKAGES`. Their transitive dependencies are
resolved by npm and are not enumerated here.

```
bash-language-server@5.8.1 yaml-language-server@1.24.0 vscode-langservers-extracted@4.10.0 typescript-language-server@6.0.0 typescript@5.9.3 pyright@1.1.414
```

Installed with `--omit=dev --no-audit --no-fund`, so only runtime dependencies
are fetched and no request goes to the audit endpoint.

### Go modules — `GOPROXY`, `GOSUMDB`

One module is requested; its dependency graph is resolved through the proxy.

| Module |
| --- |
| `golang.org/x/tools/gopls@v0.23.0` |

Pinned by `GOPLS_VERSION`. Set `GOSUMDB=off` when the checksum database is not
reachable, and `GOTOOLCHAIN=local` so Go never tries to fetch a newer toolchain
through the proxy.

---

## 7. Deliberately not parameterised

| What | Where it comes from instead |
| --- | --- |
| `dnf` repositories (UBI, EPEL) — `ripgrep`, `fd-find`, `clang-tools-extra`, and the `builder-lsp` toolchain | `/etc/yum.repos.d` inside `BASE_IMAGE`. Build against a UDI derivative carrying your own repository configuration. |
| TLS trust for a mirror behind a private CA | `BASE_IMAGE`, or whatever makes the mirror transparent. |
| Proxies | `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` and their lowercase spellings are predefined build arguments in both BuildKit and Buildah — available in every stage without being declared here. |

---

## Why three GitHub arguments

They are not redundant. Three different mechanisms fetch from github.com, and
each needs its own redirect:

| Mechanism | Used for | Redirected by |
| --- | --- | --- |
| `git clone` | section 2 | `url.<mirror>.insteadOf` in `/etc/gitconfig`, written in the `base` stage — so it also catches submodules and anything a workspace user clones later |
| `curl` at a call site this repository writes | section 3 | `GITHUB_RELEASES_URL`, substituted directly into the URL |
| `curl` inside nvim-treesitter, against URLs carried in its own parser table | section 4 | `TREESITTER_GRAMMAR_URL`, rewritten into that table before installation |

The git redirect does **not** reach sections 3 or 4, and the section 3
substitution does not reach section 4. Setting only `GITHUB_REPOS_URL` on an
isolated network gets you a successful clone followed by 38 timeouts.

---

## Regenerating section 4

The grammar table is derived from the nvim-treesitter commit pinned in
`NVIM_TREESITTER_REF`. After bumping that pin, rebuild and re-extract:

```bash
podman build --target lsp -t neovim:dev-lsp nvim

cat > /tmp/dump.lua <<'LUA'
vim.opt.runtimepath:prepend("/usr/share/nvim/vendor/nvim-treesitter")
local parsers = require("nvim-treesitter.parsers")
for _, f in ipairs(vim.fn.readdir("/usr/share/nvim/vendor/treesitter/parser")) do
  local lang = f:gsub("%.so$", "")
  local i = parsers[lang] and parsers[lang].install_info
  io.write(("%s\t%s\t%s\n"):format(lang, i and i.url or "?", i and i.revision or "?"))
end
LUA

podman run --rm -v /tmp/dump.lua:/tmp/dump.lua:ro,Z \
    neovim:dev-lsp nvim --headless -l /tmp/dump.lua
```

Every other section is quoted from a `Containerfile` `ARG` and only changes when
you change that `ARG`.
