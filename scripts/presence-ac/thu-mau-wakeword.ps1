<#
.SYNOPSIS
Thu mẫu giọng để train wakeword microWakeWord. Xuất wav 16 kHz mono 16-bit — đúng định dạng train.

.DESCRIPTION
Chạy trên Windows (PowerShell), KHÔNG chạy trong WSL: WSL2 không có thiết bị thu âm
(/dev/snd chỉ có timer). Dùng API MCI của winmm.dll nên không phải cài thêm gì.

Tự đếm ngược, tự thu, tự lưu, hiện mức âm sau mỗi mẫu. Đọc 300 lần là việc mệt — công cụ này
tồn tại để bạn chỉ phải đọc, không phải bấm.

Chạy lại là ghi TIẾP, không đè: nó dò số thứ tự lớn nhất đã có rồi đếm lên.

.EXAMPLE
.\thu-mau-wakeword.ps1 -Nhan vung-oi -SoMau 80
.\thu-mau-wakeword.ps1 -Nhan vung-rieng -SoMau 30 -GiayThu 1.5
.\thu-mau-wakeword.ps1 -Nhan hoi-thoai -SoMau 10 -GiayThu 60 -KhongDemNguoc
#>
param(
    [Parameter(Mandatory = $true)][string]$Nhan,
    [int]$SoMau = 20,
    [double]$GiayThu = 2.0,
    [double]$GiayNghi = 1.2,
    [string]$ThuMuc = "$env:USERPROFILE\wakeword-samples",
    # RMS dưới mức này coi như không nói -> tự thu lại. Đặt 0 để tắt.
    [int]$RmsToiThieu = 300,
    [switch]$KhongDemNguoc
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
using System.Text;
public class WakewordMci {
    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    public static extern int mciSendString(string cmd, StringBuilder ret, int len, System.IntPtr hwnd);
}
'@

function Invoke-Mci([string]$Lenh) {
    $sb = New-Object System.Text.StringBuilder 512
    $ma = [WakewordMci]::mciSendString($Lenh, $sb, 512, [System.IntPtr]::Zero)
    if ($ma -ne 0) { throw "MCI loi $ma khi chay: $Lenh" }
    return $sb.ToString()
}

# RMS đọc thẳng từ wav 16-bit. Cần để biết mẫu vừa thu có tiếng thật không — thu 300 mẫu mà
# cuối buổi mới phát hiện mic tắt thì mất cả buổi.
function Get-WavRms([string]$Duong) {
    $bytes = [System.IO.File]::ReadAllBytes($Duong)
    if ($bytes.Length -le 44) { return 0 }
    $tong = [double]0
    $dem = 0
    # Bỏ 44 byte header wav chuẩn. Lấy mẫu thưa (bước 2 sample) cho nhanh, đủ chính xác để phân biệt
    # "có tiếng" với "im lặng".
    for ($i = 44; $i -lt $bytes.Length - 1; $i += 4) {
        $v = [System.BitConverter]::ToInt16($bytes, $i)
        $tong += [double]$v * $v
        $dem++
    }
    if ($dem -eq 0) { return 0 }
    return [int][math]::Sqrt($tong / $dem)
}

# Ngưỡng để HIỂN THỊ cảnh báo. Cố ý tách khỏi $RmsToiThieu (ngưỡng tự-loại): tắt tự-loại bằng
# -RmsToiThieu 0 không được làm tắt luôn cảnh báo, nếu không thì mic chết sẽ hiện "OK" — đúng
# thứ công cụ này sinh ra để bắt.
$MUC_CANH_BAO_NHO = 300

function Show-Muc([int]$Rms) {
    # Thang log cho dễ nhìn: RMS tiếng nói thường 500-8000, trần int16 là 32767.
    $n = [math]::Min(30, [int](30 * [math]::Log10([math]::Max(1, $Rms)) / [math]::Log10(32767)))
    $thanh = ('#' * $n).PadRight(30, '.')
    if ($Rms -lt $MUC_CANH_BAO_NHO) { $mau = 'DarkGray'; $ghi = 'NHO QUA' }
    elseif ($Rms -gt 12000) { $mau = 'Yellow'; $ghi = 'TO QUA - lui ra xa' }
    else { $mau = 'Green'; $ghi = 'OK' }
    Write-Host ("   [$thanh] RMS=$Rms  $ghi") -ForegroundColor $mau
}

New-Item -ItemType Directory -Force -Path $ThuMuc | Out-Null

# Đếm tiếp từ file đã có, để chạy nhiều buổi mà không đè lên nhau.
$daCo = @(Get-ChildItem -Path $ThuMuc -Filter "$Nhan-*.wav" -ErrorAction SilentlyContinue)
$batDau = 0
foreach ($f in $daCo) {
    if ($f.BaseName -match "^$([regex]::Escape($Nhan))-(\d+)$") {
        $so = [int]$Matches[1]
        if ($so -gt $batDau) { $batDau = $so }
    }
}

Write-Host ""
Write-Host "=== Thu mau wakeword ===" -ForegroundColor Cyan
Write-Host "  nhan      : $Nhan"
Write-Host "  thu muc   : $ThuMuc"
Write-Host "  da co     : $($daCo.Count) mau -> ghi tiep tu so $($batDau + 1)"
Write-Host "  moi mau   : $GiayThu giay"
Write-Host "  can thu   : $SoMau mau"
Write-Host ""
Write-Host "  Ctrl+C de dung bat cu luc nao. Chay lai lenh nay se ghi tiep." -ForegroundColor DarkGray
Write-Host ""
Start-Sleep -Seconds 2

$thanhCong = 0
$i = 0
$lienTiepHong = 0   # đếm mẫu quá nhỏ liên tiếp, để phát hiện mic chết thay vì lặp vô tận
while ($thanhCong -lt $SoMau) {
    $i++
    $stt = $batDau + $thanhCong + 1
    $ten = Join-Path $ThuMuc ("{0}-{1:d4}.wav" -f $Nhan, $stt)

    if (-not $KhongDemNguoc) {
        foreach ($d in 3, 2, 1) {
            Write-Host "`r  chuan bi... $d" -NoNewline -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 600
        }
    }
    Write-Host ("`r  [{0}/{1}] NOI NGAY!            " -f ($thanhCong + 1), $SoMau) -ForegroundColor White

    Invoke-Mci 'open new type waveaudio alias recwk' | Out-Null
    try {
        Invoke-Mci 'set recwk time format ms bitspersample 16 channels 1 samplespersec 16000 bytespersec 32000 alignment 2' | Out-Null
        Invoke-Mci 'record recwk' | Out-Null
        Start-Sleep -Milliseconds ([int]($GiayThu * 1000))
        Invoke-Mci 'stop recwk' | Out-Null
        Invoke-Mci "save recwk `"$ten`"" | Out-Null
    }
    finally {
        # Phải close kể cả khi lỗi, không thì lần sau 'open new' báo alias đang bận.
        try { Invoke-Mci 'close recwk' | Out-Null } catch { }
    }

    $rms = Get-WavRms $ten
    Show-Muc $rms

    if ($RmsToiThieu -gt 0 -and $rms -lt $RmsToiThieu) {
        Remove-Item $ten -Force
        $lienTiepHong++
        Write-Host "   -> bo mau nay, thu lai" -ForegroundColor DarkYellow

        # Không có chốt này thì mic hỏng / mic bị mute = vòng lặp vô tận, user ngồi mãi không
        # hiểu vì sao số mẫu đứng yên. Hỏi sau mỗi 5 lần hỏng liên tiếp.
        if ($lienTiepHong -ge 5) {
            Write-Host ""
            Write-Host "   !! $lienTiepHong mau lien tiep deu qua nho (RMS < $RmsToiThieu)." -ForegroundColor Red
            Write-Host "      Kiem tra: mic co bi mute khong? Windows co chon dung thiet bi thu khong?" -ForegroundColor Red
            Write-Host "      (Settings > System > Sound > Input)" -ForegroundColor DarkGray
            $tl = Read-Host "      [Enter]=thu tiep / t=ha nguong xuong $([int]($RmsToiThieu/3)) / q=dung"
            if ($tl -eq 'q') { Write-Host "   dung." -ForegroundColor DarkYellow; break }
            if ($tl -eq 't') {
                $RmsToiThieu = [int]($RmsToiThieu / 3)
                Write-Host "      -> nguong moi: $RmsToiThieu" -ForegroundColor Yellow
            }
            $lienTiepHong = 0
        }
    }
    else {
        $thanhCong++
        $lienTiepHong = 0
    }

    Start-Sleep -Milliseconds ([int]($GiayNghi * 1000))
}

Write-Host ""
Write-Host "XONG: $thanhCong mau '$Nhan' trong $ThuMuc" -ForegroundColor Green
Write-Host "Tong so file cua nhan nay: $((Get-ChildItem -Path $ThuMuc -Filter "$Nhan-*.wav").Count)"
Write-Host ""
