# neovim

Neovim on the [devfile Universal Developer Image][udi], built to be the dev
container for a DevSpace driven entirely from a terminal.

The design goal is narrow: give a brand-new workspace a Neovim that is already
worth using, and then get completely out of the way the moment someone brings
their own configuration. Nothing here has to be uninstalled, disabled, or
unpicked first.

[udi]: https://github.com/devfile/developer-images

## The two images

One [`Containerfile`](Containerfile), two published images, told apart by the
tag suffix:

| Image | Stage | Contains |
| --- | --- | --- |
| `ghcr.io/kirikae/terminal-devspaces/neovim:${NEOVIM_VERSION}-base` | `base` | Neovim, a plugin-free system config, `ripgrep`, `fd` |
| `ghcr.io/kirikae/terminal-devspaces/neovim:${NEOVIM_VERSION}-lsp` | `lsp` | everything above, plus 40 Tree-sitter languages and 12 language servers |

`NEOVIM_VERSION` is the Neovim release the image was built from — `0.12.5-base`,
`0.12.5-lsp` — and is also set as an environment variable inside the image, so
`echo $NEOVIM_VERSION` in a workspace tells you what you are running. CI also
publishes the moving tags `latest-base` and `latest-lsp`, and a
`sha-<commit>-base` / `-lsp` pair per build.

Take the base if you want a fast, predictable editor and intend to bring your
own tooling. Take the LSP image if you want highlighting and LSP to work on a
fresh workspace with no network access and no first-run plugin install — every
parser is compiled and every server is downloaded at build time.

The UDI is Red Hat UBI 9 based, so `dnf` is available and the usual language
toolchains (Go, Node, Python, Java, Rust) are already present.

## How the build is laid out

```
builder-base ──┐
               ├─> base ──> builder-lsp ──┐
${BASE_IMAGE} ─┘    └────────────────────>├─> lsp
                                          ┘
```

Two rules produce that shape, and between them they are the whole story:

**A stage whose name does not start with `builder-` is a shipping image.**
`base` and `lsp` are the only two, and nothing that exists only in order to
build something is allowed into either. The Neovim tarball is downloaded,
checksummed and unpacked in `builder-base`; `base` receives `/opt/nvim` as a
finished tree. The Tree-sitter compilers, the `tree-sitter` CLI, `git` and the
Go build cache live in `builder-lsp`; `lsp` receives `/opt/nvim-lsp` and
`/usr/share/nvim/vendor`. `lsp` is therefore `FROM base`, **not** `FROM
builder-lsp` — otherwise the toolchain would ship with it.

**The shipping stages are ordered least- to most-likely-to-change.** Each is one
layer per idea: a single `dnf` transaction with its cache dropped in the same
command, one `COPY --from` per finished tree, one `RUN` for everything that is a
symlink or a `mkdir`, and the config last, so editing a Lua file rebuilds one
small layer and nothing else. The build-time test at the end of each stage
deletes the state Neovim wrote while running it, in the same layer that created
it, so it nets out to nothing.

Both images self-test and **fail rather than publish something broken** — see
[Building locally](#building-locally).

## Mirrors and air-gapped builds

This build reaches no hard-coded host. It is meant to run on a laptop with no
route to the internet, given a mirror that carries the content — and
**[`MIRRORS.md`](MIRRORS.md) is the manifest of exactly what that mirror needs
to carry**: one container image, two git repositories, eight release assets, 38
Tree-sitter grammar archives, two Node files, and two package ecosystems, each
pinned to the version currently in the `Containerfile`. That file is excluded
from the build context — it documents the build, it is never read by it.

Each argument is a **base URL** and the path below it matches upstream byte for
byte, so a path-preserving reverse proxy or artifact repository is enough and no
per-artifact override is ever needed.

| Argument | Default | Covers |
| --- | --- | --- |
| `BASE_IMAGE` | `quay.io/devfile/universal-developer-image:ubi9-latest` | the UDI itself |
| `GITHUB_REPOS_URL` | `https://github.com` | every git clone, including ones this build never names |
| `GITHUB_RELEASES_URL` | `https://github.com` | Neovim, `lua-language-server`, `rust-analyzer`, `marksman` release assets |
| `TREESITTER_GRAMMAR_URL` | follows `GITHUB_REPOS_URL` | the 38 grammar source archives |
| `NODEJS_DIST_URL` | `https://nodejs.org/dist` | the private Node runtime and its `SHASUMS256.txt` |
| `NPM_REGISTRY_URL` | `https://registry.npmjs.org` | the npm-packaged language servers |
| `GOPROXY` | `https://proxy.golang.org,direct` | `gopls` |
| `GOSUMDB` | `sum.golang.org` | `gopls` checksum verification (`off` to disable) |
| `GOTOOLCHAIN` | unset | set to `local` so Go never fetches a newer toolchain |

```bash
podman build --target lsp -t neovim:dev-lsp \
    --build-arg BASE_IMAGE=registry.corp/devfile/universal-developer-image:ubi9-latest \
    --build-arg GITHUB_REPOS_URL=https://git.corp/mirror/github \
    --build-arg GITHUB_RELEASES_URL=https://artifacts.corp/github \
    --build-arg NODEJS_DIST_URL=https://artifacts.corp/nodejs/dist \
    --build-arg NPM_REGISTRY_URL=https://artifacts.corp/api/npm/npm \
    --build-arg GOPROXY=https://artifacts.corp/api/go/go \
    --build-arg GOSUMDB=off \
    --build-arg GOTOOLCHAIN=local \
    nvim
```

### Three GitHub arguments, not one

They are not redundant, and this is the part that bites. Three different
mechanisms fetch from github.com, and a redirect for one does not apply to the
others:

**1. `git clone`** — redirected by a system git config written in the `base`
stage:

```gitconfig
[url "https://git.corp/mirror/github/"]
	insteadOf = https://github.com/
```

Clone commands therefore keep their canonical `https://github.com/...` URLs and
are rewritten transparently. That is not merely tidier — it also catches clones
this build never writes down: submodules, and anything the workspace user clones
later, since the rule ships in the image. At the default value the rule rewrites
the URL to itself and does nothing. It is appended to `/etc/gitconfig`, so the
UDI's own `git-lfs` filters survive.

**2. `curl` at a call site this repository writes** — release assets, with
`GITHUB_RELEASES_URL` substituted straight into the URL.

**3. `curl` inside nvim-treesitter** — each of the 40 grammars is fetched as
`<repo url>/archive/<revision>.tar.gz`, from a URL carried in nvim-treesitter's
own parser table. **This is not a git operation**, so mechanism 1 does not touch
it, and the URL is not written here, so mechanism 2 does not either.
[`lsp/vendor-treesitter.sh`](lsp/vendor-treesitter.sh) rewrites that table
before installing. `TREESITTER_GRAMMAR_URL` follows `GITHUB_REPOS_URL` by
default, since the two are the same host upstream; set it separately if your git
mirror cannot serve `/archive/` tarballs.

If the rewrite is asked for and matches nothing, **the build fails** — on an
isolated network, silently falling through to github.com is 38 timeouts rather
than a useful error. Setting only `GITHUB_REPOS_URL` would otherwise give you a
successful clone followed by exactly that.

### What is deliberately not parameterised

| What | Where it comes from instead |
| --- | --- |
| `dnf` repositories — `ripgrep`, `fd-find`, `clang-tools-extra`, and the `builder-lsp` toolchain | `/etc/yum.repos.d` inside `BASE_IMAGE`. Build against a UDI derivative carrying your own repository configuration. |
| TLS trust for a mirror behind a private CA | `BASE_IMAGE`, or whatever makes the mirror transparent in the first place. |
| Proxies | `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` and their lowercase spellings are predefined build arguments in both BuildKit and Buildah, available in every stage without being declared. |

## How the config gets overridden

This is the part worth understanding, because it is the reason the image is
laid out the way it is.

**The image's config lives in `/etc/xdg/nvim`, not in `/home/user`.** A
DevSpace with a persistent home mounts a PVC over `/home/user`, so anything the
image writes there is shadowed the instant a real home directory arrives.
`/etc/xdg` is Neovim's documented system-wide fallback, which gives three
behaviours for free:

**1. Fresh workspace, no user config.** Neovim finds no
`~/.config/nvim/init.lua`, falls back to `/etc/xdg/nvim/init.lua`, and you get
the image defaults.

**2. You bring your own home directory.** Your `~/.config/nvim` exists, so
Neovim loads it and *never reads the image config at all*. Not merged, not
layered — simply not read. Your config behaves exactly as it does on your
laptop.

**3. You want the defaults plus your own changes.** Start your
`~/.config/nvim/init.lua` with:

```lua
dofile("/etc/xdg/nvim/init.lua")

-- your overrides from here
vim.opt.relativenumber = false
```

Every autocommand the image sets lives in one augroup, so case 3 can also drop
the lot selectively:

```lua
vim.api.nvim_del_augroup_by_name("devspace")
```

## What the base config does

Plugin-free by design — everything is a built-in option, so the base image
starts instantly and cannot break on an upstream plugin change.

- Leader is `<Space>`; `<leader>` is otherwise left mostly unclaimed, because
  someone else's config may end up sitting on top of this one.
- `<C-h/j/k/l>` for window navigation, chosen to nest sensibly inside the
  equivalent tmux pane bindings.
- Persistent undo, no swapfiles, 2-space soft tabs with per-filetype
  corrections, `.editorconfig` honoured.
- `grepprg` set to ripgrep.
- **Clipboard over OSC 52**, so a yank inside a browser terminal reaches your
  real clipboard. Paste reads the unnamed register rather than issuing an OSC
  52 read, because browsers almost universally refuse the read and Neovim would
  block waiting for a reply that never arrives.

No colourscheme is set. Neovim's built-in default is legible on both
256-colour and true-colour terminals, and choosing one for you is exactly the
kind of decision a base image should not make.

## What the LSP image adds

Tree-sitter parsers are listed in [`lsp/parsers.txt`](lsp/parsers.txt) and
compiled into `/usr/share/nvim/vendor`. Anything not in that list can still be
added at runtime with `:TSInstall`, which installs into your home directory
rather than the image.

Language servers (`bashls`, `clangd`, `cssls`, `gopls`, `html`, `jsonls`,
`lua_ls`, `marksman`, `pyright`, `rust_analyzer`, `ts_ls`, `yamlls`) install
into `/opt/nvim-lsp` and are exposed on `PATH`. Server configuration comes
from a vendored copy of `nvim-lspconfig`, which Neovim 0.11+ reads straight off
`runtimepath` as `lsp/<name>.lua` — no plugin manager and no setup calls.
Completion is Neovim's built-in `vim.lsp.completion`, which is why this layer
ships two vendored plugins instead of a dozen.

A server is only enabled if its executable is actually present, so
`:lua =vim.g.devspace_lsp_servers` tells you what the image really shipped
with.

**Nothing installs under `/home`.** That includes a private Node runtime, even
though the UDI already has one — the UDI's Node lives in `/home/user/.nvm` and
disappears the moment a persistent home is mounted over it. That runtime is
trimmed to what the servers actually execute: `npm`, `corepack`, the C headers
and the docs are build-time material and are removed before the tree is copied
into the shipping image.

The drop-in mechanism is what keeps the two images independent.
`/etc/xdg/nvim/init.lua` sources every `*.lua` in `/etc/xdg/nvim/devspace.d`
after its own modules, sorted by filename, so the `lsp` stage adds
[`10-treesitter.lua`](lsp/config/devspace.d/10-treesitter.lua) and
[`20-lsp.lua`](lsp/config/devspace.d/20-lsp.lua) without patching a line of the
base config.

## Using it in a DevSpace

[`devfile.yaml`](devfile.yaml) is a ready-to-run project devfile: it selects
the `tmux-ttyd` editor from [`../tmux-devspace`](../tmux-devspace) and uses the
`-lsp` image as the dev container.

The split matters. The editor definition supplies only the terminal transport
(tmux served over ttyd); the *dev container image* is what supplies the editor,
and that comes from your own project's devfile. That is what this image is for.

To use it, commit a `devfile.yaml` at the root of your repository — copy
[`devfile.yaml`](devfile.yaml) as a starting point — and start a workspace from
that repository.

### Persistent home

Case 2 and 3 above need `/home/user` to survive a workspace restart. Either
turn it on cluster-wide:

```yaml
# CheCluster
spec:
  devEnvironments:
    persistUserHome:
      enabled: true
```

…or declare the volume in your own devfile, as the sample does.

The two are not quite equivalent, and the difference shows up on the very
first start:

- **`persistUserHome`** runs an init container that seeds the PVC from the
  image's own `/home/user` the first time, and skips it on every start after
  that. You get the UDI's shell dotfiles, and anything you change afterwards
  survives.
- **A volume declared in the devfile** is simply mounted, so `/home/user`
  starts empty and the image's copy is hidden behind it. Neovim recreates what
  it needs on first launch, so this costs you the UDI's stock dotfiles and
  nothing else.

Either way an image update never overwrites a config you have put there, which
is the property that matters here.

### Terminal colours

The config enables `termguicolors` only when `COLORTERM` says the terminal
really supports it. ttyd sets it; **tmux does not pass it through unless its
own config opts in**, which is the usual cause of washed-out or invisible text
in a web terminal. To get true colour end to end, put this in your
`~/.tmux.conf`:

```tmux
set -g default-terminal "tmux-256color"
set -as terminal-features ",*:RGB"
```

The bundled fallback config in `../tmux-ttyd/tmux.conf.default` deliberately
does not set this — it cannot know what your browser and terminal support — so
Neovim stays in 256-colour mode until you opt in. It looks fine either way.

## Building locally

The build context is this directory, and the stage is chosen with `--target`:

```bash
podman build --target base -t neovim:dev-base nvim
podman build --target lsp  -t neovim:dev-lsp  nvim
```

Building `lsp` builds `base` on the way through, so the second command is the
only one you need if you just want the full image. There is no `BASE_IMAGE`
juggling between two files any more: one build, one cache.

Both stages **self-test and fail rather than publish something broken**. The
base stage checks that the Lua parses and that the workspace user can write
Neovim's state directories. The LSP stage runs
[`lsp/verify.lua`](lsp/verify.lua), which starts every language server for real
and parses a buffer per language — because "the binary exists" is a much weaker
claim than "the editor works". `lua-language-server` in particular answers
`--version` happily and then dies on first contact if its log directory is not
writable, and the only symptom in a workspace is a silent absence of LSP.

Try the result the way a workspace would see it:

```bash
# image defaults
podman run --rm -it neovim:dev-lsp nvim

# with your own home directory mounted over the top
podman run --rm -it -v "$HOME/dotfiles:/home/user:Z" neovim:dev-lsp nvim
```

## Updating pins

Everything is pinned, and every version lives in a `Containerfile` `ARG`, so an
upgrade is a one-line edit and the build fails loudly if a checksum moves.

| Pin | Where in `Containerfile` |
| --- | --- |
| Neovim version + per-arch SHA256 | global `ARG`s, above the first stage |
| `nvim-treesitter` commit | `builder-lsp` |
| `nvim-lspconfig` tag | `builder-lsp` |
| Node, lua-language-server, rust-analyzer, marksman, gopls | `builder-lsp` |
| npm-installed servers | `NPM_PACKAGES` in `builder-lsp` |

`NEOVIM_VERSION` is a global `ARG` because it is read twice: once by
`builder-base` to fetch the tarball, and once by CI to name the published tags.
Bumping it there is all that is needed.

Neovim's checksums are verified explicitly because release assets are mutable in
principle — and a mirror is one more thing that can be wrong. Node's are read
from the release's own `SHASUMS256.txt`.

After changing any pin, refresh [`MIRRORS.md`](MIRRORS.md) so whoever populates
the mirror knows what moved. Bumping `NVIM_TREESITTER_REF` is the one that
matters most: it re-pins all 38 grammar revisions at once, and that file carries
the command to re-extract them.

`typescript` is held at 5.x deliberately: `typescript-language-server` drives
`tsserver`, and TypeScript 7 replaced it with a different native binary.

## Architecture

The `Containerfile` builds on `x86_64` and `aarch64`. CI publishes `x86_64`
only — compiling every Tree-sitter parser under emulation is slow enough not
to be worth it — so build locally for arm64.

`clangd` comes from `dnf` rather than an upstream LLVM release because LLVM
publishes no aarch64 Linux build, and one install path for every architecture
is worth more than a newer clangd. It is the one piece of the LSP image that is
installed in the shipping stage rather than copied in from a builder, because it
is a runtime dependency rather than a build tool.

## Relationship to `../nvim-udi`

[`../nvim-udi`](../nvim-udi) is the two-Containerfile predecessor of this
directory, published as `nvim-udi-base` and `nvim-udi-ide`. It is left in place
and still built by CI; this directory is where the work continues. The editor
configuration is the same, and a workspace can move from `nvim-udi-ide:latest`
to `neovim:latest-lsp` without noticing.
