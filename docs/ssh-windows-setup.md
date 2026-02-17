# Guide: Installing OpenSSH Server on Windows

This document guides you through enabling and configuring SSH Server on Windows (including Hyper-V VMs) for remote management.

## 1. Install OpenSSH Server

Run PowerShell as **Administrator** and execute the following commands:

```powershell
# Option A: Using Windows Capability (Standard for Win 10/11 Pro)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Option B: Using Winget (Recommended for Windows 11 Eval or if Option A fails)
winget install "Microsoft.OpenSSH.Preview"
```

## 2. Configure Service

Enable the service and set it to start automatically with Windows:

```powershell
# Start the SSHD service
Start-Service sshd

# Set to start automatically
Set-Service -Name sshd -StartupType 'Automatic'

# Verify service status (should be 'Running')
Get-Service sshd
```

## 3. Configure Firewall & Network

To ensure you can connect from outside (e.g., from the Host machine), you need to open port 22 and set the network category to Private:

```powershell
# 1. Open port 22 for SSH on all network profiles
New-NetFirewallRule -Name "SSH-In" -DisplayName "Allow SSH Inbound" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow

# 2. Set network profile to Private (Specifically for Win 11 Eval to reduce default blocks)
Set-NetConnectionProfile -InterfaceAlias "*" -NetworkCategory Private
```

## 4. Configure Default Shell (Optional)

If you want to use PowerShell instead of CMD when connecting via SSH:

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

## 5. Test Connection

From a client machine, try connecting using the following command:

```bash
ssh <username>@<ip-address>
```

**Final Step (Dotfiles):**
Once the SSH connection is successful, run the dotfiles installation script to complete your environment setup:
```powershell
irm https://raw.githubusercontent.com/vovanphu/arx/master/install.ps1 | iex
```

