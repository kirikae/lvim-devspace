#!/bin/sh
# Runs inside the merged dev container (devfile "postStart" exec command),
# backgrounded via `nohup ... &` by the devfile commandLine. This is the
# only piece that touches $HOME, so it's the one place that needs updating
# if you want to recognize other config locations (e.g. ~/.config/tmux/tmux.conf).
set -eu

TOOLBOX=/toolbox
PORT="${TTYD_PORT:-7681}"
SESSION="${TMUX_SESSION_NAME:-main}"

# Prefer the user's own config if $HOME is populated (persistent user home,
# a dotfiles checkout, or a bind-mounted ConfigMap/Secret all land here the
# same way); otherwise fall back to the bundled default so the session is
# still usable on a brand-new workspace.
if [ -f "${HOME}/.tmux.conf" ]; then
  TMUX_CONF="${HOME}/.tmux.conf"
elif [ -f "${HOME}/.config/tmux/tmux.conf" ]; then
  TMUX_CONF="${HOME}/.config/tmux/tmux.conf"
else
  TMUX_CONF="${TOOLBOX}/tmux.conf.default"
fi

echo "[tmux-ttyd] using tmux config: ${TMUX_CONF}"

# Create the session up front (idempotent) so it exists before the first
# browser connection, and so it survives a page refresh or a second tab.
"${TOOLBOX}/tmux" -f "${TMUX_CONF}" new-session -d -s "${SESSION}" 2>/dev/null || true

# --writable is required: ttyd serves read-only terminals by default.
# Auth/TLS is handled by Che's own gateway in front of this endpoint
# (cookiesAuthEnabled in the devfile), so ttyd's own -c/--credential
# flag is left off here — add it only if you're exposing this outside Che.
exec "${TOOLBOX}/ttyd" \
  --writable \
  --port "${PORT}" \
  --client-option titleFixed="${SESSION}" \
  "${TOOLBOX}/tmux" -f "${TMUX_CONF}" attach-session -t "${SESSION}"
