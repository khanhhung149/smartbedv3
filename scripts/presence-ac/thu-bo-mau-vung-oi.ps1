<#
.SYNOPSIS
Chạy trọn buổi thu mẫu cho wakeword "vừng ơi" — cả mẫu dương lẫn hard negative.

.DESCRIPTION
Bọc quanh thu-mau-wakeword.ps1. Mục đích: bạn chỉ chạy MỘT lệnh rồi đọc theo hướng dẫn trên màn
hình, không phải nhớ 10 lệnh với tham số khác nhau.

Mỗi nhóm hỏi trước khi bắt đầu, nên nghỉ giữa chừng thoải mái. Chạy lại là ghi TIẾP, không đè —
nhóm nào đủ số thì tự bỏ qua.

Vì sao cần hard negative nhiều đến vậy: "ơi" là từ đệm cực phổ biến trong tiếng Việt ("mẹ ơi",
"anh ơi"). Không dạy model phân biệt thì nó kích mỗi lần bạn gọi ai đó.

.EXAMPLE
.\thu-bo-mau-vung-oi.ps1
.\thu-bo-mau-vung-oi.ps1 -ChiNhom duong      # chỉ thu mẫu dương
.\thu-bo-mau-vung-oi.ps1 -ChiNhom am         # chỉ thu hard negative
#>
param(
    [ValidateSet('tatca', 'duong', 'am')][string]$ChiNhom = 'tatca',
    [string]$ThuMuc = "$env:USERPROFILE\wakeword-samples"
)

$ErrorActionPreference = 'Stop'
$thuMau = Join-Path $PSScriptRoot 'thu-mau-wakeword.ps1'
if (-not (Test-Path $thuMau)) { throw "Khong thay $thuMau" }

# nhan, so mau, giay/mau, huong dan doc
$NHOM_DUONG = @(
    @{ nhan = 'vungoi-thuong'; so = 80; giay = 2.0; huong = 'Nói "VỪNG ƠI" (có dấu huyền!) BÌNH THƯỜNG, cách mic ~50cm' }
    @{ nhan = 'vungoi-nhanh'; so = 40; giay = 1.5; huong = 'Nói "VỪNG ƠI" NHANH, như lúc đang vội' }
    @{ nhan = 'vungoi-cham'; so = 40; giay = 2.5; huong = 'Nói "VỪNG ƠI" CHẬM, rõ từng chữ' }
    @{ nhan = 'vungoi-nho'; so = 30; giay = 2.0; huong = 'Nói "VỪNG ƠI" NHỎ tiếng, như ban đêm' }
    @{ nhan = 'vungoi-xa'; so = 40; giay = 2.0; huong = 'Đứng XA ~2m rồi nói "VỪNG ƠI"' }
    @{ nhan = 'vungoi-lech'; so = 30; giay = 2.0; huong = 'Nói "VỪNG ƠI" khi quay lưng / nghiêng đầu, KHÔNG hướng vào mic' }
)

# Hard negative. "am" = am tinh, khong duoc kich.
$NHOM_AM = @(
    # Số mẫu âm ĐÃ TĂNG sau khi user chốt giữ cụm 2 âm tiết (06/08). Cụm càng ngắn càng ít thông
    # tin để phân biệt, mà "ơi" lại là từ đệm dùng hàng ngày — bù bằng hard negative là cách duy
    # nhất còn lại. Nhóm "gọi người" nặng nhất vì đó là nguồn báo giả thật sự trong sinh hoạt.
    @{ nhan = 'am-vung'; so = 40; giay = 1.5; huong = 'Chỉ nói "VỪNG" - MỘT từ thôi' }
    # 80, không phải 50: đo trên board 07/08 cho thấy "ơi" MỘT MÌNH kích 7/10 lần, tb chạm 0.996
    # (đúng trần cứng của model). Đây là nguồn báo giả nặng nhất, cần nhiều mẫu nhất.
    @{ nhan = 'am-oi'; so = 80; giay = 1.5; huong = 'Chỉ nói "ƠI" - MỘT từ thôi' }
    # 80, không phải 60: đây là dạng "ơi" xuất hiện thật trong nhà, sát ngữ cảnh sử dụng nhất.
    @{ nhan = 'am-goi-nguoi'; so = 80; giay = 2.0; huong = 'Gọi người: "mẹ ơi", "anh ơi", "em ơi", "ơi trời", "bà ơi" - đổi luân phiên' }
    @{ nhan = 'am-gan-am'; so = 50; giay = 1.5; huong = 'Từ GẦN ÂM: "vâng", "vùng", "vừa", "dừng", "vung ơi" (KHÔNG dấu huyền) - đổi luân phiên' }
    @{ nhan = 'am-hoithoai'; so = 10; giay = 60.0; huong = 'Nói chuyện / đọc báo BÌNH THƯỜNG 60 giây, KHÔNG được nói cụm đánh thức' }
)

function Dem-DaCo([string]$Nhan) {
    return @(Get-ChildItem -Path $ThuMuc -Filter "$Nhan-*.wav" -ErrorAction SilentlyContinue).Count
}

function Chay-Nhom($nhom, [string]$tieuDe) {
    Write-Host ""
    Write-Host "############ $tieuDe ############" -ForegroundColor Cyan
    foreach ($g in $nhom) {
        $daCo = Dem-DaCo $g.nhan
        $con = $g.so - $daCo
        Write-Host ""
        Write-Host ("--- {0}  ({1}/{2} da co) ---" -f $g.nhan, $daCo, $g.so) -ForegroundColor Yellow
        if ($con -le 0) {
            Write-Host "   du roi, bo qua" -ForegroundColor DarkGray
            continue
        }
        Write-Host ("   HUONG DAN: {0}" -f $g.huong) -ForegroundColor White
        Write-Host ("   Con thieu {0} mau, moi mau {1} giay" -f $con, $g.giay)
        $tl = Read-Host "   Bat dau? [Enter]=co / s=bo qua / q=dung han"
        if ($tl -eq 'q') { Write-Host "   dung." -ForegroundColor DarkYellow; return $false }
        if ($tl -eq 's') { continue }

        # Hội thoại dài thì không đếm ngược và không tự loại theo RMS (im lặng giữa câu là bình thường).
        $daiHoiThoai = $g.giay -ge 30
        # Splat bằng HASHTABLE, không phải mảng. Splat mảng truyền theo VỊ TRÍ, nên '-Nhan' rơi
        # vào tham số 1 và giá trị rơi vào tham số 2 -> lỗi ép kiểu. Hashtable mới truyền theo TÊN.
        # (Không đặt tên biến là $args — đó là biến tự động của PowerShell.)
        $thamSo = @{ Nhan = $g.nhan; SoMau = $con; GiayThu = $g.giay; ThuMuc = $ThuMuc }
        if ($daiHoiThoai) { $thamSo.RmsToiThieu = 0; $thamSo.KhongDemNguoc = $true }
        & $thuMau @thamSo
    }
    return $true
}

Write-Host ""
Write-Host "=== THU BO MAU WAKEWORD 'vung oi' ===" -ForegroundColor Green
Write-Host "  thu muc: $ThuMuc"
Write-Host ""
Write-Host "  Đọc ĐÚNG cụm bạn sẽ dùng thật: VỪNG ƠI (vừng có DẤU HUYỀN)." -ForegroundColor White
Write-Host "  Đọc TỰ NHIÊN như khi sai bảo điều hòa, đừng đọc kiểu rõ chữ quá mức -" -ForegroundColor White
Write-Host "  model học gì thì nhận nấy, đọc kiểu lạ thì lúc dùng thật nó không nhận." -ForegroundColor White
Write-Host ""

$tiep = $true
if ($ChiNhom -in 'tatca', 'duong') { $tiep = Chay-Nhom $NHOM_DUONG 'MAU DUONG (phai kich)' }
if ($tiep -and $ChiNhom -in 'tatca', 'am') { Chay-Nhom $NHOM_AM 'HARD NEGATIVE (KHONG duoc kich)' | Out-Null }

Write-Host ""
Write-Host "=== TONG KET ===" -ForegroundColor Green
foreach ($g in ($NHOM_DUONG + $NHOM_AM)) {
    $c = Dem-DaCo $g.nhan
    $mau = if ($c -ge $g.so) { 'Green' } else { 'DarkYellow' }
    Write-Host ("  {0,-18} {1,3}/{2,3}" -f $g.nhan, $c, $g.so) -ForegroundColor $mau
}
Write-Host ""
Write-Host "File nam o: $ThuMuc" -ForegroundColor Cyan
Write-Host "Chay lai lenh nay bat cu luc nao de thu tiep phan con thieu." -ForegroundColor DarkGray
Write-Host ""
