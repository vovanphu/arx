# Windows Bootstrap Script for Dotfiles
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# --- Remote Bootstrap Logic ---
if (-not $PSScriptRoot) {
    Write-Host "Running in Remote Bootstrap Mode..." -ForegroundColor Cyan
    $DEST_DIR = "$HOME\dotfiles"

    if (Test-Path ".env") {
        Write-Host "Found .env in current directory. Loading automation variables..." -ForegroundColor Gray
        $envContent = Get-Content ".env"
        foreach ($line in $envContent) {
            # Trim comments and whitespace
            $cleanLine = $line.Split('#')[0].Trim()
            if ($cleanLine -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim().Trim(" `"'")
                if ($key -eq "BW_PASSWORD")   { $env:BW_PASSWORD = $val }
                if ($key -eq "BW_EMAIL")      { $env:BW_EMAIL = $val }
                if ($key -eq "ROLE")          { $env:ROLE = $val }
                if ($key -eq "HOSTNAME")      { $env:HOSTNAME = $val }
                if ($key -eq "USER_NAME")     { $env:USER_NAME = $val }
                if ($key -eq "EMAIL_ADDRESS") { $env:EMAIL_ADDRESS = $val }
            }
        }
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Git not found. Installing via Winget..." -ForegroundColor Yellow
        winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    
    if (-not (Test-Path $DEST_DIR)) {
        Write-Host "Cloning repository to $DEST_DIR..." -ForegroundColor Gray
        git clone https://github.com/vovanphu/dotfiles.git $DEST_DIR
    } else {
        Write-Host "Repository exists. Updating..." -ForegroundColor Gray
        Set-Location $DEST_DIR; git pull
    }
    
    Write-Host "Handing over to local install script..." -ForegroundColor Green
    # Propagate .env if present
    if (Test-Path ".env") { 
        Write-Host "Propagating .env to repository directory..." -ForegroundColor Gray
        Copy-Item ".env" -Destination $DEST_DIR -Force 
    }
    Set-Location $DEST_DIR
    & ".\install.ps1"
    return 
}

# --- Local Execution Logic ---
# Ensure target paths exist
$LOCAL_BIN = "$HOME/.local/bin"
if (-not (Test-Path $LOCAL_BIN)) { New-Item -ItemType Directory -Force -Path $LOCAL_BIN | Out-Null }

$CHEZMOI_BIN = Get-Command chezmoi -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $CHEZMOI_BIN) {
    Write-Host "Installing chezmoi via Winget..." -ForegroundColor Cyan
    winget install --id twpayne.chezmoi -e --source winget --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $CHEZMOI_BIN = Get-Command chezmoi -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Bitwarden CLI (Required for Secrets)..." -ForegroundColor Cyan
    winget install --id Bitwarden.CLI -e --source winget --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# --- Installation Block (with Secure Cleanup) ---
$envFile = Join-Path $PSScriptRoot ".env"
try {
    # 0. Load Variables
    $password = $env:BW_PASSWORD; $email = $env:BW_EMAIL; $role = $env:ROLE; $hostname = $env:HOSTNAME; $userName = $env:USER_NAME; $emailAddress = $env:EMAIL_ADDRESS
    $shouldPrompt = $true

    if (Test-Path $envFile) {
        Write-Host "`n--- Bitwarden Setup ---" -ForegroundColor Cyan
        Write-Host "Found .env file. Parsing for automation variables..." -ForegroundColor Gray
        $envContent = Get-Content $envFile
        foreach ($line in $envContent) {
            $cleanLine = $line.Split('#')[0].Trim()
            if ($cleanLine -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim().Trim(" `"'")
                if ($key -eq "BW_PASSWORD")   { $password = $val }
                if ($key -eq "BW_EMAIL")      { $email = $val }
                if ($key -eq "ROLE")          { $role = $val }
                if ($key -eq "HOSTNAME")      { $hostname = $val }
                if ($key -eq "USER_NAME")     { $userName = $val }
                if ($key -eq "EMAIL_ADDRESS") { $emailAddress = $val }
            }
        }

        if ($role -or $hostname -or $userName) {
            Write-Host "Automation Detected: ROLE=$role, HOSTNAME=$hostname, USER=$userName" -ForegroundColor Cyan
        }

        if ($password) {
            Write-Host "BW_PASSWORD detected. Attempting automated Bitwarden unlock..." -ForegroundColor Yellow
            $statusObj = bw status | ConvertFrom-Json
            if ($statusObj.status -eq "unauthenticated") {
                Write-Host "Logging in via email and passwordenv..." -ForegroundColor Gray
                if ($email) { bw login $email --passwordenv BW_PASSWORD } else { bw login --passwordenv BW_PASSWORD }
            }
            
            $env:BW_PASSWORD = $password
            # FIX: Capture output as string and take last line to remove CLI chatter
            $output = (bw unlock --passwordenv BW_PASSWORD --raw | Out-String).Trim() -split "`n" | Select-Object -Last 1
            
            # Regex check: Ensure we captured a valid Base64 session key
            if ($output -match '^[A-Za-z0-9+/=]{20,}$') {
                $env:BW_SESSION = $output.Trim()
                Write-Host "Vault unlocked & synced!" -ForegroundColor Green
                bw sync | Out-Null
                $shouldPrompt = $false
            }
            $env:BW_PASSWORD = $null
        }
    }

    # Fallback to interactive prompt if needed
    if ($shouldPrompt -and (-not $env:BW_SESSION)) {
        $response = Read-Host "Bitwarden session not detected. Unlock now? (y/n)"
        if ($response -eq 'y') {
            $statusObj = bw status | ConvertFrom-Json
            if ($statusObj.status -eq "unauthenticated") { bw login }
            Write-Host ">>> STEP 2: Decrypt Vault (Unlock)" -ForegroundColor Cyan
            $output = (bw unlock --raw | Out-String).Trim() -split "`n" | Select-Object -Last 1
            if ($output -match '^[A-Za-z0-9+/=]{20,}$') {
                $env:BW_SESSION = $output.Trim()
                Write-Host "Vault unlocked!" -ForegroundColor Green
                bw sync | Out-Null
            }
        }
    }

    # --- Chezmoi Initialization (The "Invisible" Version) ---
    Write-Host "`n--- Chezmoi Initialization ---" -ForegroundColor Cyan
    
    # Set environment variables for the template to read directly
    $env:ROLE = $role
    $env:HOSTNAME = $hostname
    $env:USER_NAME = $userName
    $env:EMAIL_ADDRESS = $emailAddress

    Write-Host "Initializing chezmoi with environment variables..." -ForegroundColor Gray
    & $CHEZMOI_BIN init --force --source="$PSScriptRoot"
    if ($LASTEXITCODE -ne 0) { throw "Chezmoi init failed. Check for template errors." }

    Write-Host "Applying dotfiles..." -ForegroundColor Green
    & $CHEZMOI_BIN apply --source="$PSScriptRoot" --force
    if ($LASTEXITCODE -ne 0) { throw "Failed to apply dotfiles." }

    # --- Post-Install Tasks ---
    # Migration/Backup
    if (Test-Path "$HOME/.ssh/id_ed25519") {
        Write-Host "Backing up legacy default keys..." -ForegroundColor Yellow
        Rename-Item "$HOME/.ssh/id_ed25519" "id_ed25519.bak" -Force -ErrorAction SilentlyContinue
        Rename-Item "$HOME/.ssh/id_ed25519.pub" "id_ed25519.pub.bak" -Force -ErrorAction SilentlyContinue
    }

    # Profile Rendering
    $templatePath = Join-Path $PSScriptRoot "powershell_profile.ps1.tmpl"
    if (Test-Path $templatePath) {
        Write-Host "Rendering PowerShell Profile..." -ForegroundColor Gray
        $rendered = Get-Content $templatePath -Raw | & $CHEZMOI_BIN execute-template --source $PSScriptRoot
        if ($LASTEXITCODE -eq 0 -and $rendered) {
            $PROFILE_DIR = Split-Path $PROFILE -Parent
            if (-not (Test-Path $PROFILE_DIR)) { New-Item -ItemType Directory -Force $PROFILE_DIR | Out-Null }
            $rendered | Set-Content -Path $PROFILE -Force -Encoding UTF8
            Write-Host "Profile applied: $PROFILE" -ForegroundColor Green
        }
    }

    Write-Host "`n✨ Setup Complete! Please restart your terminal." -ForegroundColor Cyan
}
catch {
    Write-Error "Error occurred: $($_.Exception.Message)"
    exit 1
}
finally {
    # LUÔN LUÔN xóa file .env dù thành công hay thất bại
    if (Test-Path $envFile) {
        Write-Host "Cleaning up security credentials (.env)..." -ForegroundColor Gray
        Remove-Item $envFile -Force
    }
}
