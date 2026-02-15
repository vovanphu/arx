# Windows Bootstrap Script for Dotfiles
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1
#        OR: irm https://raw.githubusercontent.com/vovanphu/dotfiles/master/install.ps1 | iex

# Ensure scripts can run for this and future sessions
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# --- Remote Bootstrap Logic ---
if (-not $PSScriptRoot) {
    Write-Host "Running in Remote Bootstrap Mode..." -ForegroundColor Cyan
    $DEST_DIR = "$HOME\dotfiles"

    # 0. Load .env from current directory if present (to pass secrets to local script)
    if (Test-Path ".env") {
        Write-Host "Found .env in current directory. Loading credentials..." -ForegroundColor Gray
        $envContent = Get-Content ".env"
        foreach ($line in $envContent) {
            if ($line -match "^BW_PASSWORD=(.*)$") { $env:BW_PASSWORD = $matches[1].Trim() }
            if ($line -match "^BW_EMAIL=(.*)$") { $env:BW_EMAIL = $matches[1].Trim() }
        }
    }
    # 1. Install Git if missing
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Git not found. Installing via Winget..." -ForegroundColor Yellow
        winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
        # Refresh Env
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    
    # 2. Clone Repo
    if (-not (Test-Path $DEST_DIR)) {
        Write-Host "Cloning repository to $DEST_DIR..." -ForegroundColor Cyan
        git clone https://github.com/vovanphu/dotfiles.git $DEST_DIR
    } else {
        Write-Host "Repository already exists at $DEST_DIR. Pulling latest..." -ForegroundColor Cyan
        Set-Location $DEST_DIR
        git pull
    }
    
    # 3. Handover to local script
    Write-Host "Handing over to local install script..." -ForegroundColor Green
    Set-Location $DEST_DIR
    & "$DEST_DIR\install.ps1"
    exit
}
# ------------------------------

# Identify chezmoi binary (Check PATH, then default Winget location)
$CHEZMOI_BIN = Get-Command chezmoi -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if (-not $CHEZMOI_BIN) {
    # Check default Winget installation path as fallback
    $WINGET_PATH = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\twpayne.chezmoi_Microsoft.WinGet.Source_8wekyb3d8bbwe\chezmoi.exe"
    if (Test-Path $WINGET_PATH) {
        $CHEZMOI_BIN = $WINGET_PATH
    }
}

# Install chezmoi if not found
if (-not $CHEZMOI_BIN) {
    Write-Host "Installing chezmoi via Winget..." -ForegroundColor Cyan
    winget install --id twpayne.chezmoi -e --source winget --accept-source-agreements --accept-package-agreements
    
    # Force refresh environment immediately
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Refresh PATH reference
    $CHEZMOI_BIN = Get-Command chezmoi -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $CHEZMOI_BIN) {
        Write-Error "chezmoi was installed but could not be found in PATH. Please try restarting your terminal or manually installing chezmoi."
        exit 1
    }
}

# Pre-install Bitwarden CLI (Required for secret rendering during init)
if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Bitwarden CLI (Required for Secrets)..." -ForegroundColor Cyan
    winget install --id Bitwarden.CLI -e --source winget --accept-source-agreements --accept-package-agreements
    
    # Force refresh environment immediately
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
        Write-Error "Bitwarden CLI was installed but could not be found in PATH. Please try restarting your terminal or manually installing Bitwarden CLI."
        exit 1
    }
}

# Smart Unlock: Help user provision secrets automatically or interactively
if (-not $env:BW_SESSION) {
    Write-Host "`n--- Bitwarden Setup ---" -ForegroundColor Cyan
    
    # 1. Try to load password from environment or .env file
    $password = $env:BW_PASSWORD
    $email = $env:BW_EMAIL
    $envFile = Join-Path $PSScriptRoot ".env"
    
    if ((-not $password -or -not $email) -and (Test-Path $envFile)) {
        Write-Host "Found .env file. Parsing for secrets..." -ForegroundColor Gray
        $envContent = Get-Content $envFile
        foreach ($line in $envContent) {
            if ($line -match "^BW_PASSWORD=(.*)$") {
                $password = $matches[1].Trim()
            }
            if ($line -match "^BW_EMAIL=(.*)$") {
                $email = $matches[1].Trim()
            }
        }
    }

    $shouldPrompt = $true
    if ($password) {
        Write-Host "BW_PASSWORD detected. Attempting automated unlock..." -ForegroundColor Yellow
        # Check status first
        $statusObj = bw status | ConvertFrom-Json
        if ($statusObj.status -eq "unauthenticated") {
             if ($email) {
                 Write-Host "Logging in via email and passwordenv..." -ForegroundColor Gray
                 $env:BW_PASSWORD = $password
                 bw login $email --passwordenv BW_PASSWORD
             } else {
                 Write-Host "Logging in via passwordenv..." -ForegroundColor Gray
                 $env:BW_PASSWORD = $password
                 bw login --passwordenv BW_PASSWORD
             }
        }
        
        $env:BW_PASSWORD = $password
        $output = bw unlock --passwordenv BW_PASSWORD --raw
        if ($LASTEXITCODE -eq 0 -and $output) {
            $env:BW_SESSION = $output
            Write-Host "Vault unlocked automatically!" -ForegroundColor Green
            Write-Host "Syncing Bitwarden vault..." -ForegroundColor Gray
            bw sync
            $shouldPrompt = $false
        } else {
            Write-Warning "Automated unlock failed. Falling back to interactive mode..."
        }
        # Clear sensitive env var after use
        $env:BW_PASSWORD = $null
    }

    # 2. Fallback to interactive prompt if automated unlock skipped or failed
    if ($shouldPrompt) {
        $response = Read-Host "Bitwarden session not detected. Unlock vault now to provision secrets? (y/n)"
        if ($response -eq 'y') {
            # Check status first
            $statusObj = bw status | ConvertFrom-Json
            
            if ($statusObj.status -eq "unauthenticated") {
                Write-Host "You are not logged in to Bitwarden." -ForegroundColor Yellow
                Write-Host ">>> STEP 1: Authenticate Device (Login)" -ForegroundColor Cyan
                bw login
                Write-Host "Login successful." -ForegroundColor Green
            }
            
            # Unlock
            Write-Host ">>> STEP 2: Decrypt Vault (Unlock)" -ForegroundColor Cyan
            $output = bw unlock --raw
            if ($LASTEXITCODE -eq 0 -and $output) {
                $env:BW_SESSION = $output
                Write-Host "Vault unlocked for this session!" -ForegroundColor Green
                Write-Host "Syncing Bitwarden vault..." -ForegroundColor Gray
                bw sync
            } else {
                Write-Warning "Failed to unlock Bitwarden. Secrets will NOT be provisioned. Proceeding with basic installation..."
            }
        }
    }
}

# Initialize and apply dotfiles from current directory
Write-Host "`n--- Chezmoi Initialization ---" -ForegroundColor Cyan
Write-Host "Initializing Chezmoi with source: $PSScriptRoot" -ForegroundColor Cyan
& $CHEZMOI_BIN init --source "$PSScriptRoot" --force

Write-Host "Verifying source path..." -ForegroundColor Gray
& $CHEZMOI_BIN source-path

Write-Host "Applying dotfiles..." -ForegroundColor Green
& $CHEZMOI_BIN apply --force

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply dotfiles. Please check the logs above."
    exit 1
}

# Cleanup default keys to avoid confusion (Migration to id_ed25519_dotfiles_master)
if (Test-Path "$HOME/.ssh/id_ed25519") {
    Write-Host "Backing up legacy default key ($HOME/.ssh/id_ed25519)..." -ForegroundColor Yellow
    Rename-Item "$HOME/.ssh/id_ed25519" "id_ed25519.bak" -Force -ErrorAction SilentlyContinue
    Rename-Item "$HOME/.ssh/id_ed25519.pub" "id_ed25519.pub.bak" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$HOME/.ssh/id_ed25519_dotfiles") {
     Write-Host "Backing up legacy dotfiles key..." -ForegroundColor Yellow
     Rename-Item "$HOME/.ssh/id_ed25519_dotfiles" "id_ed25519_dotfiles.bak" -Force -ErrorAction SilentlyContinue
     Rename-Item "$HOME/.ssh/id_ed25519_dotfiles.pub" "id_ed25519_dotfiles.pub.bak" -Force -ErrorAction SilentlyContinue
}

Write-Host "Applying PowerShell Profile dynamically..." -ForegroundColor Green
$PROFILE_DIR = Split-Path $PROFILE -Parent
if (-not (Test-Path $PROFILE_DIR)) { New-Item -ItemType Directory -Force -Path $PROFILE_DIR | Out-Null }

# Render template using chezmoi and write to the active profile path
$templatePath = Join-Path $PSScriptRoot "powershell_profile.ps1.tmpl"
if (Test-Path $templatePath) {
    Write-Host "- Rendering profile template..." -ForegroundColor Gray
    $rendered = Get-Content $templatePath -Raw | & $CHEZMOI_BIN execute-template --source $PSScriptRoot
    
    if ($LASTEXITCODE -eq 0 -and $rendered) {
        $rendered | Set-Content -Path $PROFILE -Force -Encoding UTF8
        Write-Host "Profile applied to: $PROFILE" -ForegroundColor Green
    } else {
        Write-Error "Failed to render PowerShell profile template. Keeping existing profile."
    }
}

Write-Host "Setup complete. Please restart your terminal to reload environment variables." -ForegroundColor Yellow
