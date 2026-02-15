# Dotfiles

My personal dotfiles managed by [chezmoi](https://chezmoi.io).
**Motto**: "One Config to Rule Them All."

## 🚀 Installation

### 1. Prerequisites
*   **Bitwarden Account**: You need a Bitwarden account with the following items:
    *   **Secure Notes**: `ssh-key-master-ed25519` and `ssh-key-server-ed25519` (Private Keys).
    *   **Login**: `tailscale-auth-key` (Reusable key). *Note: Must be rotated every 90 days.*
*   **Internet**: Required for package downloads.

### 2. Quick Start

#### 🪟 Windows (PowerShell Administrator)
The script automatically installs `chezmoi`, `bitwarden-cli`, `git`, `tailscale`, and provisions keys.

*   **Option A: Interactive** (Prompts for secrets):
    ```powershell
    irm https://raw.githubusercontent.com/vovanphu/dotfiles/master/install.ps1 | iex
    ```
*   **Option B: Automated** (Zero-touch, will auto-delete `.env`):
    ```powershell
    @("BW_EMAIL=user@mail.com", "BW_PASSWORD=pass", "ROLE=centaur", "HOSTNAME=chiron", "USER_NAME='vovanphu'", "EMAIL_ADDRESS='vovanphu1012@gmail.com'") | Set-Content .env; irm https://raw.githubusercontent.com/vovanphu/dotfiles/master/install.ps1 | iex
    ```

#### 🐧 Linux / WSL
Handles dependency checks, Bitwarden authentication, and SSH agent reuse.

*   **Option A: Interactive**:
    ```bash
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/dotfiles/master/install.sh)"
    ```
*   **Option B: Automated** (Zero-touch, will auto-delete `.env`):
    ```bash
    echo "BW_EMAIL=user@mail.com" > .env; echo "BW_PASSWORD=pass" >> .env; echo "ROLE=centaur" >> .env; echo "USER_NAME='vovanphu'" >> .env; bash -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/dotfiles/master/install.sh)"
    ```

---

## 🤖 Role Selection: "The Mythos"
We use a **Mythological Role System** to categorize machines. Choose wisely:

| Role | Core Concept | Typical Use Case |
| :--- | :--- | :--- |
| **`centaur`** | **The Wise Commander** | Laptop/Mac. Admin, Management. |
| **`chimera`** | **The Hybrid Beast** | Windows Workstation + WSL. |
| **`hydra`** | **The Undying Cluster** | Proxmox Host. |
| **`griffin`** | **The Guardian** | Portable Debit/KVM Lab. |
| **`cyclops`** | **The Strong** | General Purpose Server. |
| *Server Fleet* | *Specialized Units* | `kraken` (Storage), `cerberus` (Bastion), `golem` (DB), `minion` (Worker), `siren` (Web). |

## ✨ Features
*   **🔐 Automated Secrets**: Pulls SSH Keys directly from Bitwarden (`ssh-key-master-ed25519` -> `~/.ssh/id_ed25519_dotfiles_master`).
*   **📦 Centralized Packages**: All software definitions live in [`packages.yaml`](packages.yaml), separating data from installation scripts.
*   **🏷️ Mythological Name Pools**: Curated lists of names (e.g., `chiron`, `polyphemus`) for each role, ensuring unique and thematic hostnames.
*   **🌐 Zero-Touch Connectivity**: **Tailscale** automatically authenticates via Bitwarden and configures MagicDNS without manual login.
*   **🛡️ Namespaced Keys**: Uses explicit filenames to avoid conflicts with system defaults.
*   **🔧 Local Overrides**: Supports `~/.ssh/config.local` for custom SSH hosts that are not managed by dotfiles.
*   **🧠 Intelligent Scripts**:
    *   **Safety First**: Backs up old SSH keys instead of deleting them. Soft-fails if Bitwarden is unreachable.
    *   **Hostname Sync**: Detects mismatch between config and OS hostname, prompting for a safe rename.
    *   **Windows**: Auto-starts `ssh-agent`, handles `bw login/unlock/sync`.
    *   **WSL**: Implements **Socket Reuse** so all terminal tabs share one `ssh-agent` session.
    *   **Self-Healing**: Automatically derives SSH Public keys (`.pub`) locally whenever private keys change.
    *   **GUI Ready**: Automatically installs **FiraCode Nerd Font** on Windows and Linux (Interactive roles).
*   **🐚 Unified Shell**: Starship prompt & aliases consistent across PowerShell and Bash.

## ❓ Troubleshooting

### Factory Reset (Re-select Role/Hostname)
The system remembers your choices in `~/.config/chezmoi/chezmoi.toml`. To force a fresh start:
*   **Linux**: `rm ~/.config/chezmoi/chezmoi.toml`
*   **Windows**: `Remove-Item $env:USERPROFILE\.config\chezmoi\chezmoi.toml`

### SSH Guest/VM Setup
If you need to configure SSH for a Windows VM or a new target machine, refer to the following guide:
*   [**Install OpenSSH Server on Windows**](docs/ssh-windows-setup.md)

Then run the install script again.
