# Hướng dẫn cài đặt OpenSSH Server trên Windows

Tài liệu này hướng dẫn cách kích hoạt và cấu hình SSH Server trên Windows (bao gồm cả máy ảo Hyper-V) để có thể quản lý từ xa.

## 1. Cài đặt OpenSSH Server

Chạy PowerShell với quyền **Administrator** và thực thi lệnh sau:

```powershell
# Cách A: Dùng Windows Capability (Tiêu chuẩn cho Win 10/11 Pro)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Cách B: Dùng Winget (Khuyên dùng cho bản Windows 11 Eval hoặc khi Cách A lỗi)
winget install "Microsoft.OpenSSH.Preview"
```

## 2. Cấu hình Dịch vụ (Service)

Kích hoạt dịch vụ và thiết lập tự động khởi chạy cùng Windows:

```powershell
# Khởi động dịch vụ SSHD
Start-Service sshd

# Thiết lập tự động khởi chạy (Automatic)
Set-Service -Name sshd -StartupType 'Automatic'

# Kiểm tra trạng thái dịch vụ (Phải là 'Running')
Get-Service sshd
```

## 3. Cấu hình Tường lửa & Mạng (Firewall)

Để đảm bảo có thể kết nối từ bên ngoài (như máy Host), bạn cần mở cổng 22 và chuyển loại mạng về Private:

```powershell
# 1. Mở cổng 22 cho SSH trên mọi Profile mạng
New-NetFirewallRule -Name "SSH-In" -DisplayName "Allow SSH Inbound" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow

# 2. Chuyển cấu hình mạng sang Private (Dành cho Win 11 Eval - Giảm bớt chặn mặc định)
Set-NetConnectionProfile -InterfaceAlias "*" -NetworkCategory Private
```

## 4. Cấu hình Shell mặc định (Tùy chọn)

Nếu bạn muốn khi SSH vào sẽ sử dụng PowerShell thay vì CMD:

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

## 5. Kết nối thử nghiệm

Từ máy khách, hãy thử kết nối bằng lệnh:

```bash
ssh <username>@<ip-address>
```

**Linh hồn của hệ thống (Dotfiles):**
Sau khi SSH thành công, đừng quên chạy script cài đặt dotfiles để hoàn thiện môi trường làm việc:
```powershell
irm https://raw.githubusercontent.com/vovanphu/dotfiles/master/install.ps1 | iex
```
