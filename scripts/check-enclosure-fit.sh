#!/usr/bin/env bash
# Kiểm vỏ hộp 3 mảnh có lắp vừa nhau không, TRƯỚC khi tốn 3-4h in thử.
#
# Cách làm: lấy phép GIAO khối (CGAL) giữa từng cặp mảnh rồi tính THỂ TÍCH khối giao.
# Đếm số mặt là KHÔNG đủ — hai mảnh chạm nhau (mặt trùng mặt) vẫn sinh ra cả trăm mặt
# nhưng thể tích bằng 0. Chỉ thể tích > 0 mới là đè nhau thật.
#
# Bản v2 từng lọt: base∩face 1945mm³, base∩lid 264mm³ — cả 3 mảnh đều không lắp được.
#
# Dùng: scripts/check-enclosure-fit.sh
set -uo pipefail

SCAD_BIN="${OPENSCAD:-$HOME/.local/opt/squashfs-root/AppRun}"
HW="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hardware" && pwd)"
MODEL="vo-hop-modular.scad"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$HW/_fitcheck.scad"' EXIT

if [ ! -x "$SCAD_BIN" ]; then
  echo "Không tìm thấy OpenSCAD ở $SCAD_BIN — đặt biến OPENSCAD trỏ tới binary." >&2
  exit 1
fi

# Nắp nằm trên đỉnh trụ; face/base ở toạ độ tuyệt đối sẵn.
LID="translate([0,0,33]) lid()"

check() {  # $1=nhãn  $2=khối A  $3=khối B
  printf 'use <%s>\nintersection() { %s; %s; }\n' "$MODEL" "$2" "$3" > "$HW/_fitcheck.scad"
  ( cd "$HW" && "$SCAD_BIN" -o "$TMP/$1.stl" _fitcheck.scad ) >/dev/null 2>&1
  python3 - "$TMP/$1.stl" "$1" <<'PY'
import re, sys, os
path, label = sys.argv[1], sys.argv[2]
# OpenSCAD không ghi file khi khối giao rỗng -> đó chính là tín hiệu "không chạm".
if not os.path.exists(path) or os.path.getsize(path) == 0:
    print(f"  {label:22} rỗng          ✅"); raise SystemExit
verts = [tuple(map(float, m.groups()))
         for m in re.finditer(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)', open(path).read())]
v = 0.0
for i in range(0, len(verts), 3):
    a, b, c = verts[i:i+3]
    v += (a[0]*(b[1]*c[2]-c[1]*b[2]) - a[1]*(b[0]*c[2]-c[0]*b[2]) + a[2]*(b[0]*c[1]-c[0]*b[1])) / 6.0
v = abs(v)
if v < 0.01:
    print(f"  {label:22} {v:8.2f} mm³  ✅ chỉ chạm mặt")
else:
    lo = [min(p[i] for p in verts) for i in range(3)]
    hi = [max(p[i] for p in verts) for i in range(3)]
    box = " ".join(f"{ax}{lo[i]:.1f}..{hi[i]:.1f}" for i, ax in enumerate("xyz"))
    print(f"  {label:22} {v:8.2f} mm³  ❌ ĐÈ NHAU  [{box}]")
    raise SystemExit(1)
PY
}

# Lỗ phải THÔNG: đầu dò nằm trong lòng lỗ, giao với mảnh phải rỗng.
# Bắt lỗi "khoét hụt" — lệnh khoét không phủ hết bề dày, để lại lớp nhựa mỏng mà nhìn
# render bằng mắt không phát hiện được. Kiểu lỗi này đã xảy ra 3 lần.
hole() {  # $1=nhãn  $2=mảnh  $3=tên đầu dò
  check "$1" "$2" "probe(\"$3\")"
}

fail=0
echo "Mảnh với mảnh:"
check base-face "base()" "face()"          || fail=1
check base-lid  "base()" "$LID"            || fail=1
check face-lid  "face()" "$LID"            || fail=1

echo "Mảnh với board (ghosts = ESP32-S3 + IR + S2):"
check base-board "base()"  "ghosts()"      || fail=1
check face-board "face()"  "ghosts()"      || fail=1
check lid-board  "$LID"    "ghosts()"      || fail=1

echo "Lỗ có thông suốt không:"
hole face-usb       "face()" face-usb        || fail=1
hole face-ir        "face()" face-ir         || fail=1
hole base-s2-pilot  "base()" base-s2-pilot   || fail=1
hole base-s2-usb    "base()" base-s2-usb     || fail=1
hole base-s3-pilot  "base()" base-s3-pilot   || fail=1
hole lid-mic        "lid()"  lid-mic         || fail=1

# Ngược lại: màng radar PHẢI còn nhựa. Đầu dò 15×20×1 = 300mm³ nằm trong màng 1.5mm;
# giao phải bằng đúng 300 thì màng mới đặc. Bằng 0 nghĩa là đã khoét thủng.
echo "Màng radar có còn nhựa không:"
printf 'use <%s>\nintersection() { lid(); probe("lid-radar-mang"); }\n' "$MODEL" > "$HW/_fitcheck.scad"
( cd "$HW" && "$SCAD_BIN" -o "$TMP/mang.stl" _fitcheck.scad ) >/dev/null 2>&1
python3 - "$TMP/mang.stl" <<'PY' || fail=1
import re, sys, os
path = sys.argv[1]
if not os.path.exists(path) or os.path.getsize(path) == 0:
    print("  lid-radar-mang         rỗng  ❌ ĐÃ KHOÉT THỦNG, radar hở ra ngoài"); raise SystemExit(1)
verts = [tuple(map(float, m.groups()))
         for m in re.finditer(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)', open(path).read())]
v = 0.0
for i in range(0, len(verts), 3):
    a, b, c = verts[i:i+3]
    v += (a[0]*(b[1]*c[2]-c[1]*b[2]) - a[1]*(b[0]*c[2]-c[0]*b[2]) + a[2]*(b[0]*c[1]-c[0]*b[1])) / 6.0
v = abs(v)
ok = abs(v - 300.0) < 1.0
print(f"  lid-radar-mang       {v:8.2f} mm³  " + ("✅ đặc, đúng 300" if ok else "❌ thiếu nhựa (cần 300)"))
raise SystemExit(0 if ok else 1)
PY

echo
[ $fail -eq 0 ] && echo "TẤT CẢ ĐẠT — in được." || echo "CÓ LỖI — đừng in."
exit $fail
