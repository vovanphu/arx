#!/usr/bin/env bash
# install-tmux-plugins.sh - Managed by Chezmoi
#
# Clones tmux-resurrect + tmux-continuum directly into ~/.tmux/plugins (no TPM).
# tmux.conf sources them if present. Auto-restore is kept OFF in tmux.conf;
# continuum auto-saves snapshots so sessions can be restored + attached on demand.
#
# Runs on every machine that has tmux. run_onchange: bump a REV marker below to
# force a re-run and pull updated plugin versions.
#   resurrect  rev: master 2026-06-08
#   continuum  rev: master 2026-06-08

set -eu

command -v tmux >/dev/null 2>&1 || exit 0
command -v git  >/dev/null 2>&1 || exit 0

PLUGIN_DIR="${HOME}/.tmux/plugins"

install_plugin() {
  repo="$1"
  dest="${PLUGIN_DIR}/$2"
  if [ -d "${dest}/.git" ]; then
    git -C "${dest}" pull --ff-only --quiet || true
  else
    mkdir -p "${PLUGIN_DIR}"
    git clone --depth 1 --quiet "${repo}" "${dest}" || true
  fi
}

install_plugin "https://github.com/tmux-plugins/tmux-resurrect.git" "tmux-resurrect"
install_plugin "https://github.com/tmux-plugins/tmux-continuum.git" "tmux-continuum"

# If a tmux server is already running, reload so the plugins take effect now.
if tmux info >/dev/null 2>&1; then
  tmux source-file "${HOME}/.tmux.conf" >/dev/null 2>&1 || true
fi
