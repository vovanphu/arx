# Dotfiles

My personal dotfiles managed by [chezmoi](https://chezmoi.io).
**Motto**: "One Config to Rule Them All."

## Installation

### 1. Prerequisites
*   **Bitwarden Account**: You must have a Bitwarden account. The checkout/install scripts will handle the CLI installation and prompting for you!
    ```powershell
    # Windows
    bw login
    # Done! The install script will ask to 'bw unlock' for you.
    ```

### 2. Bootstrap
#### Windows (PowerShell)
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/vovanphu/dotfiles/main/install.ps1'))
```

#### Linux / WSL
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply vovanphu
```

## Role Selection
During initialization, you will be prompted to choose a **Machine Role**:

| Role | Description | Key Features |
| :--- | :--- | :--- |
| **`commander`** | XPS 13 / Macbook | **Control Center**. Full admin tools, Master SSH Keys. |
| **`workstation`** | Company PC | **Heavy Dev**. Compilers, Docker, Master SSH Keys. |
| **`mobilelab`** | XPS 15 (Debian) | **Infrastructure**. KVM, K8s tools, Deploy Keys. |
| **`server`** | VPS / Gateway | **Headless**. Nginx, Tailscale, minimal keys. |

## Features
*   **Automated Secrets**: Pulls SSH Keys directly from Bitwarden Secure Notes (`ssh-key-master`, `ssh-key-server`).
*   **Smart Packages**: Installs only what you need based on the selected Role.
*   **Unified Shell**: Starship prompt & aliases consistent across PowerShell and Bash.
