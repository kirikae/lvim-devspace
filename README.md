# terminal-devspaces

Images and config for DevSpaces (Che-based DevSpaces, mainly), with a focus on
replicating terminal-only usage. Relies on `tmux` and `ttyd`.

A terminal DevSpace is assembled from two independent halves, and keeping them
separate is the point of this repository:

| | What it provides | Where |
| --- | --- | --- |
| **Editor definition** | the terminal transport — tmux served over ttyd, installed once per cluster | [`tmux-devspace/`](tmux-devspace/), built from [`tmux-ttyd/`](tmux-ttyd/) |
| **Dev container** | the image you actually work in, including the text editor | [`nvim-udi/`](nvim-udi/) |

The editor definition deliberately contains no text editor. It pairs with any
dev container that has one — vim, Neovim, Emacs, whatever you already use — so
bring your own image if you have one.

If you don't, [`nvim-udi/`](nvim-udi/) is the one provided here: Neovim on the
Universal Developer Image, in a plugin-free base flavour and an IDE flavour
with Tree-sitter and 12 language servers vendored in at build time. Its config
lives in `/etc/xdg` rather than `/home/user`, so a persistent home directory
containing your own `~/.config/nvim` takes over completely and nothing in the
image has to be unpicked first.

## Getting started

1. Install the editor definition into the cluster —
   see [`tmux-devspace/README.md`](tmux-devspace/README.md).
2. Commit a project devfile to your repository that selects that editor and
   picks a dev container image. Copy
   [`nvim-udi/devfile.yaml`](nvim-udi/devfile.yaml) as a starting point.
3. Start a workspace from the repository.
