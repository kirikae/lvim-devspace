#!/bin/sh
# Runs once, as the Kubernetes init container (devfile "preStart" apply
# command). Copies the pre-built payload onto the shared volume so the
# merged dev container can use it after the init container exits.
set -eu

TARGET="/toolbox"

echo "[injector] copying tmux/ttyd payload into ${TARGET}"
cp -r /opt/toolbox/. "${TARGET}/"
chmod +x "${TARGET}/tmux" "${TARGET}/ttyd" "${TARGET}/entrypoint-volume.sh"
echo "[injector] done"
