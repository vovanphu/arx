$ErrorActionPreference = "Continue"

$sshDir = "$HOME/.ssh"
$keys = @("id_ed25519_dotfiles_master", "id_ed25519_dotfiles_server")

Write-Host "--- DEBUG SCRIPT START ---" -ForegroundColor Cyan
Write-Host "Home: $HOME"
Write-Host "SSH Dir: $sshDir"

if (Test-Path $sshDir) {
    foreach ($key in $keys) {
        $privateKeyPath = Join-Path $sshDir $key
        $publicKeyPath = "$privateKeyPath.pub"
        
        Write-Host "Checking key: $key at $privateKeyPath" -ForegroundColor Gray

        if (Test-Path $privateKeyPath) {
            Write-Host "  -> Private key FOUND." -ForegroundColor Green
            if (-not (Test-Path $publicKeyPath)) {
                Write-Host "  -> Public key MISSING. Attempting to derive..." -ForegroundColor Yellow
                try {
                    $pubKeyContent = ssh-keygen -y -f "$privateKeyPath"
                    if ($pubKeyContent) {
                        Write-Host "  -> ssh-keygen OUTPUT: $pubKeyContent" -ForegroundColor Cyan
                        $pubKeyContent | Out-File -FilePath $publicKeyPath -Encoding ascii -NoNewline
                        if (Test-Path $publicKeyPath) {
                             Write-Host "  -> SUCCESS: Created $publicKeyPath" -ForegroundColor Green
                        } else {
                             Write-Error "  -> FAILURE: File start created but Test-Path failed?"
                        }
                    } else {
                         Write-Warning "ssh-keygen returned empty content for $key"
                    }
                } catch {
                    Write-Warning "Failed to derive public key for $key. Error: $_"
                }
            } else {
                Write-Host "  -> Public key ALREADY EXISTS." -ForegroundColor DarkGray
            }
        } else {
             Write-Host "  -> Private key NOT FOUND." -ForegroundColor Red
        }
    }
} else {
    Write-Warning "SSH Directory not found at $sshDir"
}
Write-Host "--- DEBUG SCRIPT END ---" -ForegroundColor Cyan
