#!/bin/bash
# Usage: ./install.sh
#        OR: sh -c "$(curl -fsSL https://raw.githubusercontent.com/vovanphu/arx/master/install.sh)"

# --- Configuration URLs (can be overridden via environment variables) ---
REPO_URL="${ARX_REPO_URL:-https://github.com/vovanphu/arx.git}"
CHEZMOI_INSTALL_URL="${CHEZMOI_URL:-https://get.chezmoi.io}"
BITWARDEN_CLI_URL="${BW_CLI_URL:-https://vault.bitwarden.com/download/?app=cli&platform=linux}"
TAILSCALE_INSTALL_URL="${TAILSCALE_URL:-https://tailscale.com/install.sh}"
STARSHIP_INSTALL_URL="${STARSHIP_URL:-https://starship.rs/install.sh}"
NERD_FONT_FIRACODE_URL="${NERD_FONT_FIRACODE_URL:-https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip}"
NERD_FONT_MONASPACE_URL="${NERD_FONT_MONASPACE_URL:-https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Monaspace.zip}"

# --- Global Settings ---
# Cleanup function to be called on exit
cleanup() {
    # Kill sudo keepalive background process if running
    if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    # Kill Bitwarden session keepalive background process if running
    if [ -n "${BW_KEEPALIVE_PID:-}" ]; then
        kill "$BW_KEEPALIVE_PID" 2>/dev/null || true
    fi
    # Secure cleanup: delete .env file
    rm -f .env
}
# Ensure cleanup is called on exit
trap cleanup EXIT INT TERM
SUDO_KEEPALIVE_PID=""
BW_KEEPALIVE_PID=""
WARN_LOG=()
HAVE_SUDO=false

# --- Logging Helpers ---
log_info()  { echo "INFO: $*"; }
log_warn()  { echo "WARN: $*"; WARN_LOG+=("$*"); }
log_error() { echo "ERROR: $*"; }
log_skip()  { echo "SKIP: $*"; }

# --- Environment Detection ---
# Sets: PLATFORM, DISTRO, DISTRO_FAMILY, DISTRO_VERSION, IS_WSL
detect_environment() {
    PLATFORM="linux"
    IS_WSL=false
    if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=true
    fi

    DISTRO="unknown"
    DISTRO_FAMILY="unknown"
    DISTRO_VERSION=""

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-}"
        if [ -n "${ID_LIKE:-}" ]; then
            DISTRO_FAMILY="${ID_LIKE%% *}"
        else
            DISTRO_FAMILY="${ID:-unknown}"
        fi
        case "$DISTRO_FAMILY" in
            debian|ubuntu)        DISTRO_FAMILY="debian" ;;
            fedora|rhel|centos)   DISTRO_FAMILY="fedora" ;;
        esac
    fi
}

# --- Capability Derivation ---
# Sets: IS_WORKSTATION, IS_SERVER, IS_VIRT_HOST, RECEIVES_SSH
# Must be called after ROLE is resolved.
derive_capabilities() {
    local role="${1:-}"
    IS_WORKSTATION=false
    IS_SERVER=false
    IS_VIRT_HOST=false
    RECEIVES_SSH=false

    case "$role" in
        centaur)
            IS_WORKSTATION=true ;;
        chimera)
            IS_WORKSTATION=true
            RECEIVES_SSH=true ;;
        griffin)
            IS_WORKSTATION=true
            IS_VIRT_HOST=true
            RECEIVES_SSH=true ;;
        hydra)
            IS_SERVER=true
            IS_VIRT_HOST=true
            RECEIVES_SSH=true ;;
        cyclops|cerberus|golem|minion|siren|kraken)
            IS_SERVER=true
            RECEIVES_SSH=true ;;
        "")
            ;;
        *)
            log_warn "derive_capabilities: unknown role '${role}'" ;;
    esac
}

# --- Dispatch ---
# run_layer <func_base> [args...]
# Resolution order: <func_base>_<DISTRO> -> <func_base>_<DISTRO_FAMILY> -> <func_base>_linux -> <func_base>_all
# Calls the first match found. Logs which function was dispatched.
run_layer() {
    local func_base="$1"
    shift
    local suffix fn
    for suffix in "${DISTRO}" "${DISTRO_FAMILY}" "linux" "all"; do
        fn="${func_base}_${suffix}"
        if declare -f "$fn" > /dev/null 2>&1; then
            log_info "dispatch: ${fn}"
            "$fn" "$@"
            return $?
        fi
    done
    log_skip "no handler: ${func_base} on ${DISTRO} (${DISTRO_FAMILY})"
    return 0
}

# --- Package Name Resolver ---
# Translates canonical (debian) package names to distro-specific names.
resolve_pkg_name() {
    local pkg="$1"
    case "${DISTRO_FAMILY}:${pkg}" in
        fedora:libvirt-clients)       echo "libvirt-client" ;;
        fedora:libvirt-daemon-system) echo "libvirt-daemon-kvm" ;;
        fedora:zram-tools)            echo "zram-generator-defaults" ;;
        fedora:ksmtuned)              echo "tuned" ;;
        fedora:docker.io)             echo "docker" ;;
        fedora:postgresql-client)     echo "postgresql" ;;
        fedora:redis-tools)           echo "redis" ;;
        fedora:ceph-common)           echo "ceph" ;;
        fedora:ufw)                   echo "" ;;
        *)                            echo "$pkg" ;;
    esac
}

# pkg_install: install packages via the distro package manager.
# Accepts canonical (debian) names; resolve_pkg_name handles translation.
# DNF groups (prefix @) handled separately. Logs WARN on failure, skips if no sudo.
pkg_install() {
    if [ "$HAVE_SUDO" != "true" ]; then
        log_warn "pkg_install: sudo not available; skipping: $*"
        return 0
    fi
    local regular_pkgs=() group_pkgs=()
    local pkg resolved
    for pkg in "$@"; do
        resolved=$(resolve_pkg_name "$pkg")
        [ -z "$resolved" ] && continue
        if [[ "$resolved" == @* ]]; then
            group_pkgs+=("$resolved")
        else
            regular_pkgs+=("$resolved")
        fi
    done
    if [ "$DISTRO_FAMILY" = "debian" ]; then
        if [ "${#regular_pkgs[@]}" -gt 0 ]; then
            if ! sudo apt-get install -y "${regular_pkgs[@]}"; then
                log_warn "apt: failed to install some packages: ${regular_pkgs[*]}"
            fi
        fi
    elif [ "$DISTRO_FAMILY" = "fedora" ]; then
        if [ "${#regular_pkgs[@]}" -gt 0 ]; then
            if ! sudo dnf install -y "${regular_pkgs[@]}"; then
                log_warn "dnf: failed to install some packages: ${regular_pkgs[*]}"
            fi
        fi
        if [ "${#group_pkgs[@]}" -gt 0 ]; then
            if ! sudo dnf groupinstall -y "${group_pkgs[@]}"; then
                log_warn "dnf: failed to install groups: ${group_pkgs[*]}"
            fi
        fi
    else
        log_warn "pkg_install: unsupported distro family '${DISTRO_FAMILY}'; skipping: $*"
    fi
}

# --- Package Install: Distro Layers ---
# Each function sets up repos, refreshes cache, and installs common packages.
# ubuntu calls debian (explicit parent chain).

install_packages_debian() {
    sudo apt-get update || log_warn "apt-get update failed"
    pkg_install git curl
}

install_packages_ubuntu() {
    if ! grep -qrE "^deb.* universe" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        sudo add-apt-repository -y universe 2>/dev/null || log_warn "add-apt-repository universe failed"
    fi
    install_packages_debian
}

install_packages_fedora() {
    sudo dnf makecache --refresh || log_warn "dnf makecache failed"
    pkg_install git curl
}

install_packages_centos() {
    if ! rpm -q epel-release >/dev/null 2>&1; then
        sudo dnf install -y epel-release || log_warn "EPEL install failed; some packages may not be available"
    fi
    install_packages_fedora
}

install_packages_rocky() {
    if ! rpm -q epel-release >/dev/null 2>&1; then
        sudo dnf install -y epel-release || log_warn "EPEL install failed"
    fi
    sudo dnf config-manager --set-enabled crb 2>/dev/null || true
    install_packages_fedora
}

# --- Tailscale Binary Install ---
install_tailscale_binary() {
    if command -v tailscale >/dev/null 2>&1; then
        log_skip "tailscale: already installed"
        return 0
    fi
    log_info "installing Tailscale binary..."
    if ! curl -fsSL "$TAILSCALE_INSTALL_URL" | sh; then
        if command -v tailscale >/dev/null 2>&1; then
            log_warn "tailscale: installer reported error but binary found; continuing"
        else
            log_warn "tailscale: install failed; run installer manually"
        fi
    fi
}

# --- RPM Fusion (Fedora workstation) ---
install_rpm_fusion() {
    if sudo dnf repolist 2>/dev/null | grep -q "rpmfusion"; then
        log_skip "rpm-fusion: already enabled"
        return 0
    fi
    log_info "enabling RPM Fusion repositories..."
    if ! sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; then
        log_warn "rpm-fusion: install failed"
        return 0
    fi
    sudo dnf config-manager --set-enabled fedora-cisco-openh264 2>/dev/null || true
}

# --- Nerd Fonts (workstation) ---
install_nerd_fonts() {
    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"
    pkg_install unzip fontconfig

    if [ ! -f "$font_dir/MonaspaceNeonNerdFont-Regular.otf" ]; then
        log_info "installing Monaspace Nerd Font..."
        if curl -fLo /tmp/Monaspace.zip "$NERD_FONT_MONASPACE_URL"; then
            unzip -o -q /tmp/Monaspace.zip -d "$font_dir"
            rm /tmp/Monaspace.zip
        else
            log_warn "nerd-fonts: Monaspace download failed"
        fi
    else
        log_skip "nerd-fonts: Monaspace already installed"
    fi

    if [ ! -f "$font_dir/FiraCodeNerdFont-Regular.ttf" ]; then
        log_info "installing FiraCode Nerd Font..."
        if curl -fLo /tmp/FiraCode.zip "$NERD_FONT_FIRACODE_URL"; then
            unzip -o -q /tmp/FiraCode.zip -d "$font_dir"
            rm /tmp/FiraCode.zip
        else
            log_warn "nerd-fonts: FiraCode download failed"
        fi
    else
        log_skip "nerd-fonts: FiraCode already installed"
    fi

    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$font_dir" 2>/dev/null || true
    fi
}

# --- Fedora Workstation Extras ---
install_inter_font_fedora() {
    if rpm -q inter-fonts >/dev/null 2>&1; then
        log_skip "inter-fonts: already installed"
        return 0
    fi
    log_info "installing Inter font via COPR..."
    sudo dnf copr enable -y burhanverse/inter-fonts 2>/dev/null || { log_warn "inter-fonts: COPR enable failed"; return 0; }
    sudo dnf install -y inter-fonts || log_warn "inter-fonts: install failed"
}

install_nvidia_driver_fedora() {
    if rpm -q akmod-nvidia >/dev/null 2>&1; then
        log_skip "nvidia: akmod-nvidia already installed"
        return 0
    fi
    log_info "installing NVIDIA driver (akmod-nvidia)..."
    if ! sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda nvtop; then
        log_warn "nvidia: driver install failed"
        return 0
    fi
    log_info "nvidia: wait 3-5 minutes for akmods to build, then reboot manually"
}

install_cloudflare_warp_fedora() {
    if command -v warp-cli >/dev/null 2>&1; then
        log_skip "cloudflare-warp: already installed"
        return 0
    fi
    log_info "installing Cloudflare WARP..."
    sudo rpm --import https://pkg.cloudflareclient.com/pubkey.gpg 2>/dev/null || true
    local warp_repo="/etc/yum.repos.d/cloudflare-warp.repo"
    if [ ! -f "$warp_repo" ]; then
        cat <<'EOF' | sudo tee "$warp_repo" > /dev/null
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
EOF
    fi
    if ! sudo dnf install -y cloudflare-warp; then
        log_warn "cloudflare-warp: install failed"
        return 0
    fi
    sudo systemctl enable warp-svc 2>/dev/null || true
    log_info "cloudflare-warp: register via: warp-cli registration new"
}

# --- Package Install: Purpose Layers ---
install_packages_workstation() {
    [ "$IS_WORKSTATION" = "true" ] || return 0
    pkg_install neovim ripgrep fzf zoxide
    if ! command -v starship >/dev/null 2>&1; then
        curl -sS "$STARSHIP_INSTALL_URL" | sh -s -- -y || log_warn "starship: install failed"
    else
        log_skip "starship: already installed"
    fi
    install_nerd_fonts
    if [ "$DISTRO_FAMILY" = "fedora" ]; then
        install_rpm_fusion
        install_inter_font_fedora
        install_nvidia_driver_fedora
        install_cloudflare_warp_fedora
    fi
    if [ "$DISTRO" = "debian" ]; then
        if ! grep -q "non-free" /etc/apt/sources.list 2>/dev/null; then
            sudo sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
            sudo apt-get update || true
        fi
    fi
}

install_packages_server() {
    [ "$IS_SERVER" = "true" ] || return 0
    pkg_install htop ncdu
}

# --- Package Install: Role Layers ---
install_packages_centaur() {
    pkg_install ansible
}

install_packages_chimera() {
    pkg_install openssh-server gcc make
    if [ "$DISTRO_FAMILY" = "debian" ]; then
        pkg_install build-essential g++
    elif [ "$DISTRO_FAMILY" = "fedora" ]; then
        pkg_install "@Development Tools" gcc-c++
    fi
}

install_packages_griffin() {
    pkg_install openssh-server qemu-kvm libvirt-daemon-system libvirt-clients \
        bridge-utils virt-manager htop ncdu zram-tools ksmtuned
    if [ "$DISTRO_FAMILY" = "fedora" ]; then
        pkg_install ibus-unikey gnome-tweaks gnome-extensions-app
    fi
}

install_packages_hydra() {
    pkg_install openssh-server htop ncdu neofetch zram-tools ksmtuned
}

install_packages_cyclops() {
    pkg_install openssh-server nginx net-tools
}

install_packages_cerberus() {
    pkg_install openssh-server fail2ban wireguard-tools
    if [ "$DISTRO_FAMILY" = "debian" ]; then
        pkg_install ufw
    elif [ "$DISTRO_FAMILY" = "fedora" ]; then
        pkg_install firewalld
    fi
}

install_packages_golem() {
    pkg_install openssh-server postgresql-client redis-tools
}

install_packages_minion() {
    pkg_install openssh-server htop docker.io
    if [ "$DISTRO_FAMILY" = "fedora" ]; then
        pkg_install docker-compose
    fi
}

install_packages_siren() {
    pkg_install openssh-server nginx certbot python3-certbot-nginx
}

install_packages_kraken() {
    pkg_install openssh-server ceph-common xfsprogs smartmontools
}

# --- Package Install: Orchestrator ---
run_packages() {
    echo "--- Package Installation ---"
    run_layer install_packages        # repo setup + cache update + git/curl
    install_tailscale_binary
    install_packages_workstation      # IS_WORKSTATION guard inside
    install_packages_server           # IS_SERVER guard inside
    local fn="install_packages_${ROLE:-}"
    if [ -n "${ROLE:-}" ] && declare -f "$fn" > /dev/null 2>&1; then
        log_info "role packages: ${fn}"
        "$fn"
    fi
}

# --- System Configuration Functions ---

configure_tailscale() {
    if ! command -v tailscale >/dev/null 2>&1; then
        log_skip "tailscale: binary not installed; skipping auth"
        return 0
    fi
    local ts_hostname="${HOSTNAME_VAR:-$(hostname)}"
    local ts_key=""
    if [ -n "${BW_SESSION:-}" ]; then
        ts_key=$(bw get password "tailscale-auth-key" 2>/dev/null || true)
    fi
    local ts_status
    ts_status=$(tailscale status 2>/dev/null || true)
    if echo "$ts_status" | grep -qiE "(Tailscale is stopped|NeedsLogin|not logged in|Logged out)" || [ -z "$ts_status" ]; then
        if [ -z "$ts_key" ]; then
            log_warn "tailscale: auth key not found in vault; skipping auth"
            return 0
        fi
        local ts_flags="--authkey $ts_key --hostname $ts_hostname --accept-routes"
        if [ "$IS_WSL" = "true" ]; then
            ts_flags="$ts_flags --accept-dns=false"
        fi
        log_info "tailscale: authenticating as '${ts_hostname}'..."
        if sudo tailscale up $ts_flags; then
            log_info "tailscale: connected"
        else
            log_warn "tailscale: auth failed; check key and daemon status"
        fi
    else
        log_info "tailscale: already logged in; updating hostname..."
        sudo tailscale set --hostname "$ts_hostname" 2>/dev/null || true
    fi
}

configure_wsl() {
    [ "$IS_WSL" = "true" ] || return 0
    local wsl_conf="/etc/wsl.conf"
    if ! grep -iq "\[network\]" "$wsl_conf" 2>/dev/null; then
        printf '\n[network]\n' | sudo tee -a "$wsl_conf" > /dev/null
    fi
    if grep -iq "hostname[[:space:]]*=" "$wsl_conf" 2>/dev/null; then
        sudo sed -i '/^hostname[[:space:]]*=/d' "$wsl_conf"
    fi
    if ! grep -iq "generateHosts[[:space:]]*=" "$wsl_conf" 2>/dev/null; then
        sudo sed -i '/\[network\]/a generateHosts=true' "$wsl_conf"
    else
        sudo sed -i 's/^generateHosts[[:space:]]*=.*/generateHosts=true/' "$wsl_conf"
    fi
    if ! grep -iq "generateResolvConf[[:space:]]*=" "$wsl_conf" 2>/dev/null; then
        sudo sed -i '/\[network\]/a generateResolvConf=true' "$wsl_conf"
    else
        sudo sed -i 's/^generateResolvConf[[:space:]]*=.*/generateResolvConf=true/' "$wsl_conf"
    fi
    if grep -iq "generateResolvConf[[:space:]]*=[[:space:]]*true" "$wsl_conf" 2>/dev/null; then
        if [ ! -L /etc/resolv.conf ] || [ ! -e /etc/resolv.conf ]; then
            sudo chattr -i /etc/resolv.conf 2>/dev/null || true
            sudo rm -f /etc/resolv.conf
        fi
    fi
    log_info "wsl: /etc/wsl.conf updated; run 'wsl --shutdown' in Windows to apply"
}

configure_ssh_server_linux() {
    if [ "$RECEIVES_SSH" != "true" ]; then
        log_skip "ssh-server: RECEIVES_SSH=false for role '${ROLE:-}'; skipping"
        return 0
    fi
    if ! command -v sshd >/dev/null 2>&1; then
        log_warn "ssh-server: sshd not found; install openssh-server first"
        return 0
    fi
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        log_skip "ssh-server: already running"
        return 0
    fi
    log_info "ssh-server: starting and enabling..."
    if sudo systemctl start ssh 2>/dev/null || sudo systemctl start sshd 2>/dev/null; then
        sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd 2>/dev/null || true
        log_info "ssh-server: started and enabled"
    else
        log_warn "ssh-server: failed to start; check 'systemctl status sshd'"
    fi
}

configure_zram_fedora() {
    [ "$IS_VIRT_HOST" = "true" ] || return 0
    sudo mkdir -p /etc/systemd/zram-generator.conf.d
    cat <<'EOF' | sudo tee /etc/systemd/zram-generator.conf.d/zram0.conf > /dev/null
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF
    if zramctl 2>/dev/null | grep -q zram0; then
        log_skip "zram: already running; config updated (applies on next boot)"
    else
        if sudo systemctl start systemd-zram-setup@zram0; then
            log_info "zram: configured and running"
        else
            log_warn "zram: failed to start systemd-zram-setup@zram0"
        fi
    fi
}

configure_zram_debian() {
    [ "$IS_VIRT_HOST" = "true" ] || return 0
    [ -f /etc/default/zramswap ] && sudo cp /etc/default/zramswap /etc/default/zramswap.bak
    cat <<'EOF' | sudo tee /etc/default/zramswap > /dev/null
ALGO=zstd
PERCENT=50
EOF
    if sudo systemctl restart zramswap; then
        log_info "zram: configured and running"
    else
        log_warn "zram: failed to restart zramswap"
    fi
}

configure_ksm_linux() {
    [ "$IS_VIRT_HOST" = "true" ] || return 0
    if [ ! -f /sys/kernel/mm/ksm/run ]; then
        log_skip "ksm: not available on this kernel"
        return 0
    fi
    cat <<'EOF' | sudo tee /etc/sysctl.d/99-ksm.conf > /dev/null
kernel.mm.ksm.run = 1
kernel.mm.ksm.sleep_millisecs = 20
EOF
    sudo sysctl -p /etc/sysctl.d/99-ksm.conf > /dev/null 2>&1
    log_info "ksm: enabled ($(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null || echo 0) pages shared)"
}

configure_libvirt_group_linux() {
    [ "$IS_VIRT_HOST" = "true" ] || return 0
    if ! getent group libvirt >/dev/null 2>&1; then
        log_skip "libvirt-group: group does not exist (package not installed)"
        return 0
    fi
    local user="${USER:-$(whoami 2>/dev/null)}"
    if [ -z "$user" ]; then
        log_warn "libvirt-group: cannot determine current user"
        return 0
    fi
    if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx libvirt; then
        log_skip "libvirt-group: ${user} already in libvirt group"
        return 0
    fi
    if sudo usermod -aG libvirt "$user"; then
        log_info "libvirt-group: ${user} added; log out and back in for membership to take effect"
    else
        log_warn "libvirt-group: failed to add ${user} to libvirt group"
    fi
}

configure_virt_kvm_fedora() {
    [ "$IS_VIRT_HOST" = "true" ] || return 0
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
        if command -v restorecon >/dev/null 2>&1; then
            sudo restorecon -R /var/lib/libvirt 2>/dev/null || log_warn "selinux: restorecon failed for /var/lib/libvirt"
        fi
        if rpm -q nfs-utils >/dev/null 2>&1 && command -v setsebool >/dev/null 2>&1; then
            sudo setsebool -P virt_use_nfs on 2>/dev/null || log_warn "selinux: failed to set virt_use_nfs"
        fi
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        systemctl is-enabled --quiet firewalld 2>/dev/null || sudo systemctl enable firewalld
        if ! systemctl is-active --quiet firewalld 2>/dev/null; then
            sudo systemctl start firewalld || log_warn "firewalld: failed to start"
        fi
    else
        log_warn "firewalld: not installed; libvirt networking may fail"
    fi
}

configure_tuned_linux() {
    [ "$IS_VIRT_HOST" = "true" ] || return 0
    if ! command -v tuned-adm >/dev/null 2>&1; then
        log_skip "tuned: tuned-adm not found (not installed on this distro)"
        return 0
    fi
    local current
    current=$(tuned-adm active 2>/dev/null | grep -oP '(?<=Current active profile: ).+' || true)
    if [ "$current" = "virtual-host" ]; then
        log_skip "tuned: profile already set to virtual-host"
        return 0
    fi
    if sudo tuned-adm profile virtual-host; then
        log_info "tuned: profile set to virtual-host (was: ${current:-unknown})"
    else
        log_warn "tuned: failed to set profile to virtual-host"
    fi
}

configure_workstation_linux() {
    [ "$IS_WORKSTATION" = "true" ] || return 0
    if [ -d /etc/systemd ]; then
        local logind_conf="/etc/systemd/logind.conf.d/lid.conf"
        sudo mkdir -p /etc/systemd/logind.conf.d
        if [ ! -f "$logind_conf" ] || ! grep -q "HandleLidSwitch=lock" "$logind_conf" 2>/dev/null; then
            cat <<'EOF' | sudo tee "$logind_conf" > /dev/null
[Login]
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=lock
EOF
            log_info "logind: lid switch set to lock"
        else
            log_skip "logind: lid switch already configured"
        fi
    fi
}

configure_workstation_fedora() {
    [ "$IS_WORKSTATION" = "true" ] || return 0
    configure_workstation_linux
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface font-name 'Inter Regular 10'
        gsettings set org.gnome.desktop.interface document-font-name 'Inter Regular 11'
        gsettings set org.gnome.desktop.interface monospace-font-name 'MonaspaceNeon Nerd Font 11'
        gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter SemiBold 10'
        gsettings set org.gnome.desktop.interface font-hinting 'slight'
        gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
        gsettings set org.gnome.desktop.peripherals.touchpad acceleration-profile 'flat'
        log_info "gnome: settings applied"
    fi
}

install_apps_fedora() {
    [ "$IS_WORKSTATION" = "true" ] || return 0
    if ! command -v google-chrome-stable >/dev/null 2>&1; then
        local chrome_repo="/etc/yum.repos.d/google-chrome.repo"
        if [ ! -f "$chrome_repo" ]; then
            cat <<'EOF' | sudo tee "$chrome_repo" > /dev/null
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
        fi
        if sudo dnf install -y google-chrome-stable; then
            sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null || true
            log_info "chrome: installed"
        else
            log_warn "chrome: install failed"
        fi
    else
        log_skip "chrome: already installed"
    fi

    if ! flatpak info com.mattjakeman.ExtensionManager >/dev/null 2>&1; then
        flatpak install -y flathub com.mattjakeman.ExtensionManager 2>/dev/null || \
            log_warn "extension-manager: flatpak install failed"
    else
        log_skip "extension-manager: already installed"
    fi

    if ! command -v code >/dev/null 2>&1; then
        local vscode_repo="/etc/yum.repos.d/vscode.repo"
        if [ ! -f "$vscode_repo" ]; then
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
            cat <<'EOF' | sudo tee "$vscode_repo" > /dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
        fi
        if sudo dnf install -y code; then
            log_info "vscode: installed"
        else
            log_warn "vscode: install failed"
        fi
    else
        log_skip "vscode: already installed"
    fi
}

# --- System Configuration: Orchestrator ---
configure_system() {
    echo "--- System Configuration ---"
    configure_tailscale
    configure_wsl
    run_layer configure_ssh_server
    if [ "$IS_VIRT_HOST" = "true" ]; then
        run_layer configure_zram
        configure_ksm_linux
        run_layer configure_virt_kvm
        configure_libvirt_group_linux
        configure_tuned_linux
    fi
    if [ "$IS_WORKSTATION" = "true" ]; then
        run_layer configure_workstation
        run_layer install_apps
    fi
}

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
    else
        # Create .env from environment variables if they exist
        if [ -n "${BW_EMAIL:-}" ] || [ -n "${BW_PASSWORD:-}" ] || [ -n "${ROLE:-}" ] || [ -n "${HOSTNAME:-}" ] || [ -n "${USER_NAME:-}" ] || [ -n "${EMAIL_ADDRESS:-}" ] || [ -n "${SUDO_PASSWORD:-}" ]; then
            echo "Creating .env from environment variables..."
            {
                [ -n "${BW_EMAIL:-}" ] && echo "BW_EMAIL=$BW_EMAIL"
                [ -n "${BW_PASSWORD:-}" ] && echo "BW_PASSWORD=$BW_PASSWORD"
                [ -n "${ROLE:-}" ] && echo "ROLE=$ROLE"
                [ -n "${HOSTNAME:-}" ] && echo "HOSTNAME=$HOSTNAME"
                [ -n "${USER_NAME:-}" ] && echo "USER_NAME=$USER_NAME"
                [ -n "${EMAIL_ADDRESS:-}" ] && echo "EMAIL_ADDRESS=$EMAIL_ADDRESS"
                [ -n "${SUDO_PASSWORD:-}" ] && echo "SUDO_PASSWORD=$SUDO_PASSWORD"
            } > "$DEST_DIR/.env"
        fi
    fi
    cd "$DEST_DIR" || exit
    exec bash "install.sh"
    exit
fi

# --- Local Execution Logic ---
export PATH="$HOME/.local/bin:$PATH"
CHEZMOI_BIN="$HOME/.local/bin/chezmoi"

# --- Detect-only mode ---
# Usage: bash install.sh --detect
# Prints environment tuple and capability flags without running any provisioning.
if [ "${1:-}" = "--detect" ]; then
    detect_environment
    echo "PLATFORM=$PLATFORM"
    echo "DISTRO=$DISTRO"
    echo "DISTRO_FAMILY=$DISTRO_FAMILY"
    echo "DISTRO_VERSION=$DISTRO_VERSION"
    echo "IS_WSL=$IS_WSL"
    echo ""
    _DETECT_ROLE="${ROLE:-}"
    if [ -z "$_DETECT_ROLE" ] && [ -f ".env" ] && [ ! -L ".env" ]; then
        _DETECT_ROLE=$(grep "^ROLE=" .env | head -n1 | cut -d'=' -f2- | \
            sed -e "s/#.*$//" -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//" \
                -e "s/^['\"]//" -e "s/['\"]$//")
    fi
    if [ -n "$_DETECT_ROLE" ]; then
        derive_capabilities "$_DETECT_ROLE"
        echo "ROLE=$_DETECT_ROLE"
        echo "IS_WORKSTATION=$IS_WORKSTATION"
        echo "IS_SERVER=$IS_SERVER"
        echo "IS_VIRT_HOST=$IS_VIRT_HOST"
        echo "RECEIVES_SSH=$RECEIVES_SSH"
    else
        echo "ROLE=(not set -- pass ROLE=<role> env var to see capabilities)"
    fi
    exit 0
fi

detect_environment

# --- Sudo Session Bootstrap ---
SUDO_PASSWORD="${SUDO_PASSWORD:-}"
if [ -z "$SUDO_PASSWORD" ] && [ -f ".env" ] && [ ! -L ".env" ]; then
    SUDO_PASSWORD=$(grep "^SUDO_PASSWORD=" .env | head -n1 | cut -d'=' -f2- | sed -e "s/#.*$//" -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//" -e "s/^['\"]//" -e "s/['\"]$//")
fi

if [ -n "$SUDO_PASSWORD" ]; then
    echo "Gaining sudo session..."
    if echo "$SUDO_PASSWORD" | sudo -S true 2>/dev/null; then
        echo "Sudo session active."
        # Keepalive: refresh sudo timestamp every 60s so session does not expire mid-install
        ( while true; do sudo -n true 2>/dev/null; sleep 60; done ) &
        SUDO_KEEPALIVE_PID=$!
        HAVE_SUDO=true
    else
        echo "Warning: SUDO_PASSWORD provided but sudo authentication failed. Continuing without cached session."
    fi
    unset SUDO_PASSWORD
fi

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
        curl -fL "$BITWARDEN_CLI_URL" -o bw.zip
        unzip -o bw.zip
        chmod +x bw
        mv bw "$HOME/.local/bin/"
        rm bw.zip
    elif command -v dnf &> /dev/null; then
        if ! command -v unzip &> /dev/null; then
            sudo dnf install -y unzip
        fi
        curl -fL "$BITWARDEN_CLI_URL" -o bw.zip
        unzip -o bw.zip
        chmod +x bw
        mv bw "$HOME/.local/bin/"
        rm bw.zip
    else
        echo "Error: Cannot install Bitwarden CLI -- no supported package manager found (apt/dnf)."
        exit 1
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
        BW_STATUS=$(bw status 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        if [ "$BW_STATUS" = "unauthenticated" ]; then
            export BW_PASSWORD="$PASSWORD"
            if [ -n "$EMAIL" ]; then
                if ! bw login "$EMAIL" --passwordenv BW_PASSWORD 2>&1; then
                    echo "Warning: Bitwarden login failed. Check BW_EMAIL and network connectivity."
                    unset BW_PASSWORD
                fi
            else
                if ! bw login --passwordenv BW_PASSWORD 2>&1; then
                    echo "Warning: Bitwarden login failed. Check network connectivity."
                    unset BW_PASSWORD
                fi
            fi
        fi

        if [ -n "${BW_PASSWORD:-}" ] || [ "$BW_STATUS" != "unauthenticated" ]; then
            export BW_PASSWORD="$PASSWORD"
            # If vault is locked (already logged in), logout first then login+unlock
            # --passwordenv only works reliably immediately after login in some bw versions
            if [ "$BW_STATUS" = "locked" ]; then
                bw logout 2>/dev/null || true
                if [ -n "$EMAIL" ]; then
                    bw login "$EMAIL" --passwordenv BW_PASSWORD 2>/dev/null || true
                else
                    bw login --passwordenv BW_PASSWORD 2>/dev/null || true
                fi
            fi
            BW_SES=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null | tail -n 1)
            # Regex validation for Base64 session key
            if [[ $BW_SES =~ ^[A-Za-z0-9+/=]{20,}$ ]]; then
                export BW_SESSION="$BW_SES"
                echo ""
                echo "Vault unlocked & synced!"
                bw sync 2>/dev/null | grep -v "Syncing"
                SHOULD_PROMPT=false
            else
                echo "Warning: Automated unlock failed. Check BW_PASSWORD is correct."
            fi
            unset BW_PASSWORD
        fi
    fi

    if [ "$SHOULD_PROMPT" = true ] && [ -z "$BW_SESSION" ]; then
        read -p "Bitwarden session not detected. Unlock now? (y/n) " -r
        if [[ $REPLY =~ ^[Yy] ]]; then
            if bw status | grep -q "unauthenticated"; then bw login; fi
            BW_SES=$(bw unlock --raw | tail -n 1)
            if [[ $BW_SES =~ ^[A-Za-z0-9+/=]{20,}$ ]]; then
                export BW_SESSION="$BW_SES"
                echo ""
                echo "Vault unlocked!"
                bw sync | grep -v "Syncing"
            fi
        fi
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Pre-flight privilege escalation (ensure root access for package installation) ---
if [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" -ne 0 ]; then
    echo ""
    echo "--- Privilege Escalation ---"
    echo "Package installation requires root privileges."

    # Try sudo first (most common)
    if command -v sudo &> /dev/null; then
        echo "Attempting sudo authentication..."
        if sudo -v; then
            echo "✓ Sudo authenticated successfully."
            # Keep sudo alive in background for the duration of the script
            # This allows chezmoi subprocesses to use sudo without password
            ( while true; do sudo -v; sleep 50; done ) &
            SUDO_KEEPALIVE_PID=$!
            HAVE_SUDO=true
        else
            # Sudo failed, try to add user to sudo group with su
            echo "✗ Sudo authentication failed (user not in sudo group or wrong password)."
            echo ""
            if command -v su &> /dev/null; then
                echo "Attempting to add your user to sudo group..."
                echo "You will be prompted for the ROOT password:"
                if su -c "usermod -aG sudo $USER"; then
                    echo ""
                    echo "✓ User added to sudo group successfully!"
                    echo "⚠ You must LOG OUT and LOG BACK IN for changes to take effect."
                    echo ""
                    read -p "Press Enter to continue (packages will not be installed until you re-login)..."
                    # Continue without sudo - packages won't be installed but dotfiles will be applied
                else
                    echo "✗ Failed to add user to sudo group."
                    echo ""
                    read -p "Continue without package installation? (y/N) " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        exit 1
                    fi
                fi
            else
                echo "✗ Cannot escalate privileges (neither sudo nor su available)."
                exit 1
            fi
        fi
    else
        # No sudo installed, try to install it with su
        echo "sudo not found on this system."
        if command -v su &> /dev/null; then
            echo "Attempting to install sudo..."
            echo "You will be prompted for the ROOT password:"
            if su -c "apt-get update && apt-get install -y sudo && usermod -aG sudo $USER"; then
                echo ""
                echo "✓ sudo installed and user added to sudo group!"
                echo "⚠ You must LOG OUT and LOG BACK IN for changes to take effect."
                echo ""
                read -p "Press Enter to continue (packages will not be installed until you re-login)..."
            else
                echo "✗ Failed to install sudo."
                exit 1
            fi
        else
            echo "✗ Neither sudo nor su available. Cannot proceed."
            exit 1
        fi
    fi
fi

# --- Chezmoi Initialization (The "Invisible" Version) ---
echo "--- Chezmoi Initialization ---"

# Export environment variables for the template to read directly (Short-Circuit Logic)
export ROLE="$ROLE_VAR"
export HOSTNAME="$HOSTNAME_VAR"
export USER_NAME="$USER_NAME_VAR"
export EMAIL_ADDRESS="$EMAIL_ADDRESS_VAR"
derive_capabilities "$ROLE_VAR"

if [ -n "$ROLE_VAR" ] || [ -n "$HOSTNAME_VAR" ] || [ -n "$EMAIL_ADDRESS_VAR" ]; then
    echo "Baking environment variables into template context..."
    [ -n "$EMAIL_ADDRESS_VAR" ] && echo "  > EMAIL: $EMAIL_ADDRESS_VAR"
    [ -n "$ROLE_VAR" ]          && echo "  > ROLE : $ROLE_VAR"
    [ -n "$HOSTNAME_VAR" ]      && echo "  > HOST : $HOSTNAME_VAR"
fi

run_packages

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
        echo "Bitwarden session expired. Attempting to re-unlock..."
        _BW_RELOCK_PASSWORD=""
        if [ -f ".env" ] && [ ! -L ".env" ]; then
            _BW_RELOCK_PASSWORD=$(grep "^BW_PASSWORD=" .env | head -n1 | cut -d'=' -f2- | sed -e "s/#.*$//" -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//" -e "s/^['\"]//" -e "s/['\"]$//")
        fi
        if [ -n "$_BW_RELOCK_PASSWORD" ]; then
            export BW_PASSWORD="$_BW_RELOCK_PASSWORD"
            _BW_NEW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null | tail -n1)
            unset BW_PASSWORD
            unset _BW_RELOCK_PASSWORD
            if [[ $_BW_NEW_SESSION =~ ^[A-Za-z0-9+/=]{20,}$ ]]; then
                export BW_SESSION="$_BW_NEW_SESSION"
                echo "Bitwarden session refreshed."
            else
                echo "Warning: Failed to re-unlock Bitwarden. Templates requiring vault access may fail."
            fi
        else
            echo "Warning: Bitwarden session expired and no password available to re-unlock. Templates requiring vault access may fail."
        fi
    else
        echo "Bitwarden session valid."
    fi
fi
if ! "$CHEZMOI_BIN" apply --source="$SCRIPT_DIR" --force; then
    echo "Warning: Chezmoi apply encountered errors. Some dotfiles may not be configured correctly."
    echo "You can re-run: chezmoi apply --force"
fi

configure_system

# Security: Clear sensitive environment variables
if [ -n "$BW_SESSION" ]; then
    echo "Clearing Bitwarden session from environment..."
    unset BW_SESSION
fi
if [ -n "$BW_PASSWORD" ]; then
    unset BW_PASSWORD
fi

if [ "${#WARN_LOG[@]}" -gt 0 ]; then
    echo ""
    echo "--- Warnings (degraded components) ---"
    for _w in "${WARN_LOG[@]}"; do
        echo "  WARN: $_w"
    done
fi

echo ""
echo "[DONE] Setup complete. Please reload your shell."
