#!/usr/bin/env python3
"""So phân bố năng lượng theo dải tần giữa các nguồn mẫu ngáy.

Vì sao cần: mẫu phát qua loa điện thoại rồi thu lại bị mất dải <600Hz — đúng dải mang năng lượng
của tiếng ngáy — nên vô dụng cả cho train lẫn cho kiểm chứng bộ phát hiện theo dải tần. Script này
đo thẳng xem một nguồn mẫu có còn dải thấp hay không, TRƯỚC khi tốn công thu lại qua mic.

Chỉ số quyết định là cột <600Hz: nguồn ngáy thật phải có phần đáng kể năng lượng ở đó.

Cần soundfile để đọc mp3 (libsndfile >= 1.1):

    docker run --rm -v D:/snore-dataset:/ds -v D:/esp32-presence-ac:/repo \\
      tensorflow/tensorflow:latest sh -c \\
      "pip install -q soundfile && python /repo/scripts/so-sanh-pho-mau.py /ds/nguon-mau-freesound"
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

# Biên các dải để in. Cắt ở 600Hz vì đó là ranh giới loa điện thoại làm mất, và là cận trên của dải
# mà bộ phát hiện năng lượng (duong_bao_dai_tan.py) đang dùng.
BIEN_DAI_HZ = [20, 100, 300, 600, 1500, 4000, 20000]

DUOI_INS = ("*.wav", "*.mp3", "*.flac", "*.ogg")


def nang_luong_theo_dai(x, sample_rate):
    """Trả (phần trăm năng lượng mỗi dải, tần số trung vị tích luỹ)."""
    # Một FFT trên toàn tín hiệu là đủ: ta hỏi phân bố năng lượng TỔNG, không hỏi diễn biến theo
    # thời gian.
    pho = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    tan_so = np.fft.rfftfreq(len(x), d=1.0 / sample_rate)
    tong = pho.sum()
    if tong <= 0:
        return [0.0] * (len(BIEN_DAI_HZ) - 1), 0.0

    phan_tram = []
    for thap, cao in zip(BIEN_DAI_HZ[:-1], BIEN_DAI_HZ[1:]):
        trong = (tan_so >= thap) & (tan_so < cao)
        phan_tram.append(100.0 * float(pho[trong].sum()) / float(tong))

    # Tần số mà dưới nó chứa nửa năng lượng — một con số tóm tắt "tín hiệu nặng ở đâu".
    tich_luy = np.cumsum(pho) / tong
    trung_vi = float(tan_so[int(np.searchsorted(tich_luy, 0.5))])
    return phan_tram, trung_vi


def liet_ke(muc_tieu):
    p = Path(muc_tieu)
    if p.is_file():
        return [p]
    ra = []
    for d in DUOI_INS:
        ra.extend(p.glob(d))
    return sorted(ra)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("muc_tieu", nargs="+", help="file audio hoặc thư mục")
    ap.add_argument("--gioi-han-s", type=float, default=30.0,
                    help="chỉ phân tích N giây đầu mỗi file (mặc định 30)")
    args = ap.parse_args()

    nhan_dai = [f"{t}-{c}" for t, c in zip(BIEN_DAI_HZ[:-1], BIEN_DAI_HZ[1:])]
    print(f"{'file':38s} {'sr':>6s} {'giây':>5s} " +
          " ".join(f"{n:>9s}" for n in nhan_dai) + f" {'<600Hz':>7s} {'f50%':>6s}")

    for muc_tieu in args.muc_tieu:
        for p in liet_ke(muc_tieu):
            try:
                x, sr = sf.read(str(p), always_2d=True)
            except Exception as e:  # định dạng lạ thì báo rồi đi tiếp, đừng chết cả lượt chạy
                print(f"{p.name:38s} LỖI: {e}")
                continue
            x = x.mean(axis=1)[: int(args.gioi_han_s * sr)]
            if len(x) < sr:
                print(f"{p.name:38s} (ngắn hơn 1 giây)")
                continue
            phan_tram, f50 = nang_luong_theo_dai(x, sr)
            duoi_600 = sum(pt for pt, thap in zip(phan_tram, BIEN_DAI_HZ[:-1]) if thap < 600)
            print(f"{p.name:38s} {sr:6d} {len(x) / sr:5.1f} " +
                  " ".join(f"{pt:8.1f}%" for pt in phan_tram) +
                  f" {duoi_600:6.1f}% {f50:6.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
