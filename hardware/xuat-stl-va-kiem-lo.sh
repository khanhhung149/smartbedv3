#!/usr/bin/env bash
# Kiem hinh hoc vo-hop-sleeppad.scad bang chinh CGAL cua OpenSCAD, roi xuat STL.
#
# Bo sung cho kiem-va-cham-vo-hop-sleeppad.py: script Python dung hop bao (AABB) nen bat duoc
# khe ho va va cham tho, con script nay lam phep GIAO THAT tren khoi da duoc render — thu duy
# nhat tra loi duoc "lo co thung khong". Ba lan loi "khoet hut" o ho voice-node (lenh khoet
# khong phu het be day, con lai mot lop nhua mong) deu KHONG nhin ra tren render, va AABB cung
# khong bat duoc vi hop bao cua lo van dung.
#
# Nguyen tac: giao phai RONG, do bang THE TICH chu khong bang "co file hay khong".
#
# Do bang su ton tai cua file la SAI, da dinh mot lan: base() ∩ ghosts() ra 490 mat, nhin thi
# tuong linh kien nam trong nhua, nhung the tich = 0.000000 mm3. Do la cac mat TIEP XUC ma
# thiet ke co y: day bo tì len noc tru (cung z=13), day khoi USB-A tì len san (cung z=3), mat
# truoc khoi ap vao mat trong vach (cung y=3). CGAL van xuat facet cho nhung mat trung nhau do.
# Doi tieu chi sang the tich thi phan biet duoc "cham nhau" voi "loi vao nhau" — ma cham nhau
# chinh la thu thiet ke NAY CAN co.
#
# Phai co phep DOI CHUNG o dau (base() phai ra khoi dac) — neu khong thi mot loi cu phap lam
# moi thu rong va script bao "dat het".
#
# Chay:  bash hardware/enclosure/xuat-stl-va-kiem-lo.sh [thu_muc_xuat_stl]
set -u

THU_MUC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$THU_MUC/vo-hop-sleeppad.scad"
XUAT="${1:-$THU_MUC/stl}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v openscad >/dev/null || { echo "khong tim thay openscad"; exit 127; }
mkdir -p "$XUAT"

rot=0

# render <ten> <bieu_thuc_scad> -> in ra so byte STL (0 = khoi rong)
render() {
    # Tach 3 dong: trong CUNG mot lenh `local`, ve phai khong thay bien vua gan o truoc
    # (`local a=$1 b=$TMP/$a` -> voi `set -u` la loi unbound).
    local ten="$1"
    local bieu_thuc="$2"
    local out="$TMP/$ten.stl"
    printf 'use <%s>\n%s\n' "$SRC" "$bieu_thuc" > "$TMP/$ten.scad"
    openscad -o "$out" "$TMP/$ten.scad" > "$TMP/$ten.log" 2>&1
    if grep -q "Ignoring unknown module\|ERROR" "$TMP/$ten.log"; then
        echo "  LOI CU PHAP trong $ten:"; sed 's/^/      /' "$TMP/$ten.log" | head -5
        return 2
    fi
    the_tich "$out"
}

# the_tich <file.stl> -> mm3. OpenSCAD 2021.01 xuat STL dang ASCII.
# Tong the tich tu dien co dau: V = sum( v0 . (v1 x v2) ) / 6.
the_tich() {
    [[ -s "$1" ]] || { echo "0.0000"; return; }
    python3 -c '
import re, sys
v = [tuple(map(float, m.groups()))
     for m in re.finditer(r"vertex\s+(\S+)\s+(\S+)\s+(\S+)", open(sys.argv[1]).read())]
V = 0.0
for i in range(0, len(v), 3):
    a, b, c = v[i], v[i+1], v[i+2]
    V += (a[0]*(b[1]*c[2]-b[2]*c[1]) - a[1]*(b[0]*c[2]-b[2]*c[0]) + a[2]*(b[0]*c[1]-b[1]*c[0])) / 6
print(f"{abs(V):.4f}")
' "$1"
}

# Nguong 0.01mm3: duoi muc nay chi co the la mat trung nhau, khong the la khoi loi vao nhau
# (khoi mong nhat ma thiet ke nay quan tam la 0.4mm khe lap, tuc hang chuc mm3 neu bi an mat).
lon_hon() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)' "$1" "$2"; }

# Phai RONG (the tich ~ 0).
rong() {
    local nhan="$1"
    local bieu_thuc="$2"
    local v
    v=$(render "$(echo "$nhan" | tr -c 'a-zA-Z0-9' '_')" "$bieu_thuc") || { rot=$((rot+1)); return; }
    if lon_hon "$v" 0.01; then
        echo "  FAIL  $nhan   [giao that su: $v mm3]"; rot=$((rot+1))
    else
        echo "  ok    $nhan   [$v mm3]"
    fi
}

# Phai CO khoi — phep doi chung.
dac() {
    local nhan="$1"
    local bieu_thuc="$2"
    local v
    v=$(render "$(echo "$nhan" | tr -c 'a-zA-Z0-9' '_')" "$bieu_thuc") || { rot=$((rot+1)); return; }
    if lon_hon "$v" 1000; then echo "  ok    $nhan   [$v mm3]"
    else echo "  FAIL  $nhan   [khoi RONG/qua nho — script dang do cai gi do sai]"; rot=$((rot+1)); fi
}

NAP="translate([0,0,3+22]) lid();"   # nap dat dung cho lap rap (floor_t + deck_h)

echo "=== doi chung: cac manh phai ra khoi dac ==="
dac "base() ra khoi"  "base();"
dac "lid() ra khoi"   "lid();"

echo
echo "=== dau do lo khoet: giao voi manh phai RONG ==="
rong "cua USB-A thung han be day vach"   'intersection() { base(); probe("usba"); }'
rong "cua USB-C thung han be day vach"   'intersection() { base(); probe("usbc"); }'
rong "2 lo moi M2.5 co that"             'intersection() { base(); probe("s3-pilot"); }'
rong "ranh thoat day tren vach chan"     'intersection() { base(); probe("usba-wire"); }'

echo
echo "=== lap rap: cac manh khong duoc dam nhau ==="
# Day la phep bat duoc loi nang nhat cua ho voice-node ban v2 (go tut nap dam vao 4 tru goc,
# 1512 mat giao nhau) — loi ma render nhin van thay "nap dat vua khit".
rong "base khong dam lid"                "intersection() { base(); $NAP }"

echo
echo "=== linh kien that: khong duoc nam trong nhua ==="
rong "linh kien khong dam base"          'intersection() { base(); ghosts(); }'
rong "linh kien khong dam lid"           "intersection() { $NAP ghosts(); }"

echo
echo "=== xuat STL -> $XUAT ==="
for p in base lid test-usba test-s3 test-s3-truoc; do
    if openscad -o "$XUAT/vo-hop-sleeppad-$p.stl" -D "part=\"$p\"" "$SRC" \
        > "$TMP/x-$p.log" 2>&1 && [[ -s "$XUAT/vo-hop-sleeppad-$p.stl" ]]; then
        echo "  ok    vo-hop-sleeppad-$p.stl   [$(stat -c%s "$XUAT/vo-hop-sleeppad-$p.stl") byte]"
    else
        echo "  FAIL  vo-hop-sleeppad-$p.stl"; sed 's/^/      /' "$TMP/x-$p.log" | head -5
        rot=$((rot+1))
    fi
done

echo
if [[ $rot -eq 0 ]]; then echo "tat ca dat."; else echo "$rot muc HONG."; fi
exit $((rot > 0 ? 1 : 0))
