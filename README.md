# terminal-devspaces

Images and config for DevSpaces (Che-based DevSpaces, mainly), with a focus on
replicating terminal-only usage. Relies on `tmux` and `ttyd`.

A terminal DevSpace is assembled from two independent halves, and keeping them
separate is the point of this repository:

| | What it provides | Where |
| --- | --- | --- |
| **Editor definition** | the terminal transport — tmux served over ttyd, installed once per cluster | [`tmux-devspace/`](tmux-devspace/), built from [`tmux-ttyd/`](tmux-ttyd/) |
| **Dev container** | the image you actually work in, including the text editor | [`nvim/`](nvim/) |

The editor definition deliberately contains no text editor. It pairs with any
dev container that has one — vim, Neovim, Emacs, whatever you already use — so
bring your own image if you have one.

If you don't, [`nvim/`](nvim/) is the one provided here: Neovim on the
Universal Developer Image, in a plugin-free `-base` flavour and a `-lsp`
flavour with Tree-sitter and 12 language servers vendored in at build time,
both from one multi-stage `Containerfile`. Its config lives in `/etc/xdg`
rather than `/home/user`, so a persistent home directory containing your own
`~/.config/nvim` takes over completely and nothing in the image has to be
unpicked first. Every host the build fetches from is a build argument, so it
can be pointed at an internal mirror or built air-gapped on a laptop with no
network at all — [`nvim/MIRRORS.md`](nvim/MIRRORS.md) lists every artifact such
a mirror has to carry.

[`nvim-udi/`](nvim-udi/) is the two-Containerfile predecessor of `nvim/`,
published as `nvim-udi-base` and `nvim-udi-ide`. It is still built, but new
work goes into `nvim/`.

## Getting started

1. Install the editor definition into the cluster —
   see [`tmux-devspace/README.md`](tmux-devspace/README.md).
2. Commit a project devfile to your repository that selects that editor and
   picks a dev container image. Copy
   [`nvim/devfile.yaml`](nvim/devfile.yaml) as a starting point.
3. Start a workspace from the repository.
