# nvim-udi

Neovim on the [devfile Universal Developer Image][udi], built to be the dev
container for a DevSpace driven entirely from a terminal.

The design goal is narrow: give a brand-new workspace a Neovim that is already
worth using, and then get completely out of the way the moment someone brings
their own configuration. Nothing here has to be uninstalled, disabled, or
unpicked first.

[udi]: https://github.com/devfile/developer-images

## The two images

| Image | Built from | Contains |
| --- | --- | --- |
| `nvim-udi-base` | [`base/`](base/) | Neovim 0.12.5, a plugin-free system config, `ripgrep`, `fd` |
| `nvim-udi-ide` | [`ide/`](ide/) | everything above, plus 40 Tree-sitter languages and 12 language servers |

`nvim-udi-ide` builds *on the published base image* rather than rebuilding it,
so the layer you run is the layer that was tested.

Take the base if you want a fast, predictable editor and intend to bring your
own tooling. Take the IDE layer if you want highlighting and LSP to work on a
fresh workspace with no network access and no first-run plugin install — every
parser is compiled and every server is downloaded at build time.

The UDI is Red Hat UBI 9 based, so `dnf` is available and the usual
language toolchains (Go, Node, Python, Java, Rust) are already present.

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

## What the IDE layer adds

Tree-sitter parsers are listed in [`ide/parsers.txt`](ide/parsers.txt) and
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
disappears the moment a persistent home is mounted over it.

## Using it in a DevSpace

[`devfile.yaml`](devfile.yaml) is a ready-to-run project devfile: it selects
the `tmux-ttyd` editor from [`../tmux-devspace`](../tmux-devspace) and uses
`nvim-udi-ide` as the dev container.

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

```bash
podman build -t nvim-udi-base:dev nvim-udi/base
podman build -t nvim-udi-ide:dev \
    --build-arg BASE_IMAGE=localhost/nvim-udi-base:dev \
    nvim-udi/ide
```

The `BASE_IMAGE` build argument is what lets you iterate on both layers at
once; without it the IDE layer builds against the published base image.

Both builds **self-test and fail rather than publish something broken**. The
base checks that the Lua parses and that the workspace user can write Neovim's
state directories. The IDE layer runs
[`ide/verify.lua`](ide/verify.lua), which starts every language server for real
and parses a buffer per language — because "the binary exists" is a much weaker
claim than "the editor works". `lua-language-server` in particular answers
`--version` happily and then dies on first contact if its log directory is not
writable, and the only symptom in a workspace is a silent absence of LSP.

Try the result the way a workspace would see it:

```bash
# image defaults
podman run --rm -it nvim-udi-ide:dev nvim

# with your own home directory mounted over the top
podman run --rm -it -v "$HOME/dotfiles:/home/user:Z" nvim-udi-ide:dev nvim
```

## Updating pins

Everything is pinned, and every version lives in a Containerfile `ARG` so
upgrades are a one-line edit and the build fails loudly if a checksum moves.

| Pin | Where |
| --- | --- |
| Neovim version + per-arch SHA256 | `base/Containerfile` |
| `nvim-treesitter` commit | `ide/Containerfile` |
| `nvim-lspconfig` tag | `ide/Containerfile` |
| Node, lua-language-server, rust-analyzer, marksman, gopls | `ide/Containerfile` |
| npm-installed servers | `NPM_PACKAGES` in `ide/Containerfile` |

Neovim's checksums are verified explicitly because GitHub release assets are
mutable in principle. Node's are read from the release's own `SHASUMS256.txt`.

`typescript` is held at 5.x deliberately: `typescript-language-server` drives
`tsserver`, and TypeScript 7 replaced it with a different native binary.

## Architecture

The Containerfiles build on `x86_64` and `aarch64`. CI publishes `x86_64`
only — compiling every Tree-sitter parser under emulation is slow enough not
to be worth it — so build locally for arm64.

`clangd` comes from `dnf` rather than an upstream LLVM release because LLVM
publishes no aarch64 Linux build, and one install path for every architecture
is worth more than a newer clangd.
