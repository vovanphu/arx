# Dotfiles

My personal dotfiles managed by [chezmoi](https://chezmoi.io).
**Motto**: "One Config to Rule Them All."

## 🚀 Installation

### 1. Prerequisites
*   **Bitwarden Account**: You need a Bitwarden account with the following items:
    *   **Secure Notes**: `ssh-key-master-ed25519` and `ssh-key-server-ed25519` (Private Keys).
        *   Each item must have a **custom field** named exactly `public_key` containing the full SSH public key string (e.g., `ssh-ed25519 AAAA... user@host`). This field is read by `authorized_keys.tmpl` to populate `~/.ssh/authorized_keys` on machines that accept SSH connections. Without it, `authorized_keys` will be empty.
    *   **Password**: `tailscale-auth-key` (One-off key). *Generate a new key for each new machine setup. Enable "Pre-approved" so devices auto-authorize.*
*   **Internet**: Required for package downloads.

### 2. Quick Start

#### 🪟 Windows (PowerShell Administrator)
The script automatically installs `chezmoi`, `bitwarden-cli`, `git`, `tailscale`, and provisions keys.

*   **Option A: Interactive** (Prompts for secrets):
    ```powershell
    irm https://raw.githubusercontent.com/vovanphu/arx/master/install.ps1 | iex
    ```
*   **Option B: Automated** (Zero-touch, will auto-delete `.env`):
    ```powershell
    @("BW_EMAIL=user@mail.com", "BW_PASSWORD=pass", "ROLE=centaur", "HOSTNAME=chiron", "USER_NAME='vovanphu'", "EMAIL_ADDRESS='vovanphu1012@gmail.com'") | Set-Content .env; irm https://raw.githubusercontent.com/vovanphu/arx/master/install.ps1 | iex
    ```
*   **Option C: Direct Environment Injection** (No temporary files):
    ```powershell
    $env:BW_EMAIL="user@mail.com"; $env:BW_PASSWORD="pass"; $env:ROLE="centaur"; $env:HOSTNAME="chiron"; $env:USER_NAME="vovanphu"; $env:EMAIL_ADDRESS="vovanphu1012@gmail.com"; irm https://raw.githubusercontent.com/vovanphu/arx/master/install.ps1 | iex
    ```

#### 🐧 Linux / WSL
Handles dependency checks, Bitwarden authentication, and SSH agent reuse.

*   **Option A: Interactive**:
    ```bash
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/arx/master/install.sh)"
    ```
*   **Option B: Automated** (Zero-touch, will auto-delete `.env`):
    ```bash
    echo "BW_EMAIL=user@mail.com" > .env; echo "BW_PASSWORD=pass" >> .env; echo "ROLE=centaur" >> .env; echo "USER_NAME='vovanphu'" >> .env; bash -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/arx/master/install.sh)"
    ```
*   **Option C: Direct Environment Injection** (No temporary files):
    ```bash
    export BW_EMAIL="user@mail.com" BW_PASSWORD="pass" ROLE="centaur" USER_NAME="vovanphu" EMAIL_ADDRESS="vovanphu1012@gmail.com" && bash -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/arx/master/install.sh)"
    ```

---

## 🤖 Role Selection: "The Mythos"
We use a **Mythological Role System** to categorize machines. The system uses **capability-based configuration** instead of hardcoded role checks.

### Role Taxonomy
All 10 roles are centrally defined with capabilities in [`.chezmoi.yaml.tmpl`](.chezmoi.yaml.tmpl). Each role has 5 capabilities:
- `has_master_key` - Gets master SSH key
- `has_server_key` - Gets server SSH key
- `receives_ssh` - Has authorized_keys configured
- `is_server` - Server-specific configuration (headless, limited shell history)
- `install_desktop_tools` - Installs GUI applications

| Role | Core Concept | Typical Use Case | Capabilities |
| :--- | :--- | :--- | :--- |
| **`centaur`** | **The Wise Commander** | Laptop/Mac. Admin, Management. | 🔑 Master Key, 🖥️ Desktop |
| **`chimera`** | **The Hybrid Beast** | Windows Workstation + WSL. | 🔑 Master + Server Keys, 🔐 SSH, 🖥️ Desktop |
| **`griffin`** | **The Guardian** | Portable Debit/KVM Lab. | 🔑 Server Key, 🔐 SSH, 🖥️ Desktop |
| **`hydra`** | **The Undying Cluster** | Proxmox Host. | 🔑 Server Key, 🔐 SSH, 🖧 Server |
| **`cyclops`** | **The Strong** | General Purpose Server. | 🔑 Server Key, 🔐 SSH, 🖧 Server |
| **`kraken`** | **The Deep Storage** | Database Server. | 🔑 Server Key, 🔐 SSH, 🖧 Server |
| **`cerberus`** | **The Guardian Gate** | Security/Firewall Server. | 🔑 Server Key, 🔐 SSH, 🖧 Server |
| **`golem`** | **The Builder** | CI/CD Server. | 🔑 Server Key, 🔐 SSH, 🖧 Server |
| **`minion`** | **The Worker** | Compute Node. | 🔑 Server Key, 🔐 SSH, 🖧 Server |
| **`siren`** | **The Watchful** | Monitoring Server. | 🔑 Server Key, 🔐 SSH, 🖧 Server |

📖 **Full Documentation:** See [ROLES.md](ROLES.md) for detailed role definitions, how to add new roles, and template usage examples.

## ✨ Features

### 🏗️ Architecture
*   **🎯 Centralized Role Taxonomy**: Single source of truth for all role definitions in `.chezmoi.yaml.tmpl`
*   **🔧 Capability-Based Templates**: Templates use capabilities (e.g., `.has_master_key`) instead of hardcoded roles
*   **📦 Centralized Packages**: All software definitions live in [`packages.yaml`](packages.yaml), separating data from installation scripts
*   **🔄 File-Based Merge Logic**: SSH merge scripts detect files, not roles (works for any role without code changes)

### 🔐 Security & SSH Management
*   **🔑 Automated Secrets**: Pulls SSH Keys directly from Bitwarden (`ssh-key-master-ed25519` -> `~/.ssh/id_ed25519_dotfiles_master`)
*   **🛡️ Namespaced Keys**: Uses explicit filenames to avoid conflicts with system defaults
*   **💾 Smart Backup**: Automatically backs up `~/.ssh` before deployment (timestamped: `~/.ssh.backup.YYYYMMDD_HHMMSS`)
*   **🔄 Intelligent Merge**: Preserves old SSH keys and custom config entries when re-installing
*   **🧹 Backup Retention**: Automatically keeps only 3 most recent backups (prevents disk bloat)
*   **🔒 Session Cleanup**: Clears `BW_SESSION` after installation (both success and error paths)
*   **🪟 Windows Admin Fix**: Auto-configures `C:\ProgramData\ssh\administrators_authorized_keys` for admin accounts
*   **🔧 Local Overrides**: Supports `~/.ssh/config.local` for custom SSH hosts not managed by dotfiles

### 🌐 Connectivity & Integration
*   **🏷️ Mythological Name Pools**: Curated lists of names (e.g., `chiron`, `polyphemus`) for each role
*   **🌐 Zero-Touch Tailscale**: Automatically authenticates via Bitwarden and configures MagicDNS
*   **🔗 Hostname Sync**: Detects mismatch between config and OS hostname, prompting for safe rename

### 🧠 Intelligent Scripts
*   **✅ Safety First**: Soft-fails if Bitwarden is unreachable, validates session before template rendering
*   **🪟 Windows**: Auto-starts `ssh-agent`, handles `bw login/unlock/sync`
*   **🐧 WSL**: Implements **Socket Reuse** so all terminal tabs share one `ssh-agent` session
*   **🔄 Self-Healing**: Automatically derives SSH public keys (`.pub`) whenever private keys change
*   **🎨 GUI Ready**: Automatically installs **FiraCode Nerd Font** on Windows and Linux (workstation roles)
*   **🐚 Unified Shell**: Starship prompt & aliases consistent across PowerShell and Bash

### 📊 Quality & Consistency
*   **✅ 100% Platform Parity**: Identical behavior on Linux and Windows (verified via [SSH_FLOW_REVIEW.md](SSH_FLOW_REVIEW.md))
*   **🎯 Zero Hardcoded Roles**: All templates use capability checks (maintainable, no copy-paste errors)
*   **🔍 Comprehensive Testing**: Full SSH flow review with security audit trail

## 🖥️ Tools

### tmux

Prefix: `C-a` (Ctrl+a, thả ra, rồi bấm phím tiếp theo).

**Session**

| Command | Action |
| :--- | :--- |
| `tmux` | New session (auto name) |
| `tmux new -s <name>` | New session with name |
| `tmux ls` | List sessions |
| `tmux a` | Attach to last session |
| `tmux a -t <name>` | Attach to named session |
| `prefix + d` | Detach (session stays alive) |

**Window (tab)**

| Key | Action |
| :--- | :--- |
| `prefix + c` | New window |
| `prefix + ,` | Rename window |
| `prefix + n` / `p` | Next / previous window |
| `prefix + 0..9` | Jump to window by number |
| `prefix + w` | List windows (j/k to navigate) |
| `prefix + &` | Close window |

**Pane (split)**

| Key | Action |
| :--- | :--- |
| `prefix + \|` | Vertical split |
| `prefix + -` | Horizontal split |
| `Alt + h/j/k/l` | Move between panes (no prefix) |
| `prefix + H/J/K/L` | Resize pane |
| `prefix + z` | Zoom pane (toggle fullscreen) |
| `prefix + x` | Close pane |

**Copy mode** — enter with `prefix + [`, exit with `q`

| Key | Action |
| :--- | :--- |
| `h/j/k/l` | Navigate |
| `C-u` / `C-d` | Page up / down |
| `/` | Search |
| `v` | Begin selection |
| `y` | Copy and exit |
| `prefix + ]` | Paste |

**Other**

| Key | Action |
| :--- | :--- |
| `prefix + r` | Reload `~/.tmux.conf` |
| `prefix + $` | Rename session |
| `prefix + ?` | List all keybindings |

**Typical SSH workflow**

```bash
ssh cyclops
tmux a || tmux new -s work   # attach or create
# work across multiple windows/panes
# disconnect or lose connection
ssh cyclops
tmux a                        # everything still there
```

---

## ❓ Troubleshooting

### Factory Reset (Re-select Role/Hostname)
The system remembers your choices in `~/.config/chezmoi/chezmoi.toml`. To force a fresh start:
*   **Linux**: `rm ~/.config/chezmoi/chezmoi.toml`
*   **Windows**: `Remove-Item $env:USERPROFILE\.config\chezmoi\chezmoi.toml`

### SSH Guest/VM Setup
If you need to configure SSH for a Windows VM or a new target machine, refer to the following guide:
*   [**Install OpenSSH Server on Windows**](docs/ssh-windows-setup.md)

Then run the install script again.

## 📚 Documentation

- **[ROLES.md](ROLES.md)** - Complete role taxonomy, capabilities, and how to add new roles
- **[SSH_FLOW_REVIEW.md](SSH_FLOW_REVIEW.md)** - Comprehensive SSH flow review with security audit
- **[docs/ssh-windows-setup.md](docs/ssh-windows-setup.md)** - Install OpenSSH Server on Windows

## 🎯 Recent Improvements (2026-02-23)

### Security Enhancements ✅
- ✅ **BW_SESSION Cleanup**: Automatically cleared after installation (both success and error paths)
- ✅ **Session Validation**: Pre-check Bitwarden session before template rendering (Linux + Windows)
- ✅ **Backup Retention**: Keeps only 3 most recent SSH backups (prevents unlimited disk usage)

### Architecture Improvements ✅
- ✅ **Centralized Role Taxonomy**: Single source of truth eliminates inconsistencies
- ✅ **Capability-Based Templates**: No more hardcoded role checks (easier maintenance)
- ✅ **File-Based Merge**: SSH merge scripts work for ANY role without code changes
- ✅ **Near-Complete Platform Parity**: Verified functional equivalence on Linux and Windows
  - ⚠️ **Note:** Environment variable cleanup has minor timing differences between platforms due to process model differences (Bash `trap` vs PowerShell scope). Both methods are secure but behavior is not byte-identical.

**Consistency Score:** 92% → **98%** ✅ (platform limitations acknowledged)
**Security Issues:** 3 → **0** ✅
**Platform Parity:** 10/12 → **13/13** ✅ (functional equivalence achieved)

## 📋 Known Issues / TODO

### 🔴 High Priority
*   [ ] **DRY Violation — Role Lists x3**: Role capabilities are defined in `roles:` (L67-140), then manually duplicated in `roles_with_*` groups (L154-166), then duplicated *again* in `has_*` checks (L171-175). Adding a new role requires updating 3 places → error-prone.
*   [ ] **Hardcoded Role Checks in Scripts**: `run_once_install-packages.sh.tmpl` hardcodes workstation roles (`centaur || chimera || griffin`) instead of using the `.is_workstation` capability. Same pattern at lines 38, 80, 140.

### 🟡 Medium Priority
*   [ ] **SSH Key Add Logic Bug**: `dot_bashrc.tmpl` L84-85 checks `ssh-add -l` exit code to decide whether to add key. Exit 0 = "has *any* identity" (not necessarily the right one). Should check by key fingerprint instead.
*   [ ] **PowerShell SSH Agent**: `powershell_profile.ps1.tmpl` L32 — `Get-Service ssh-agent` throws if service doesn't exist. Needs `-ErrorAction SilentlyContinue`.
*   [ ] **Tailscale Fallback Download**: `run_once_install-packages.ps1.tmpl` L79-89 downloads and executes `.exe` without checksum verification.
*   [ ] **Error Handling**: Package installation failures only warn, don't fail the script. Consider stricter error handling.

### 🟢 Low Priority / Nits
*   [ ] **SSH Agent**: Add wait/retry loop to ensure service is ready before adding keys.
*   [ ] **Duplicate Comment**: `dot_bashrc.tmpl` L63-64 has two `SSH Agent Auto-Load` comments.
*   [ ] **Redundant Git Alias**: `dot_gitconfig.tmpl` defines `st = status` which overlaps with shell alias `st = "git status"`.
*   [ ] **Trailing Blank Lines**: `run_once_install-packages.ps1.tmpl` has 5 trailing blank lines (L118-122).
