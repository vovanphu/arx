#!/bin/bash
# Usage: ./install.sh
#        OR: sh -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/arx/master/install.sh)"

# --- Configuration URLs (can be overridden via environment variables) ---
REPO_URL="${ARX_REPO_URL:-https://github.com/vovanphu/arx.git}"
CHEZMOI_INSTALL_URL="${CHEZMOI_URL:-https://get.chezmoi.io}"
BITWARDEN_CLI_URL="${BW_CLI_URL:-https://vault.bitwarden.com/download/?app=cli&platform=linux}"

# --- Global Settings ---
# Ensure .env is deleted on exit (secure cleanup)
trap 'rm -f .env' EXIT

# --- Remote Bootstrap Logic ---
if [ ! -f "install.sh" ]; then 
    echo "Running in Remote Bootstrap Mode..."
    DEST_DIR="$HOME/arx"
    
    if [ -f ".env" ] && [ ! -L ".env" ]; then
        echo "Found .env in current directory. Loading credentials..."
        # Export variables to sub-processes (safely with set -a)
        set -a
        # shellcheck disable=SC1091
        . ".env"
        set +a
    elif [ -L ".env" ]; then
        echo "Warning: .env is a symlink. Skipping for security reasons."
    fi

    if ! command -v git &> /dev/null; then
        echo "Git not found. Installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y git
        else
            echo "Error: Git is required. Please install Git manually."
            exit 1
        fi
    fi
    
    if [ ! -d "$DEST_DIR" ]; then
        echo "Cloning repository to $DEST_DIR..."
        git clone "$REPO_URL" "$DEST_DIR"
    else
        echo "Repo exists. Updating..."
        cd "$DEST_DIR" || exit
        if ! git pull; then
            echo "Warning: git pull failed. Using existing local version."
        fi
    fi
    
    echo "Handing over to local install script..."
    if [ -f ".env" ] && [ ! -L ".env" ]; then
        cp ".env" "$DEST_DIR/"
    fi
    cd "$DEST_DIR" || exit
    exec bash "install.sh"
    exit
fi

# --- Local Execution Logic ---
export PATH="$HOME/.local/bin:$PATH"
CHEZMOI_BIN="$HOME/.local/bin/chezmoi"

if [ ! -f "$CHEZMOI_BIN" ]; then
    echo "Installing chezmoi..."
    mkdir -p "$HOME/.local/bin"
    sh -c "$(curl -fsLS "$CHEZMOI_INSTALL_URL")" -- -b "$HOME/.local/bin"
fi

if ! command -v bw &> /dev/null; then
    echo "Installing Bitwarden CLI..."
    if command -v apt-get &> /dev/null; then
        if ! command -v unzip &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y unzip
        fi
        curl -L "$BITWARDEN_CLI_URL" -o bw.zip
        unzip -o bw.zip
        chmod +x bw
        mv bw "$HOME/.local/bin/"
        rm bw.zip
    fi
fi

# --- Bitwarden Setup ---
if [ -z "${BW_SESSION:-}" ]; then
    echo ""
    echo "--- Bitwarden Setup ---"
    
    # Load variables
    PASSWORD="${BW_PASSWORD:-}"
    EMAIL="${BW_EMAIL:-}"
    ROLE_VAR="${ROLE:-}"
    HOSTNAME_VAR="${HOSTNAME:-}"
    USER_NAME_VAR="${USER_NAME:-}"
    EMAIL_ADDRESS_VAR="${EMAIL_ADDRESS:-}"

    if [ -f ".env" ] && [ ! -L ".env" ]; then
        echo "Found .env file. Parsing for automation variables..."
        parse_var() {
            local var_name="$1"
            local value
            # Safely parse with proper quoting
            value=$(grep "^${var_name}=" .env | head -n1 | cut -d'=' -f2- | sed -e "s/#.*$//" -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//" -e "s/^['\"]//" -e "s/['\"]$//")
            printf '%s' "$value"
        }
        [ -z "$PASSWORD" ] && PASSWORD="$(parse_var "BW_PASSWORD")"
        [ -z "$EMAIL" ] && EMAIL="$(parse_var "BW_EMAIL")"
        [ -z "$ROLE_VAR" ] && ROLE_VAR="$(parse_var "ROLE")"
        [ -z "$HOSTNAME_VAR" ] && HOSTNAME_VAR="$(parse_var "HOSTNAME")"
        [ -z "$USER_NAME_VAR" ] && USER_NAME_VAR="$(parse_var "USER_NAME")"
        [ -z "$EMAIL_ADDRESS_VAR" ] && EMAIL_ADDRESS_VAR="$(parse_var "EMAIL_ADDRESS")"

        # Validate email addresses if provided
        if [ -n "$EMAIL" ]; then
            if ! [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                echo "Warning: BW_EMAIL '$EMAIL' does not appear to be a valid email address."
            fi
        fi
        if [ -n "$EMAIL_ADDRESS_VAR" ]; then
            if ! [[ "$EMAIL_ADDRESS_VAR" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                echo "Warning: EMAIL_ADDRESS '$EMAIL_ADDRESS_VAR' does not appear to be a valid email address."
            fi
        fi
    elif [ -L ".env" ]; then
        echo "Warning: .env is a symlink. Skipping for security reasons."
    fi

    SHOULD_PROMPT=true
    if [ -n "$PASSWORD" ]; then
        echo "BW_PASSWORD detected. Attempting automated unlock..."
        if bw status | grep -q "unauthenticated"; then
            export BW_PASSWORD="$PASSWORD"
            if [ -n "$EMAIL" ]; then
                bw login "$EMAIL" --passwordenv BW_PASSWORD
            else
                bw login --passwordenv BW_PASSWORD
            fi
        fi
    
        export BW_PASSWORD="$PASSWORD"
        # Noise-free capture
        BW_SES=$(bw unlock --passwordenv BW_PASSWORD --raw | tail -n 1)
        # Regex validation for Base64 session key
        if [[ $BW_SES =~ ^[A-Za-z0-9+/=]{20,}$ ]]; then
            export BW_SESSION="$BW_SES"
            echo "Vault unlocked & synced!"
            bw sync | grep -v "Syncing"
            SHOULD_PROMPT=false
        else
            echo "Warning: Automated unlock failed."
        fi
        unset BW_PASSWORD
    fi

    if [ "$SHOULD_PROMPT" = true ] && [ -z "$BW_SESSION" ]; then
        read -p "Bitwarden session not detected. Unlock now? (y/n) " -r
        if [[ $REPLY =~ ^[Yy] ]]; then
            if bw status | grep -q "unauthenticated"; then bw login; fi
            BW_SES=$(bw unlock --raw | tail -n 1)
            if [[ $BW_SES =~ ^[A-Za-z0-9+/=]{20,}$ ]]; then
                export BW_SESSION="$BW_SES"
                echo "Vault unlocked!"
                bw sync | grep -v "Syncing"
            fi
        fi
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# --- Chezmoi Initialization (The "Invisible" Version) ---
echo "--- Chezmoi Initialization ---"

# Export environment variables for the template to read directly (Short-Circuit Logic)
export ROLE="$ROLE_VAR"
export HOSTNAME="$HOSTNAME_VAR"
export USER_NAME="$USER_NAME_VAR"
export EMAIL_ADDRESS="$EMAIL_ADDRESS_VAR"

if [ -n "$ROLE_VAR" ] || [ -n "$HOSTNAME_VAR" ] || [ -n "$EMAIL_ADDRESS_VAR" ]; then
    echo "Baking environment variables into template context..."
    [ -n "$EMAIL_ADDRESS_VAR" ] && echo "  > EMAIL: $EMAIL_ADDRESS_VAR"
    [ -n "$ROLE_VAR" ]          && echo "  > ROLE : $ROLE_VAR"
    [ -n "$HOSTNAME_VAR" ]      && echo "  > HOST : $HOSTNAME_VAR"
fi

echo "Initializing Chezmoi..."
# Change to HOME to avoid chezmoi scanning current directory for dotfiles
cd "$HOME" || exit
"$CHEZMOI_BIN" init --force --source="$SCRIPT_DIR"
if [ $? -ne 0 ]; then echo "Error: Chezmoi init failed."; exit 1; fi

echo "Applying dotfiles..."

# Backup existing .ssh directory with timestamp (if exists and has content)
if [ -d "$HOME/.ssh" ] && [ -n "$(ls -A "$HOME/.ssh" 2>/dev/null)" ]; then
    BACKUP_DIR="$HOME/.ssh.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing SSH configuration to $BACKUP_DIR..."
    cp -a "$HOME/.ssh" "$BACKUP_DIR"
    echo "Backup created. You can restore with: rm -rf ~/.ssh && mv $BACKUP_DIR ~/.ssh"
fi

# Ensure BW_SESSION is still valid before applying
if [ -n "$BW_SESSION" ]; then
    echo "Verifying Bitwarden session..."
    if ! bw status 2>&1 | grep -q '"status":"unlocked"'; then
        echo "Warning: Bitwarden session expired. Templates requiring vault access may fail."
    fi
fi
if ! "$CHEZMOI_BIN" apply --source="$SCRIPT_DIR" --force; then
    echo "Warning: Chezmoi apply encountered errors. Some dotfiles may not be configured correctly."
    echo "You can re-run: chezmoi apply --force"
fi

# Security: Clear sensitive environment variables
if [ -n "$BW_SESSION" ]; then
    echo "Clearing Bitwarden session from environment..."
    unset BW_SESSION
fi
if [ -n "$BW_PASSWORD" ]; then
    unset BW_PASSWORD
fi

echo -e "\n[DONE] Setup complete! Please reload your shell."
