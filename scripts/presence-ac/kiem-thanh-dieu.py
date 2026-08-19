#!/usr/bin/env python3
"""Cổng kiểm thanh điệu: giữ clip đọc "vừng" (thanh huyền, xuống), loại clip đọc "vâng" (ngang).

    # chấm một tập
    python3 scripts/kiem-thanh-dieu.py datasets/generated_samples --json ket-qua.json

    # chuẩn hoá lại ngưỡng khi đổi nguồn mẫu
    python3 scripts/kiem-thanh-dieu.py --chuan-hoa datasets/real_samples datasets/generated_samples

Đo bằng ĐƯỜNG F0 của âm tiết đầu, KHÔNG dùng mô hình ngôn ngữ.

Vì sao không dùng whisper — đã đo 09/08 và loại: whisper (`small` lẫn `medium`) loại **100%**
mẫu giọng thật của user, thứ chắc chắn đọc đúng "vừng ơi". Lý do không phải kích cỡ model:
"vâng" là một trong những từ phổ biến nhất tiếng Việt, "vừng ơi" gần như không có trong văn bản,
mà clip 1,5 s cô lập thì không có ngữ cảnh để kéo ngược. Prior ngôn ngữ đè bẹp bằng chứng âm học.
Số liệu đầy đủ:
plans/reports/phase-01-chuan-hoa-cong-tone-260809-0839-whisper-san-100-phan-tram-f0-thay-the-report.md

Vì sao F0 chạy được: thanh huyền là thanh XUỐNG THẤP, thanh ngang là thanh BẰNG. Khác biệt nằm
thẳng trong đường cao độ. Đo dốc F0 rồi quy ra bán cung so với trung vị của chính clip ⇒ bỏ được
khác biệt cao độ giọng nam/nữ, chỉ còn lại hình dạng đường tiếng.

Ngưỡng KHÔNG hardcode theo cảm tính — chạy `--chuan-hoa` với một tập biết-tốt và một tập biết-xấu,
script quét ngưỡng và chọn điểm tách tốt nhất. Đổi nguồn mẫu thì chuẩn hoá lại.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

SR = 16000
DUOI_AUDIO = {".wav", ".mp3", ".flac", ".ogg", ".m4a"}

# Chuẩn hoá 09/08 trên 190 mẫu giọng thật (biết-tốt, n đo được 189) vs 1000 mẫu TTS Anh
# (biết-xấu, n đo được 999). Điểm tách tốt nhất theo J = giữ_tốt − lọt_xấu:
#
#   ngưỡng -1,00 st  ->  giữ 84,1% mẫu tốt · lọt 38,8% mẫu xấu · J = +0,453
#   trung vị biết-tốt -2,09 st   ·   trung vị biết-xấu -0,33 st
#
# ⇒ SÀN LOẠI-OAN 15,9% — dưới mốc 30% của phase-01 nên cổng DÙNG ĐƯỢC.
# ⚠️ Nhưng lọt 38,8% mẫu xấu: cổng bắt được thằng tệ nhất, KHÔNG bảo đảm tập dương sạch.
#    Một phần trong 38,8% đó có thể là clip Piper tình cờ có đường xuống thật — không tách
#    được nếu không nghe tay. Đọc con số này là "chặn trên của tỷ lệ sai", không phải "tỷ lệ sai".
#
# Chạy lại `--chuan-hoa` nếu đổi nguồn mẫu — đừng sửa tay số này.
NGUONG_MAC_DINH = -1.0  # bán cung; dốc ÂM hơn ngưỡng = đi xuống = thanh huyền


def _tach_am_tiet_dau(y: np.ndarray) -> np.ndarray:
    """Cắt lấy âm tiết đầu của cụm 2 âm tiết ("vừng" trong "vừng ơi").

    Tìm thung lũng năng lượng ở khoảng giữa clip — chỗ nối hai âm tiết. Không thấy thung lũng
    rõ (hai âm tiết dính liền) thì lùi về mốc 45%, đủ dùng vì hai âm tiết gần đều nhau.
    """
    import librosa

    rms = librosa.feature.rms(y=y, frame_length=512, hop_length=128)[0]
    if len(rms) < 8:
        return y[: int(len(y) * 0.45)]

    # Chỉ tìm trong dải 30-70% — ngoài dải đó là đầu/cuối clip, không phải chỗ nối.
    lo, hi = int(len(rms) * 0.30), int(len(rms) * 0.70)
    day = lo + int(np.argmin(rms[lo:hi])) if hi > lo else int(len(rms) * 0.45)

    # Thung lũng phải đủ sâu mới tin là chỗ nối thật.
    if rms[day] < 0.6 * np.median(rms[lo:hi]):
        cat = int(day * 128)
    else:
        cat = int(len(y) * 0.45)
    return y[:cat] if cat > int(0.08 * SR) else y[: int(len(y) * 0.45)]


def do_doc_f0(path: Path) -> dict | None:
    """Trả về dốc F0 của âm tiết đầu, đơn vị bán cung. ÂM = đi xuống = thanh huyền."""
    import librosa

    y, _ = librosa.load(str(path), sr=SR, mono=True)
    y, _ = librosa.effects.trim(y, top_db=30)
    if len(y) < int(0.15 * SR):
        return None

    dau = _tach_am_tiet_dau(y)
    f0, voiced, _ = librosa.pyin(dau, fmin=70, fmax=400, sr=SR, frame_length=1024, hop_length=128)
    f0v = f0[voiced & ~np.isnan(f0)]
    if len(f0v) < 6:
        return None  # quá ít khung hữu thanh — không kết luận được

    st = 12 * np.log2(f0v / np.median(f0v))
    doc = float(np.polyfit(np.arange(len(st)), st, 1)[0] * len(st))
    return {
        "file": path.name,
        "doc_semitone": doc,
        "f0_median": float(np.median(f0v)),
        "bien_do_st": float(st.max() - st.min()),
        "n_frame": int(len(f0v)),
    }


def gom_file(duong_dan: list[str]) -> list[Path]:
    ket_qua: list[Path] = []
    for d in duong_dan:
        p = Path(d)
        if p.is_dir():
            ket_qua += sorted(f for f in p.rglob("*") if f.suffix.lower() in DUOI_AUDIO)
        elif p.is_file():
            ket_qua.append(p)
        else:
            print(f"LỖI: không thấy {p}", file=sys.stderr)
    return ket_qua


def do_ca_tap(files: list[Path], nhan: str = "") -> list[dict]:
    kq = []
    for i, f in enumerate(files, 1):
        r = do_doc_f0(f)
        if r:
            kq.append(r)
        if i % 100 == 0:
            print(f"  … {nhan}{i}/{len(files)}", file=sys.stderr)
    return kq


def chuan_hoa(dir_tot: str, dir_xau: str, gioi_han: int | None) -> int:
    """Quét ngưỡng trên một tập biết-tốt và một tập biết-xấu, chọn điểm tách tốt nhất.

    Chỉ có tập biết-tốt thì không đủ: một cổng loại sạch mọi thứ vẫn cho sàn "đẹp" ở tập xấu.
    Phải có cả hai vế mới biết cổng có PHÂN BIỆT hay không.
    """
    ftot, fxau = gom_file([dir_tot]), gom_file([dir_xau])
    if gioi_han:
        ftot, fxau = ftot[:gioi_han], fxau[:gioi_han]
    print(f"biết-tốt {len(ftot)} file · biết-xấu {len(fxau)} file", file=sys.stderr)

    tot = np.array([r["doc_semitone"] for r in do_ca_tap(ftot, "tốt ")])
    xau = np.array([r["doc_semitone"] for r in do_ca_tap(fxau, "xấu ")])
    if not len(tot) or not len(xau):
        print("LỖI: một trong hai tập không đo được clip nào", file=sys.stderr)
        return 1

    print(f"\nbiết-tốt: n={len(tot)} trung vị {np.median(tot):+.2f} st")
    print(f"biết-xấu: n={len(xau)} trung vị {np.median(xau):+.2f} st\n")
    print(f"{'ngưỡng':>8} {'giữ mẫu tốt':>12} {'lọt mẫu xấu':>12} {'J':>7}")

    tot_nhat, j_nhat = None, -9
    for ng in np.arange(-5.0, 1.01, 0.25):
        recall = float((tot < ng).mean())
        lot = float((xau < ng).mean())
        j = recall - lot
        print(f"{ng:>8.2f} {recall:>11.1%} {lot:>11.1%} {j:>+7.3f}")
        if j > j_nhat:
            j_nhat, tot_nhat = j, (float(ng), recall, lot)

    ng, recall, lot = tot_nhat
    print(f"\n=== NGƯỠNG TỐT NHẤT: {ng:+.2f} st ===")
    print(f"  giữ được {recall:.1%} mẫu tốt · lọt {lot:.1%} mẫu xấu · J = {j_nhat:+.3f}")
    print(f"  ⇒ SÀN LOẠI-OAN = {1 - recall:.1%}")
    if j_nhat < 0.3:
        print("\n⚠️  J < 0,3 — cổng phân biệt YẾU. Đừng tin nó để lọc hàng loạt.")
    print(f"\nĐặt NGUONG_MAC_DINH = {ng:.2f} trong script nếu muốn chốt ngưỡng này.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("duong_dan", nargs="*", help="file audio hoặc thư mục")
    ap.add_argument(
        "--chuan-hoa",
        nargs=2,
        metavar=("THU_MUC_TOT", "THU_MUC_XAU"),
        help="quét ngưỡng trên tập biết-tốt và tập biết-xấu rồi thoát",
    )
    ap.add_argument("--nguong", type=float, default=NGUONG_MAC_DINH, help="dốc bán cung tối đa để qua cổng")
    ap.add_argument("--json", type=Path, help="ghi kết quả từng file ra JSON")
    ap.add_argument("--gioi-han", type=int, help="chỉ chấm N file đầu")
    ap.add_argument("--im-lang", action="store_true", help="chỉ in tổng kết")
    args = ap.parse_args()

    if args.chuan_hoa:
        return chuan_hoa(*args.chuan_hoa, args.gioi_han)

    files = gom_file(args.duong_dan)
    if args.gioi_han:
        files = files[: args.gioi_han]
    if not files:
        print("Không có file audio nào để chấm.", file=sys.stderr)
        return 1

    do_duoc, khong_do_duoc = [], []
    for i, f in enumerate(files, 1):
        r = do_doc_f0(f)
        if r is None:
            khong_do_duoc.append(f.name)
            if not args.im_lang:
                print(f"⚠️  [{i}/{len(files)}] {f.name} — không đủ khung hữu thanh, BỎ")
            continue
        r["qua"] = r["doc_semitone"] < args.nguong
        do_duoc.append(r)
        if not args.im_lang:
            print(
                f'{"✅" if r["qua"] else "❌"} [{i}/{len(files)}] {r["file"]} '
                f'— dốc {r["doc_semitone"]:+.2f} st'
            )
        elif i % 100 == 0:
            print(f"  … {i}/{len(files)}", file=sys.stderr)

    qua = sum(1 for r in do_duoc if r["qua"])
    tong = len(do_duoc)
    print(f"\n=== TỔNG KẾT (ngưỡng {args.nguong:+.2f} st) ===")
    print(f"  đo được {tong}/{len(files)} · qua {qua} ({qua / tong:.1%})" if tong else "  không đo được clip nào")
    if khong_do_duoc:
        print(f"  bỏ vì không đủ khung hữu thanh: {len(khong_do_duoc)}")

    if args.json:
        args.json.write_text(
            json.dumps(
                {
                    "nguong": args.nguong,
                    "tong_file": len(files),
                    "do_duoc": tong,
                    "qua": qua,
                    "ty_le_qua": qua / tong if tong else 0.0,
                    "khong_do_duoc": khong_do_duoc,
                    "chi_tiet": do_duoc,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"\nĐã ghi {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
