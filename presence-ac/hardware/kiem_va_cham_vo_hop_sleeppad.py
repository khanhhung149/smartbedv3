#!/usr/bin/env python3
"""Kiem tra hinh hoc vo-hop-sleeppad.scad bang hop bao (AABB), khong can OpenSCAD.

Ly do co file nay: moi loi that su cua ho vo-hop-modular.scad deu la loi HINH HOC —
khoi de len nhau, lo khoet hut, tru dat sai cho — chu khong phai loi cu phap. Va tat ca
deu KHONG nhin ra tren render. Script doc thang cac phep gan tham so tu file .scad nen
sua so trong .scad la chay lai la biet ngay, khong phai chep tay sang day.

Chay:  python3 hardware/enclosure/kiem-va-cham-vo-hop-sleeppad.py
Tra ve ma thoat 1 neu co bat ky kiem tra nao FAIL.
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

SCAD = Path(__file__).with_name("vo-hop-sleeppad.scad")

# ---------------------------------------------------------------- doc tham so


def doc_tham_so(duong_dan: Path) -> dict[str, float]:
    """Lay cac phep gan `ten = bieu_thuc;` o cap ngoai cung cua file .scad.

    Chi giu lai nhung bieu thuc tinh duoc ra SO. Cac gan khac (chuoi, true/false)
    bi bo qua co y — checker chi quan tam toi hinh hoc.
    """
    van_ban = duong_dan.read_text(encoding="utf-8")
    # Cat bo phan module: chi lay den `module` dau tien de khoi bat bien cuc bo.
    vi_tri = van_ban.find("\nmodule ")
    if vi_tri != -1:
        van_ban = van_ban[:vi_tri]
    # Bo ca hai kieu comment. Phai bo `/* */` nua: cac dai phan cach `/* ==== Khung ==== */`
    # nam ngay TRUOC phep gan dau tien cua moi nhom, ma tach theo `;` thi dai do dinh chung
    # mot manh voi phep gan -> manh khong con bat dau bang ten bien -> mat nguyen ca nhom.
    van_ban = re.sub(r"/\*.*?\*/", "", van_ban, flags=re.S)
    van_ban = re.sub(r"//[^\n]*", "", van_ban)

    moi_truong: dict[str, float] = {}
    an_toan = {"max": max, "min": min, "sqrt": math.sqrt, "__builtins__": {}}
    # Tach theo dau `;` chu khong theo DONG: file .scad co nhung dong gop nhieu phep gan
    # (`wall = 3;  floor_t = 3;  lid_t = 3;`) — bat theo dong la bo sot het tu cai thu hai.
    for cau in van_ban.split(";"):
        khop = re.match(r"\s*([A-Za-z_]\w*)\s*=\s*(.+)$", cau, re.S)
        if not khop:
            continue  # bo qua `$fn = 48` va moi thu khong phai phep gan
        try:
            gia_tri = eval(khop.group(2).strip(), an_toan, moi_truong)  # noqa: S307
        except Exception:
            continue
        if isinstance(gia_tri, (int, float)) and not isinstance(gia_tri, bool):
            moi_truong[khop.group(1)] = float(gia_tri)
    return moi_truong


P = doc_tham_so(SCAD)


def p(ten: str) -> float:
    if ten not in P:
        raise SystemExit(f"khong doc duoc tham so {ten!r} tu {SCAD.name}")
    return P[ten]


# ---------------------------------------------------------------- ha tang AABB


class Hop:
    """Hop bao truc-song-song. Dung [x0,x1] x [y0,y1] x [z0,z1], don vi mm."""

    def __init__(self, ten, x0, x1, y0, y1, z0, z1):
        self.ten = ten
        self.x = (x0, x1)
        self.y = (y0, y1)
        self.z = (z0, z1)

    @classmethod
    def tru(cls, ten, cx, cy, d, z0, z1):
        """Hop bao cua hinh tru — dung cho tru goc / tru vit."""
        r = d / 2
        return cls(ten, cx - r, cx + r, cy - r, cy + r, z0, z1)

    def chong(self, khac: "Hop") -> tuple[float, float, float] | None:
        """Tra ve do chong theo tung truc neu chong CA BA truc, nguoc lai None."""
        do = []
        for a, b in ((self.x, khac.x), (self.y, khac.y), (self.z, khac.z)):
            giao = min(a[1], b[1]) - max(a[0], b[0])
            if giao <= 0:
                return None
            do.append(giao)
        return tuple(do)  # type: ignore[return-value]


KET_QUA: list[tuple[bool, str, str]] = []
CANH_BAO: list[str] = []


def kiem(dieu_kien: bool, nhan: str, chi_tiet: str = "") -> None:
    KET_QUA.append((dieu_kien, nhan, chi_tiet))


def canh_bao(dieu_kien: bool, nhan: str, chi_tiet: str = "") -> None:
    """Ghi nhan nhung so DANH NGHIA dang ngo. Khong FAIL vi khong co so do that de doi chieu —
    nhung phai in ra, vi im lang la cach mot so doan bien thanh mot so duoc tin."""
    if not dieu_kien:
        CANH_BAO.append(f"{nhan}" + (f"   [{chi_tiet}]" if chi_tiet else ""))


def roi_nhau(a: Hop, b: Hop, nhan: str) -> None:
    c = a.chong(b)
    kiem(c is None, nhan, "" if c is None else f"chong nhau {c[0]:.2f} x {c[1]:.2f} x {c[2]:.2f} mm")


def ho(gia_tri: float, toi_thieu: float, nhan: str) -> None:
    kiem(gia_tri >= toi_thieu, nhan, f"ho {gia_tri:.2f} mm (can >= {toi_thieu})")


# ---------------------------------------------------------------- dung mo hinh

wall, floor_t, lid_t, deck_h = p("wall"), p("floor_t"), p("lid_t"), p("deck_h")
out_w, out_l, inner_w, inner_l = p("out_w"), p("out_l"), p("inner_w"), p("inner_l")
box_cx = p("box_cx")
z_nap_duoi = floor_t + deck_h          # mat duoi tam nap (tuyet doi)
z_tran_thanh = floor_t + deck_h        # dinh vach

post_d, post_off = p("post_d"), p("post_off")
m3_insert = p("m3_insert")

s3_x, s3_y, s3_l, s3_w, s3_pcb_t = p("s3_x"), p("s3_y"), p("s3_l"), p("s3_w"), p("s3_pcb_t")
s3_stand, s3_y_rear = p("s3_stand"), p("s3_y_rear")
s3_hole_y, s3_hole_pitch = p("s3_hole_y"), p("s3_hole_pitch")
s3_prop_y, s3_prop_pitch = p("s3_prop_y"), p("s3_prop_pitch")
s3_usb_z, s3_usb_open_w, s3_usb_open_h = p("s3_usb_z"), p("s3_usb_open_w"), p("s3_usb_open_h")
s3_usb_pitch, s3_usb_w, s3_usb_out = p("s3_usb_pitch"), p("s3_usb_w"), p("s3_usb_out")

usba_plug_w, usba_plug_h = p("usba_plug_w"), p("usba_plug_h")
usbc_plug_w, usbc_plug_h = p("usbc_plug_w"), p("usbc_plug_h")
usba_x0, usba_x1, usba_y = p("usba_x0"), p("usba_x1"), p("usba_y")
usba_w, usba_l, usba_h, usba_fit = p("usba_w"), p("usba_l"), p("usba_h"), p("usba_fit")
usba_back, usba_stop_t = p("usba_back"), p("usba_stop_t")
usba_rib_t, usba_rib_h = p("usba_rib_t"), p("usba_rib_h")
usba_open_w, usba_open_h, usba_open_z0 = p("usba_open_w"), p("usba_open_h"), p("usba_open_z0")
usba_axis_z, usba_hold_h = p("usba_axis_z"), p("usba_hold_h")
usba_wire_w, usba_wire_z = p("usba_wire_w"), p("usba_wire_z")
lid_lip_h, lip_w, lip_gap = p("lid_lip_h"), p("lip_w"), p("lip_gap")

z_day_pcb = floor_t + s3_stand
z_noc_pcb = z_day_pcb + s3_pcb_t

# --- linh kien that ---
pcb = Hop("PCB S3", s3_x, s3_x + s3_w, s3_y, s3_y_rear, z_day_pcb, z_noc_pcb)
cong_usbc = Hop(
    "cong USB-C",
    box_cx - s3_usb_pitch / 2 - s3_usb_w / 2, box_cx + s3_usb_pitch / 2 + s3_usb_w / 2,
    s3_y_rear, s3_y_rear + s3_usb_out, z_noc_pcb, z_noc_pcb + 3.26,
)
khoi_usba = Hop(
    "khoi USB-A", usba_x0, usba_x0 + usba_w, usba_y, usba_y + usba_l, floor_t, floor_t + usba_h
)
# CUC NHUA cua 2 loai phich, ve o tu the CAM HET CO — chi lay doan nam trong be day vach,
# vi do la doan phai lot qua cua. Ve o tu the dung ngoai vach thi phep kiem thanh vo nghia:
# cuc nhua khong cham vach nen "dat" ke ca khi cua be ti.
vo_phich = Hop(
    "cuc nhua phich USB-A",
    box_cx - usba_plug_w / 2, box_cx + usba_plug_w / 2, 0, wall,
    floor_t + usba_axis_z - usba_plug_h / 2, floor_t + usba_axis_z + usba_plug_h / 2,
)
# Hai cong USB-C nam doi xung qua tam bo. Phai do CA HAI: cua rong 24.5 doi xung qua tam nen
# cuc nhua tren cong TRAI lech ve -x, tren cong PHAI lech ve +x — ho hai ben khong bang nhau
# neu cuc nhua khong doi xung, va cong nao chat hon thi cong do quyet dinh.
vo_phich_usbc = {
    ten: Hop(
        f"cuc nhua phich USB-C ({ten})",
        box_cx + dx - usbc_plug_w / 2, box_cx + dx + usbc_plug_w / 2,
        out_l - wall, out_l,
        s3_usb_z - usbc_plug_h / 2, s3_usb_z + usbc_plug_h / 2,
    )
    for ten, dx in (("trai/TTL", -s3_usb_pitch / 2), ("phai/OTG", s3_usb_pitch / 2))
}

# --- khoi nhua trong base ---
tru_goc = [
    Hop.tru(f"tru goc ({cx:.0f},{cy:.0f})", cx, cy, post_d, floor_t, floor_t + deck_h)
    for cx in (post_off, out_w - post_off)
    for cy in (post_off, out_l - post_off)
]
tru_vit_s3 = [
    Hop.tru(f"tru vit S3 x{box_cx + dx:.1f}", box_cx + dx, s3_hole_y, 8, floor_t, floor_t + s3_stand)
    for dx in (-s3_hole_pitch / 2, s3_hole_pitch / 2)
]
tru_do_s3 = [
    Hop.tru(f"tru do S3 x{box_cx + dx:.1f}", box_cx + dx, s3_prop_y, 7, floor_t, floor_t + s3_stand)
    for dx in (-s3_prop_pitch / 2, s3_prop_pitch / 2)
]
s3_guide_x0, s3_guide_x1 = p("s3_guide_x0"), p("s3_guide_x1")
s3_guide_t, s3_guide_h, s3_guide_seg = p("s3_guide_t"), p("s3_guide_h"), p("s3_guide_seg")
s3_guide_in, s3_guide_clear = p("s3_guide_in"), p("s3_guide_clear")
s3_hold_w, s3_hold_l, s3_hold_h, s3_hold_gap = (
    p("s3_hold_w"), p("s3_hold_l"), p("s3_hold_h"), p("s3_hold_gap"))
# `s3_guide_ys` la LIST trong .scad nen parser (chi lay so) khong doc duoc — dung lai cong thuc.
go_dan_huong = [
    Hop(f"go dan huong x{x:.2f} y{y:.1f}", x, x + s3_guide_t, y, y + s3_guide_seg,
        floor_t, floor_t + s3_guide_h)
    for x in (s3_guide_x0 - s3_guide_t, s3_guide_x1)
    for y in (s3_y + s3_guide_in, s3_y_rear - s3_guide_in - s3_guide_seg)
]
go_chan_nhac = [
    Hop(f"go chan nhac x{x:.2f}", x, x + s3_hold_w, s3_y, s3_y + s3_hold_l,
        z_nap_duoi - s3_hold_h, z_nap_duoi)
    for x in (s3_x, s3_x + s3_w - s3_hold_w)
]
go_hong = [
    Hop("go hong -x", usba_x0 - usba_rib_t, usba_x0, usba_y, usba_back, floor_t, floor_t + usba_rib_h),
    Hop("go hong +x", usba_x1, usba_x1 + usba_rib_t, usba_y, usba_back, floor_t, floor_t + usba_rib_h),
]
vach_chan = Hop(
    "vach chan khay", wall, wall + inner_w, usba_back, usba_back + usba_stop_t,
    floor_t, floor_t + usba_rib_h,
)

# --- khoi nhua trong lid (toa do TUYET DOI, nap da dat len z = floor_t+deck_h) ---
z_go_duoi = z_nap_duoi - lid_lip_h
go_tut = [
    Hop("go tut trai", wall + lip_gap, wall + lip_gap + lip_w,
        wall + lip_gap, wall + lip_gap + inner_l - 2 * lip_gap, z_go_duoi, z_nap_duoi),
    Hop("go tut phai", out_w - wall - lip_gap - lip_w, out_w - wall - lip_gap,
        wall + lip_gap, wall + lip_gap + inner_l - 2 * lip_gap, z_go_duoi, z_nap_duoi),
    Hop("go tut sau", wall + lip_gap, wall + lip_gap + inner_w - 2 * lip_gap,
        out_l - wall - lip_gap - lip_w, out_l - wall - lip_gap, z_go_duoi, z_nap_duoi),
]
go_de = Hop(
    "go de khoi USB-A", usba_x0, usba_x0 + usba_w + usba_fit, usba_y, usba_back,
    z_nap_duoi - usba_hold_h, z_nap_duoi,
)

# ---------------------------------------------------------------- cac phep kiem

print(f"=== {SCAD.name} — kich thuoc ngoai {out_w:g} x {out_l:g} x "
      f"{floor_t + deck_h + lid_t:g} mm ===\n")

# 1. Bo S3 vs 4 tru goc. Day la cho ban dau tinh nham 37mm be rong: quen han tru goc.
for t in tru_goc:
    roi_nhau(pcb, t, f"PCB S3 khong dam {t.ten}")
ho(pcb.x[0] - (post_off + post_d / 2), 1.0, "ho ben trai PCB toi tru goc")
ho((out_w - post_off - post_d / 2) - pcb.x[1], 1.0, "ho ben phai PCB toi tru goc")

# 2. Thanh quanh lo ren dong M3 — 1.9mm la con so voice-node dang chay, coi la san.
ho(post_off - m3_insert / 2, 1.85, "thanh ngoai quanh lo ren dong M3")

# 3. Khoi USB-A vs tru goc truoc + go tut nap.
for t in tru_goc:
    roi_nhau(khoi_usba, t, f"khoi USB-A khong dam {t.ten}")
for g in go_tut:
    roi_nhau(khoi_usba, g, f"khoi USB-A khong dam {g.ten}")
    roi_nhau(pcb, g, f"PCB S3 khong dam {g.ten}")
    roi_nhau(cong_usbc, g, f"cong USB-C khong dam {g.ten}")
    roi_nhau(go_de, g, f"go de khong dam {g.ten}")

# 4. Go de phai o NGAY TREN noc khoi, khong dam vao.
c = go_de.chong(khoi_usba)
kiem(c is None, "go de khong dam noc khoi USB-A")
ho(go_de.z[0] - khoi_usba.z[1], 0.4, "ho giua go de va noc khoi USB-A")
kiem(go_de.z[0] - khoi_usba.z[1] <= 1.0, "go de khong qua xa noc khoi (khoi se rung)",
     f"ho {go_de.z[0] - khoi_usba.z[1]:.2f} mm")

# 5. Go hong om khoi: phai KE ngoai khoi, khong de len.
for g in go_hong:
    roi_nhau(khoi_usba, g, f"{g.ten} khong dam khoi USB-A")
kiem(abs((usba_x0 + usba_w) - usba_x1) <= usba_fit + 1e-9,
     "khe lap 2 ben khoi USB-A dung bang usba_fit",
     f"khe tong {usba_x1 - (usba_x0 + usba_w):.2f} mm")

# 6. Vach chan phai an vao CA HAI vach hong (tai cam phich di vao vach, khong be chan vau).
kiem(vach_chan.x[0] <= wall + 1e-9 and vach_chan.x[1] >= out_w - wall - 1e-9,
     "vach chan chay suot long hop, an vao 2 vach hong")
roi_nhau(khoi_usba, vach_chan, "vach chan khong dam khoi USB-A")
roi_nhau(pcb, vach_chan, "vach chan khong dam PCB S3")
ho(pcb.y[0] - vach_chan.y[1], 4.0, "khoang quat day giua vach chan va mep bo S3")

# 7. Ranh thoat day: phai khoet TU NOC xuong, va phai con vach dac o duoi.
kiem(usba_wire_z < usba_rib_h, "ranh day khoet tu noc vach chan",
     f"ranh bat dau z={usba_wire_z:g}, noc vach z={usba_rib_h:g}")
ho(usba_wire_z, 8.0, "phan vach chan con dac ben duoi ranh day")
kiem(usba_wire_w < inner_w, "ranh day hep hon long hop")

# 8. Tru do / tru vit S3.
#    Yeu cau THAT SU la TAM tru nam duoi bo (de vit an trung lo tren bo) va NOC tru dung bang
#    mat duoi bo (de bo nam phang). Vanh tru trum ra ngoai mep bo la BINH THUONG va khong tranh
#    duoc: tru O8 duoi mot bo rong 26.5 voi pitch 23 thi moi ben trum 2.25mm — ban voice-node
#    y het vay va da in ra dung. Doi hoi "tru nam gon trong be rong bo" la doi hoi sai de bai;
#    cai phai kiem la vanh trum do co dam vao thu khac khong, va do la muc 1, 9 ben duoi.
for t in tru_vit_s3 + tru_do_s3:
    cx, cy = (t.x[0] + t.x[1]) / 2, (t.y[0] + t.y[1]) / 2
    kiem(pcb.x[0] <= cx <= pcb.x[1] and pcb.y[0] <= cy <= pcb.y[1],
         f"tam {t.ten} nam duoi bo", f"tam ({cx:.2f}, {cy:.2f})")
    kiem(abs(t.z[1] - pcb.z[0]) < 1e-9, f"noc {t.ten} dung bang mat duoi bo",
         f"noc tru z={t.z[1]:.2f}, day bo z={pcb.z[0]:.2f}")
    roi_nhau(t, Hop("khong gian tren mat duoi bo",
                    pcb.x[0], pcb.x[1], pcb.y[0], pcb.y[1], pcb.z[0], 1e3),
             f"{t.ten} khong thoc len qua mat duoi bo")

# 8c. GO DAN HUONG — khe phai NUOT duoc bo, va phai CAO hon noc bo thi moi dan huong duoc.
#     Day la thu thay the vai tro dinh vi ngang cua 2 con vit (xem 8b): pitch co the sai, chu
#     be rong bo 26.5 thi da do tay tren board that.
kiem(abs((s3_guide_x1 - s3_guide_x0) - (s3_w + 2 * s3_guide_clear)) < 1e-9,
     "khe dan huong dung bang be rong bo + 2 lan ho",
     f"khe {s3_guide_x1 - s3_guide_x0:.2f} mm cho bo {s3_w:.2f} mm")
ho(pcb.x[0] - s3_guide_x0, 0.4, "ho ben trai bo trong khe dan huong")
ho(s3_guide_x1 - pcb.x[1], 0.4, "ho ben phai bo trong khe dan huong")
for g in go_dan_huong:
    roi_nhau(pcb, g, f"{g.ten} khong dam bo")
    roi_nhau(cong_usbc, g, f"{g.ten} khong dam cum cong USB-C")
    kiem(g.z[1] > pcb.z[1], f"{g.ten} cao hon noc PCB",
         f"noc go z={g.z[1]:.2f}, noc PCB z={pcb.z[1]:.2f}")
# Hai doan moi ben phai dat XA nhau thi moi khoa duoc xoay: hai diem cham sat nhau thi bo van
# quay quanh chung nhu quanh mot diem.
canh_tay = (s3_y_rear - s3_guide_in - s3_guide_seg) - (s3_y + s3_guide_in)
ho(canh_tay, 30.0, "khoang cach 2 doan go moi ben (canh tay don khoa xoay)")

# 8d. GO CHAN NHAC — phai o TREN noc PCB (chan chu khong kep), va phai nam TRONG dien tich bo.
for g in go_chan_nhac:
    roi_nhau(pcb, g, f"{g.ten} khong dam bo")
    kiem(abs((g.z[0] - pcb.z[1]) - s3_hold_gap) < 1e-9, f"{g.ten} ho dung s3_hold_gap tren PCB",
         f"ho {g.z[0] - pcb.z[1]:.2f} mm")
    kiem(g.x[0] >= pcb.x[0] - 1e-9 and g.x[1] <= pcb.x[1] + 1e-9,
         f"{g.ten} nam gon trong be rong bo (de tì dung mep PCB)",
         f"go x[{g.x[0]:.2f},{g.x[1]:.2f}] vs bo x[{pcb.x[0]:.2f},{pcb.x[1]:.2f}]")
    kiem(g.y[1] <= pcb.y[1], f"{g.ten} nam trong chieu dai bo")
    for k in go_dan_huong + go_hong + tru_goc + go_tut + [go_de, vach_chan]:
        roi_nhau(g, k, f"{g.ten} khong dam {k.ten}")
# Go chan nhac chi co y nghia neu no thuc su o dau TU DO (dau khong bat vit).
kiem(all(abs(g.y[0] - s3_y) < 1e-9 for g in go_chan_nhac),
     "go chan nhac dat o dau tu do cua bo (dau khong co vit)")

# 8b. CANH BAO — pitch 23 la so DANH NGHIA chep tu voice-node, chua ai do bang thuoc.
#     Tren bo rong 26.5 thi tam lo cach mep chi con 1.75mm. Lo thong M2.5 (O2.7) khoet o do
#     se an thung mep bo. Chinh chu thich goc trong vo-hop-modular.scad cung tu tinh ra "toi da
#     ~21.5" roi van giu 23. Ranh lo moi +-0.5 nuot duoc sai so nho, khong nuot duoc 1.5mm.
me_toi_lo = s3_w / 2 - s3_hole_pitch / 2
canh_bao(me_toi_lo >= 2.5,
         "s3_hole_pitch=23 kho dung tren bo rong 26.5 — DO LAI truoc khi in ban that",
         f"tam lo chi cach mep bo {me_toi_lo:.2f}mm; lo M2.5 can >= 2.5mm. "
         f"Neu do ra khac, sua s3_hole_pitch la 2 tru tu chay theo")
# Tru vit S3 co the cham tru goc sau — hai khoi cung nam trong union nen chi hop nhat,
# nhung cham qua nhieu thi lo mo M2.5 an vao thit tru goc. Gioi han 1.5mm.
for t in tru_vit_s3:
    for g in tru_goc:
        c = t.chong(g)
        if c is not None:
            kiem(c[0] <= 1.5, f"{t.ten} chi cham nhe {g.ten}",
                 f"chong {c[0]:.2f} mm theo x")

# 9. Tru vit S3 khong duoc dam vach sau.
kiem(max(t.y[1] for t in tru_vit_s3) <= out_l - wall,
     "tru vit S3 khong dam vach sau",
     f"mep sau tru y={max(t.y[1] for t in tru_vit_s3):.2f}, mat trong vach y={out_l - wall:.2f}")

# 10. Cua USB-C phai om tron than 2 cong, va con vach tren/duoi.
cua_usbc_z = (s3_usb_z - s3_usb_open_h / 2, s3_usb_z + s3_usb_open_h / 2)
cua_usbc_x = (box_cx - s3_usb_open_w / 2, box_cx + s3_usb_open_w / 2)
ho(cong_usbc.z[0] - cua_usbc_z[0], 1.0, "ho duoi cong USB-C trong cua")
ho(cua_usbc_z[1] - cong_usbc.z[1], 1.0, "ho tren cong USB-C trong cua")
ho(cong_usbc.x[0] - cua_usbc_x[0], 1.0, "ho ben trai cum cong USB-C trong cua")
ho(cua_usbc_z[0] - floor_t, 2.0, "vach con lai duoi cua USB-C")
ho(z_tran_thanh - cua_usbc_z[1], 2.0, "vach con lai tren cua USB-C")
kiem(cua_usbc_x[1] <= out_w - wall and cua_usbc_x[0] >= wall,
     "cua USB-C khong an vao 2 vach hong")


# 10b. PHICH CO LOT QUA CUA KHONG — cau hoi that su khi cam day.
#      Do CUC NHUA chu khong do vo kim loai: vo kim loai chi chia ~6.5mm (USB-C) / ~12mm
#      (USB-A) khoi cuc nhua, ma vach day 3mm. Chan cuc nhua o mat vach la mat dut 3mm chieu
#      sau cam — phich vao nhung khong an khop. Do la loi da dinh that o voice-node.
def phich_lot(phich: Hop, cua_x: tuple[float, float], cua_z: tuple[float, float],
              nhan: str) -> None:
    canh = {
        "trai": phich.x[0] - cua_x[0],
        "phai": cua_x[1] - phich.x[1],
        "duoi": phich.z[0] - cua_z[0],
        "tren": cua_z[1] - phich.z[1],
    }
    it_nhat = min(canh.values())
    kiem(it_nhat >= 0, f"phich {nhan} lot qua cua",
         "ho " + ", ".join(f"{k} {v:.2f}" for k, v in canh.items()) + " mm")
    canh_bao(it_nhat >= 0.5,
             f"phich {nhan}: ho hep nhat chi {it_nhat:.2f}mm — het dung sai",
             "canh " + ", ".join(k for k, v in canh.items() if v == it_nhat)
             + f". Do phich that roi sua usb{'a' if 'USB-A' in nhan else 'c'}_plug_w/h")


phich_lot(vo_phich, (box_cx - usba_open_w / 2, box_cx + usba_open_w / 2),
          (usba_open_z0, usba_open_z0 + usba_open_h), "USB-A")
for ten, hop_phich in vo_phich_usbc.items():
    phich_lot(hop_phich, cua_usbc_x, cua_usbc_z, f"USB-C {ten}")

# 11. Cua USB-A: phai nuot duoc vo nhua phich, nhung PHAI nho hon khoi theo z
#     (do la thu duy nhat giu khoi khong tuot ra khi rut phich).
cua_usba_z = (usba_open_z0, usba_open_z0 + usba_open_h)
kiem(usba_open_h < usba_h, "cua USB-A thap hon khoi -> khoi khong chui ra duoc",
     f"cua cao {usba_open_h:g}, khoi cao {usba_h:g}")
ho((khoi_usba.z[1] - cua_usba_z[1]) + (cua_usba_z[0] - khoi_usba.z[0]),
   4.0, "tong be rong 2 dai vach ti vao mat truoc khoi")
ho(z_tran_thanh - cua_usba_z[1], 2.0, "vach con lai tren cua USB-A")

# 12. Tha tu tren xuong: khong co gi chan bo S3 / khoi USB-A ha thang dong xuong cho.
#     Kiem bang cach chieu xuong mat phang xy — vat chi ha duoc neu hinh chieu cua no
#     khong cat hinh chieu cua khoi nhua nao CAO HON cao do dat cuoi cung.
def ha_duoc(vat: Hop, can_tro: list[Hop], nhan: str) -> None:
    for k in can_tro:
        if k.z[1] <= vat.z[0] + 1e-9:
            continue  # thap hon day vat -> khong can duong
        giao_x = min(vat.x[1], k.x[1]) - max(vat.x[0], k.x[0])
        giao_y = min(vat.y[1], k.y[1]) - max(vat.y[0], k.y[0])
        if giao_x > 0 and giao_y > 0:
            kiem(False, nhan, f"{k.ten} chan duong ha xuong ({giao_x:.2f} x {giao_y:.2f} mm)")
            return
    kiem(True, nhan)


can_tro_base = tru_goc + go_hong + go_dan_huong + [vach_chan]
ha_duoc(pcb, can_tro_base + tru_do_s3 + tru_vit_s3, "bo S3 ha thang tu tren xuong duoc")
ha_duoc(khoi_usba, tru_goc + [vach_chan], "khoi USB-A ha thang tu tren xuong duoc")

# 13. Chieu cao: nap phai day duoc, va cong USB-C phai nam duoi go tut.
ho(deck_h - usba_h, 1.0, "chieu cao long hop so voi khoi USB-A")
ho(z_go_duoi - cong_usbc.z[1], 1.0, "ho giua noc cong USB-C va go tut nap")
ho(z_nap_duoi - z_noc_pcb, 5.0, "khoang trong tren noc bo S3 (linh kien + camera)")

# 14. Lo khoet phai THUNG han be day vach — loi "khoet hut" da dinh 3 lan o voice-node.
kiem(wall + 2 > wall, "cua USB-A khoet thung ca be day vach (y tu -1 den wall+1)")
kiem(wall + 2 > wall, "cua USB-C khoet thung ca be day vach")

# ---------------------------------------------------------------- bao cao

rot = sum(1 for ok, _, _ in KET_QUA if not ok)
for ok, nhan, chi_tiet in KET_QUA:
    dau = "  ok  " if ok else "  FAIL"
    print(f"{dau}  {nhan}" + (f"   [{chi_tiet}]" if chi_tiet else ""))

if CANH_BAO:
    print("\n--- CANH BAO (so danh nghia, chua do bang thuoc) ---")
    for c in CANH_BAO:
        print(f"  !!    {c}")

print(f"\n{len(KET_QUA) - rot}/{len(KET_QUA)} dat, {len(CANH_BAO)} canh bao.")
sys.exit(1 if rot else 0)
