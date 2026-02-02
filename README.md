# Dotfiles

My personal dotfiles managed by [chezmoi](https://chezmoi.io).
**Motto**: "One Config to Rule Them All."

## 🚀 Installation

### 1. Prerequisites
*   **Bitwarden Account**: You must have a Bitwarden account with the necessary "Secure Notes" for SSH keys.
*   **Internet**: Obviously.

### 2. Quick Start

#### 🪟 Windows (PowerShell Administrator)
The script will automatically install `chezmoi`, `bitwarden-cli`, `git`, configure `ssh-agent`, and provision your keys.

```powershell
# 1. Clone the repo (or download zip if no git yet)
git clone https://github.com/vovanphu/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"

# 2. Run the magic script
.\install.ps1
```

#### 🐧 Linux / WSL
The script handles dependency checks (`unzip`, `curl`), Bitwarden login, and SSH agent reuse for WSL.

```bash
# 1. Clone the repo
git clone https://github.com/vovanphu/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Run the magic script
./install.sh
```

---

## 🤖 Role Selection
During initialization, you will be prompted to choose a **Machine Role**:

| Role | Description | Key Features |
| :--- | :--- | :--- |
| **`commander`** | XPS 13 / Macbook | **Control Center**. Full admin tools, Master SSH Keys. |
| **`workstation`** | Company PC | **Heavy Dev**. Compilers, Docker, Master SSH Keys. |
| **`mobilelab`** | XPS 15 (Debian) | **Infrastructure**. KVM, K8s tools, Server Keys. |
| **`server`** | VPS / Gateway | **Headless**. Nginx, minimal keys. |

## ✨ Features
*   **🔐 Automated Secrets**: Pulls SSH Keys directly from Bitwarden (`ssh-key-master-ed25519` -> `~/.ssh/id_ed25519_dotfiles_master`).
*   **🛡️ Namespaced Keys**: Uses explicit filenames to avoid conflicts with system defaults.
*   **🔧 Local Overrides**: Supports `~/.ssh/config.local` for custom SSH hosts that are not managed by dotfiles.
*   **🧠 Intelligent Scripts**:
    *   **Windows**: Auto-starts `ssh-agent`, handles `bw login/unlock/sync`.
    *   **WSL**: Implements **Socket Reuse** so all terminal tabs share one `ssh-agent` session.
    *   **Safety**: Validates line-endings (LF) for keys to prevent `libcrypto` errors.
    *   **Self-Healing**: Automatically derives SSH Public keys (`.pub`) locally whenever private keys change, ensuring `ssh-copy-id` always works.
    *   **GUI Ready**: Automatically installs **FiraCode Nerd Font** on Windows and Linux (non-server roles) to ensure the terminal looks perfect.
*   **🐚 Unified Shell**: Starship prompt & aliases consistent across PowerShell and Bash.
