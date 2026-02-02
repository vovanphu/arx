#!/bin/bash

# Identify chezmoi binary (Default to ~/.local/bin)
CHEZMOI_BIN="$HOME/.local/bin/chezmoi"

# Install chezmoi if not found
if [ ! -f "$CHEZMOI_BIN" ]; then
    echo "Installing chezmoi via official script..."
    mkdir -p "$HOME/.local/bin"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

# Pre-install Bitwarden CLI (Required for secret rendering)
if ! command -v bw &> /dev/null; then
    echo "Installing Bitwarden CLI..."
    if command -v apt-get &> /dev/null; then
        # Try apt/snap or direct download. Direct download is safer cross-distro.
        curl -L "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o bw.zip
        unzip -o bw.zip
        chmod +x bw
        mkdir -p "$HOME/.local/bin"
        mv bw "$HOME/.local/bin/"
        rm bw.zip
        export PATH="$HOME/.local/bin:$PATH"
    fi
fi

# Smart Unlock: Help user provision secrets immediately
if [ -z "${BW_SESSION:-}" ]; then
    echo ""
    echo "--- Bitwarden Setup ---"
    read -p "Bitwarden session not detected. Unlock vault now to provision secrets? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        export BW_SESSION=$(bw unlock --raw)
        echo "Vault unlocked!"
    fi
fi

# Initialize and apply dotfiles from current directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "--- Chezmoi Initialization ---"
echo "Initializing Chezmoi with source: $SCRIPT_DIR"
"$CHEZMOI_BIN" init --source "$SCRIPT_DIR" --force

echo "Verifying source path..."
"$CHEZMOI_BIN" source-path

echo "Applying dotfiles..."
"$CHEZMOI_BIN" apply --force

echo "Setup complete. Please reload your shell."
