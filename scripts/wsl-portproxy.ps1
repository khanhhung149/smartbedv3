# Chuyển tiếp cổng từ Windows vào các service chạy trong Docker/WSL.
#
# WSL2 trên Windows 10 chỉ có chế độ mạng NAT: WSL mang IP dải 172.x, thiết bị
# ngoài LAN (ESP32) không gọi thẳng vào được. Rule netsh portproxy bắc cầu từ
# IP LAN của Windows sang IP của WSL — nhưng IP đó ĐỔI sau mỗi lần khởi động
# lại, làm rule cũ trỏ vào hư không và ESP32 mất broker mà không báo lỗi gì.
#
# Chạy script này bằng PowerShell quyền Administrator sau mỗi lần khởi động máy,
# hoặc đăng ký chạy tự động (xem hướng dẫn ở cuối file).

$ErrorActionPreference = "Stop"

$ip = (wsl -- hostname -I).Trim().Split(" ")[0]
if (-not $ip) {
    Write-Error "Khong lay duoc IP cua WSL. WSL da chay chua?"
    exit 1
}

# 1883 = MQTT cho ESP32, 8080 = HTTP/WS API cho app Flutter.
foreach ($port in 1883, 8080) {
    netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$ip

    $name = "WSL port $port"
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $name -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
    }
}

Write-Host "Da tro 1883 va 8080 -> WSL $ip"
netsh interface portproxy show v4tov4

# Cho chay tu dong moi lan dang nhap Windows (chay 1 lan, PowerShell admin):
#
#   $me = "$env:USERPROFILE\Desktop\esp32-presence-ac\scripts\wsl-portproxy.ps1"
#   $a = New-ScheduledTaskAction -Execute "powershell.exe" `
#          -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$me`""
#   $t = New-ScheduledTaskTrigger -AtLogOn
#   $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
#   Register-ScheduledTask -TaskName "WSL portproxy" -Action $a -Trigger $t -Principal $p
