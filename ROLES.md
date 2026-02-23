# Role Management Architecture

## Overview

This dotfiles system uses a **centralized role taxonomy** defined in [.chezmoi.yaml.tmpl](.chezmoi.yaml.tmpl). All templates reference role **capabilities** instead of hardcoding role names, ensuring consistency and maintainability.

---

## Role Taxonomy

### Admin/Management Roles

#### **centaur** - Portable Workstation (Laptop)
- **Description:** Mobile admin workstation
- **Capabilities:**
  - ✅ `has_master_key`: true
  - ❌ `has_server_key`: false
  - ❌ `receives_ssh`: false
  - ❌ `is_server`: false
  - ✅ `install_desktop_tools`: true

**Use Case:** Laptop for remote administration, doesn't need to receive SSH connections

---

#### **chimera** - Primary Development Workstation
- **Description:** Main desktop workstation with full capabilities
- **Capabilities:**
  - ✅ `has_master_key`: true
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ❌ `is_server`: false
  - ✅ `install_desktop_tools`: true

**Use Case:** Primary dev machine, can SSH into servers AND accept SSH connections

---

#### **griffin** - Secondary Workstation
- **Description:** Secondary desktop workstation
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ❌ `is_server`: false
  - ✅ `install_desktop_tools`: true

**Use Case:** Additional workstation, can SSH into servers and accept connections

---

### Server Fleet

#### **hydra** - Main Server
- **Description:** Primary application server
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ✅ `is_server`: true
  - ❌ `install_desktop_tools`: false

**Use Case:** Main production server

---

#### **cyclops** - Application Server
- **Description:** Application hosting server
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ✅ `is_server`: true
  - ❌ `install_desktop_tools`: false

**Use Case:** App-specific server (e.g., web server, API server)

---

#### **kraken** - Database Server
- **Description:** Database hosting server
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ✅ `is_server`: true
  - ❌ `install_desktop_tools`: false

**Use Case:** PostgreSQL, MySQL, MongoDB, etc.

---

#### **cerberus** - Security/Firewall Server
- **Description:** Security and network gateway
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ✅ `is_server`: true
  - ❌ `install_desktop_tools`: false

**Use Case:** Firewall, VPN gateway, reverse proxy

---

#### **golem** - Build/CI Server
- **Description:** CI/CD and build automation
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ✅ `is_server`: true
  - ❌ `install_desktop_tools`: false

**Use Case:** Jenkins, GitLab Runner, GitHub Actions runner

---

#### **minion** - Worker/Compute Node
- **Description:** Compute worker node
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ✅ `is_server`: true
  - ❌ `install_desktop_tools`: false

**Use Case:** Kubernetes node, batch processing, distributed computing

---

#### **siren** - Monitoring/Alerting Server
- **Description:** Monitoring and observability
- **Capabilities:**
  - ❌ `has_master_key`: false
  - ✅ `has_server_key`: true
  - ✅ `receives_ssh`: true
  - ✅ `is_server`: true
  - ❌ `install_desktop_tools`: false

**Use Case:** Prometheus, Grafana, alertmanager, log aggregation

---

## Role Capability Reference

| Capability | Description | Example Usage |
|------------|-------------|---------------|
| `has_master_key` | Gets master SSH key deployed | Admin workstations that need full access |
| `has_server_key` | Gets server SSH key deployed | Servers and workstations that SSH into servers |
| `receives_ssh` | Has authorized_keys configured | Machines that accept SSH connections |
| `is_server` | Server-specific configuration | Headless servers (no GUI, limited shell history) |
| `install_desktop_tools` | Installs GUI applications | Workstations with desktop environment |

---

## How to Add a New Role

### Step 1: Define Role in `.chezmoi.yaml.tmpl`

```yaml
data:
    roles:
        phoenix:  # New role name
            description: "Backup and recovery server"
            has_master_key: false
            has_server_key: true
            receives_ssh: true
            is_server: true
            install_desktop_tools: false
```

### Step 2: Update Role Groups

```yaml
    # Add to appropriate groups
    roles_with_server_key: {{ list "chimera" "hydra" ... "phoenix" | join " " | quote }}
    roles_receiving_ssh: {{ list "chimera" "hydra" ... "phoenix" | join " " | quote }}
    roles_server: {{ list "hydra" "cyclops" ... "phoenix" | join " " | quote }}
```

### Step 3: Update Capability Checks

```yaml
    # Update computed capabilities
    has_server_key: {{ has $role (list "chimera" ... "phoenix") }}
    receives_ssh: {{ has $role (list "chimera" ... "phoenix") }}
    is_server: {{ has $role (list "hydra" ... "phoenix") }}
```

### Step 4: Test

```bash
# Install with new role
ROLE=phoenix ./install.sh

# Verify capabilities
chezmoi data | grep -A5 "phoenix"
```

---

## Template Usage Examples

### ✅ CORRECT (Capability-based)

```go-template
{{- /* Deploy Master SSH key based on role capability */ -}}
{{- if .has_master_key -}}
{{-   if (env "BW_SESSION") -}}
{{-     $key := (bitwarden "item" "ssh-key-master-ed25519") -}}
{{ $key.notes }}
{{-   end -}}
{{- end -}}
```

### ❌ INCORRECT (Hardcoded roles)

```go-template
{{- /* DON'T DO THIS - not maintainable */ -}}
{{- if or (eq .role "centaur") (eq .role "chimera") -}}
{{-   if (env "BW_SESSION") -}}
{{-     $key := (bitwarden "item" "ssh-key-master-ed25519") -}}
{{ $key.notes }}
{{-   end -}}
{{- end -}}
```

---

## Architecture Benefits

### ✅ Single Source of Truth
- All role definitions in ONE place
- No scattered role checks across 15+ templates

### ✅ Consistent Behavior
- No more "missing roles" on Windows vs Linux
- Guaranteed behavior parity across platforms

### ✅ Self-Documenting
- Role capabilities clearly defined
- Easy to understand what each role gets

### ✅ Easy Maintenance
- Add new role: Update 1 file
- Change capability: Update 1 place
- No copy-paste errors

### ✅ Type Safety (Template-level)
- Pre-computed boolean capabilities
- No complex `or` chains in templates

---

## Validation

### Check Current Role Configuration

```bash
# View all role data
chezmoi data

# Check specific role capabilities
chezmoi execute-template '{{ .role }}: has_master_key={{ .has_master_key }}, is_server={{ .is_server }}'
```

### Verify File Deployment

```bash
# Check which SSH keys got deployed
ls -la ~/.ssh/id_ed25519_dotfiles_*

# Verify authorized_keys (servers only)
cat ~/.ssh/authorized_keys

# Check SSH config
cat ~/.ssh/config | grep -A2 "IdentityFile"
```

---

## Migration Guide

If you have old templates with hardcoded roles:

1. **Identify capability needed:**
   - SSH key deployment? → Use `.has_master_key` or `.has_server_key`
   - Server-specific config? → Use `.is_server`
   - Desktop tools? → Use `.is_workstation`

2. **Replace role checks:**
   ```diff
   - {{- if or (eq .role "chimera") (eq .role "hydra") ... }}
   + {{- if .receives_ssh }}
   ```

3. **Test thoroughly:**
   ```bash
   chezmoi apply --dry-run --verbose
   ```

---

## Troubleshooting

### "Role not recognized"
→ Check if role is defined in `.chezmoi.yaml.tmpl` under `data.roles`

### "Missing SSH key"
→ Verify role has correct capability: `has_master_key` or `has_server_key`

### "authorized_keys not created"
→ Check if `receives_ssh: true` in role definition

### "Desktop tools not installed"
→ Verify `install_desktop_tools: true` for workstation roles

---

## See Also

- [.chezmoi.yaml.tmpl](.chezmoi.yaml.tmpl) - Role definitions
- [ROLES.md](ROLES.md) - This file
- [SSH Merge Logic](run_once_after_98-merge-ssh-keys.sh.tmpl)
