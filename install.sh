#!/bin/bash
# Usage: ./install.sh
#        OR: sh -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/dotfiles/master/install.sh)"

# --- Remote Bootstrap Logic ---
# Detect if running from pipe/curl (Script file doesn't exist in CWD)
if [ ! -f "install.sh" ]; then 
    echo "Running in Remote Bootstrap Mode..."
    DEST_DIR="$HOME/dotfiles"
    
    # 0. Load .env from current directory if present
    if [ -f ".env" ]; then
        echo "Found .env in current directory. Loading credentials..."
        # Export variables to sub-processes
        export $(grep -v '^#' .env | xargs)
    fi
    # 1. Install Git if missing
    if ! command -v git &> /dev/null; then
        echo "Git not found. Installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y git
        else
            echo "Error: Git is required. Please install Git manually."
            exit 1
        fi
    fi
    
    # 2. Clone Repo
    if [ ! -d "$DEST_DIR" ]; then
        echo "Cloning repository to $DEST_DIR..."
        git clone https://github.com/vovanphu/dotfiles.git "$DEST_DIR"
    else
        echo "Repo exists. Pulling latest..."
        cd "$DEST_DIR" || exit
        git pull
    fi
    
    # 3. Handover
    echo "Handing over to local install script..."
    cd "$DEST_DIR" || exit
    # Ensure usage of bash for the local script
    exec bash "install.sh"
    exit
fi
# ------------------------------

# Identify chezmoi binary (Default to ~/.local/bin)
export PATH="$HOME/.local/bin:$PATH"
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
        # Ensure unzip is present
        if ! command -v unzip &> /dev/null; then
            echo "Installing unzip..."
            sudo apt-get update && sudo apt-get install -y unzip
        fi
        
        # Download Bitwarden
        curl -L "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o bw.zip
        unzip -o bw.zip
        chmod +x bw
        mkdir -p "$HOME/.local/bin"
        mv bw "$HOME/.local/bin/"
        rm bw.zip
        export PATH="$HOME/.local/bin:$PATH"
    fi
fi

# Smart Unlock: Help user provision secrets automatically or interactively
if [ -z "${BW_SESSION:-}" ]; then
    echo ""
    echo "--- Bitwarden Setup ---"
    
    # 1. Try to load variables from environment or .env file
    PASSWORD="${BW_PASSWORD:-}"
    EMAIL="${BW_EMAIL:-}"
    ROLE_VAR="${ROLE:-}"
    HOSTNAME_VAR="${HOSTNAME:-}"
    USER_NAME_VAR="${USER_NAME:-}"
    EMAIL_ADDRESS_VAR="${EMAIL_ADDRESS:-}"

    if [ -f ".env" ]; then
        echo "Found .env file. Parsing for automation variables..."
        [ -z "$PASSWORD" ] && PASSWORD=$(grep "^BW_PASSWORD=" .env | head -n1 | cut -d'=' -f2- | xargs)
        [ -z "$EMAIL" ] && EMAIL=$(grep "^BW_EMAIL=" .env | head -n1 | cut -d'=' -f2- | xargs)
        [ -z "$ROLE_VAR" ] && ROLE_VAR=$(grep "^ROLE=" .env | head -n1 | cut -d'=' -f2- | xargs)
        [ -z "$HOSTNAME_VAR" ] && HOSTNAME_VAR=$(grep "^HOSTNAME=" .env | head -n1 | cut -d'=' -f2- | xargs)
        [ -z "$USER_NAME_VAR" ] && USER_NAME_VAR=$(grep "^USER_NAME=" .env | head -n1 | cut -d'=' -f2- | xargs)
        [ -z "$EMAIL_ADDRESS_VAR" ] && EMAIL_ADDRESS_VAR=$(grep "^EMAIL_ADDRESS=" .env | head -n1 | cut -d'=' -f2- | xargs)
    fi

    SHOULD_PROMPT=true
    if [ -n "$PASSWORD" ]; then
        echo "BW_PASSWORD detected. Attempting automated unlock..."
        # Check login status
        if bw status | grep -q "unauthenticated"; then
            if [ -n "$EMAIL" ]; then
                echo "Logging in as $EMAIL via passwordenv..."
                export BW_PASSWORD="$PASSWORD"
                bw login "$EMAIL" --passwordenv BW_PASSWORD
            else
                echo "Logging in via passwordenv..."
                export BW_PASSWORD="$PASSWORD"
                bw login --passwordenv BW_PASSWORD
            fi
        fi
    
        # Unlock and capture session using passwordenv
        export BW_PASSWORD="$PASSWORD"
        BW_SES=$(bw unlock --passwordenv BW_PASSWORD --raw)
        if [ $? -eq 0 ] && [ -n "$BW_SES" ]; then
            export BW_SESSION="$BW_SES"
            echo "Vault unlocked automatically!"
            echo "Syncing Bitwarden vault..."
            bw sync
            SHOULD_PROMPT=false
        else
            echo "Warning: Automated unlock failed. Falling back to interactive mode..."
        fi
        # Clear sensitive env var
        unset BW_PASSWORD
    fi

    # 2. Fallback to interactive prompt if automated unlock skipped or failed
    if [ "$SHOULD_PROMPT" = true ]; then
        read -p "Bitwarden session not detected. Unlock vault now to provision secrets? (y/n) " -r
        echo
        if [[ $REPLY =~ ^[Yy] ]]; then
            # Check login status
            if bw status | grep -q "unauthenticated"; then
                echo "You are not logged in to Bitwarden."
                echo ">>> STEP 1: Authenticate Device (Login)"
                bw login
                echo "Login successful."
            fi
        
            # Unlock and capture session
            echo ">>> STEP 2: Decrypt Vault (Unlock)"
            BW_SES=$(bw unlock --raw)
            if [ $? -eq 0 ] ; then
                export BW_SESSION="$BW_SES"
                echo "Vault unlocked!"
                echo "Syncing Bitwarden vault..."
                bw sync
            else
                echo "Warning: Failed to unlock vault. Secrets will not be provisioned. Proceeding..."
            fi
        fi
    fi
fi

# Initialize and apply dotfiles from current directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "--- Chezmoi Initialization ---"
echo "Initializing and Applying Chezmoi with source: $SCRIPT_DIR"

# Prepare init arguments
INIT_ARGS=("init" "--apply" "--source" "$SCRIPT_DIR" "--force")
[ -n "$ROLE_VAR" ] && INIT_ARGS+=("--data" "role=$ROLE_VAR")
[ -n "$HOSTNAME_VAR" ] && INIT_ARGS+=("--data" "hostname=$HOSTNAME_VAR")
[ -n "$USER_NAME_VAR" ] && INIT_ARGS+=("--data" "name=$USER_NAME_VAR")
[ -n "$EMAIL_ADDRESS_VAR" ] && INIT_ARGS+=("--data" "email=$EMAIL_ADDRESS_VAR")

"$CHEZMOI_BIN" "${INIT_ARGS[@]}"

# Cleanup/Backup legacy default keys to avoid confusion
if [ -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Backing up legacy default key..."
    mv "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.bak"
    mv "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub.bak" 2>/dev/null || true
fi
if [ -f "$HOME/.ssh/id_ed25519_dotfiles" ]; then
    echo "Backing up legacy dotfiles key..."
    mv "$HOME/.ssh/id_ed25519_dotfiles" "$HOME/.ssh/id_ed25519_dotfiles.bak"
    mv "$HOME/.ssh/id_ed25519_dotfiles.pub" "$HOME/.ssh/id_ed25519_dotfiles.pub.bak" 2>/dev/null || true
fi

echo "Setup complete. Please reload your shell."

# Clean up .env file for security
if [ -f ".env" ]; then
    echo "Cleaning up security credentials (.env)..."
    rm .env
fi
