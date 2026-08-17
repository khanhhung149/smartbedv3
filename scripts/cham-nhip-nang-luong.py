#!/usr/bin/env python3
"""Chấm nhịp ngáy TRÊN ĐƯỜNG BAO NĂNG LƯỢNG dải tần, không dùng model.

Vì sao có đường này song song với cham-diem-snore-offline.py: đo 17/08 chứng minh chuỗi score của
snore.tflite trên audio phòng thật là nhiễu (ac1 0,16-0,65) trong khi đường bao năng lượng của
chính đoạn audio đó trơn (ac1 0,77-0,89). Chấm nhịp cần một chuỗi trơn để bám; năng lượng có sẵn
tính chất đó mà không cần model nào.

Chỉ cần numpy, không cần TensorFlow.

Chạy:

    docker run --rm -v backend_voice-records:/data -v D:/esp32-presence-ac:/repo \\
      tensorflow/tensorflow:latest python /repo/scripts/cham-nhip-nang-luong.py /data

So sánh nhiều dải tần để chọn dải tách lớp tốt nhất:

    ... /repo/scripts/cham-nhip-nang-luong.py /data --dai 100-600 --dai 20-8000
"""

import argparse
import statistics
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from duong_bao_dai_tan import DAI_CAO_HZ, DAI_THAP_HZ, duong_bao_db  # noqa: E402
from snore_nhip import phan_tich_nhip  # noqa: E402
from wav_io import SAMPLE_RATE, doc_wav, liet_ke_wav  # noqa: E402

# Ngưỡng bắt đỉnh tối thiểu tính bằng dB. Đường bao ở thang dB nên delta là HIỆU mức, không phải
# tỉ lệ: 3dB = năng lượng gấp đôi, mức chênh nhỏ nhất còn đáng gọi là một đợt chứ không phải gợn nền.
DELTA_DB_TOI_THIEU = 3.0


def tu_tuong_quan_tre_1(xs):
    """Đo độ trơn của chuỗi. Dùng để đối chiếu trực tiếp với ac1 của chuỗi score model."""
    x = np.asarray(xs, dtype=np.float64)
    x = x - x.mean()
    mau = float((x * x).sum())
    return float((x[:-1] * x[1:]).sum() / mau) if mau > 0 else float("nan")


def phan_tich_file(path, f_thap, f_cao):
    bao, chu_ky = duong_bao_db(doc_wav(path), SAMPLE_RATE, f_thap, f_cao)
    if not bao:
        return None
    kq = phan_tich_nhip(bao, chu_ky, delta_toi_thieu=DELTA_DB_TOI_THIEU)
    kq["ac1"] = round(tu_tuong_quan_tre_1(bao), 3)
    kq["bien_do_db"] = round(max(bao) - min(bao), 1)
    return kq


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("muc_tieu", nargs="+", help="file WAV hoặc thư mục chứa WAV")
    ap.add_argument("--dai", action="append", default=None,
                    help=f"dải tần dạng THAP-CAO tính bằng Hz (mặc định "
                         f"{DAI_THAP_HZ:.0f}-{DAI_CAO_HZ:.0f}); lặp lại cờ này để so nhiều dải")
    args = ap.parse_args()

    dai = [tuple(float(v) for v in d.split("-")) for d in (args.dai or
                                                           [f"{DAI_THAP_HZ:.0f}-{DAI_CAO_HZ:.0f}"])]

    for f_thap, f_cao in dai:
        print(f"\n=== dải {f_thap:.0f}-{f_cao:.0f} Hz ===")
        print(f"{'':4s} {'file':44s} {'đợt':>4s} {'khoảng':>7s} {'CV':>6s} {'ac1':>6s} {'biên độ':>8s}")
        ac1_gop = []
        for muc_tieu in args.muc_tieu:
            for p in liet_ke_wav(muc_tieu):
                kq = phan_tich_file(p, f_thap, f_cao)
                if kq is None:
                    print(f"     {p.name:44s} (quá ngắn)")
                    continue
                ac1_gop.append(kq["ac1"])
                print(f"{'NGÁY' if kq['la_ngay'] else '-':4s} {p.name:44s} "
                      f"{kq['so_dot']:4d} {str(kq['khoang_trung_vi_s']):>7s} "
                      f"{str(kq['cv']):>6s} {kq['ac1']:6.3f} {kq['bien_do_db']:7.1f}dB "
                      f"{kq['ly_do']}")
        if ac1_gop:
            print(f"     ac1 trung vị = {statistics.median(ac1_gop):.3f} "
                  f"(score model đo được 0,16-0,65)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
