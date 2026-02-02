# Windows Bootstrap Script for Dotfiles
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1

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
    winget install chezmoi --accept-source-agreements --accept-package-agreements
    
    Write-Host "Refreshing Environment Variables..." -ForegroundColor Gray
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Refresh PATH reference
    $CHEZMOI_BIN = Get-Command chezmoi -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $CHEZMOI_BIN) { $CHEZMOI_BIN = "chezmoi" } 
}

# Pre-install Bitwarden CLI (Required for secret rendering during init)
if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Bitwarden CLI (Required for Secrets)..." -ForegroundColor Cyan
    winget install Bitwarden.CLI --accept-source-agreements --accept-package-agreements
}

# Smart Unlock: Help user provision secrets immediately
if (-not $env:BW_SESSION) {
    Write-Host "`n--- Bitwarden Setup ---" -ForegroundColor Cyan
    $response = Read-Host "Bitwarden session not detected. Unlock vault now to provision secrets? (y/n)"
    if ($response -eq 'y') {
        # Check status first
        $statusObj = bw status | ConvertFrom-Json
        
        if ($statusObj.status -eq "unauthenticated") {
            Write-Host "You are not logged in to Bitwarden." -ForegroundColor Yellow
            bw login
        }
        
        # Unlock
        $output = bw unlock --raw
        if ($LASTEXITCODE -eq 0 -and $output) {
            $env:BW_SESSION = $output
            Write-Host "Vault unlocked for this session!" -ForegroundColor Green
        } else {
            Write-Error "Failed to unlock Bitwarden. Secrets will NOT be provisioned."
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

Write-Host "Applying PowerShell Profile dynamically..." -ForegroundColor Green
$PROFILE_DIR = Split-Path $PROFILE -Parent
if (-not (Test-Path $PROFILE_DIR)) { New-Item -ItemType Directory -Force -Path $PROFILE_DIR | Out-Null }

# Render template using chezmoi and write to the active profile path
$templatePath = Join-Path $PSScriptRoot "powershell_profile.ps1.tmpl"
if (Test-Path $templatePath) {
    Write-Host "- Rendering profile template..." -ForegroundColor Gray
    $rendered = Get-Content $templatePath -Raw | & $CHEZMOI_BIN execute-template --source $PSScriptRoot
    
    if ($LASTEXITCODE -eq 0 -and $rendered) {
        $rendered | Set-Content -Path $PROFILE -Force
        Write-Host "Profile applied to: $PROFILE" -ForegroundColor Green
    } else {
        Write-Error "Failed to render PowerShell profile template. Keeping existing profile."
    }
}

Write-Host "Setup complete. Please restart your terminal." -ForegroundColor Yellow
