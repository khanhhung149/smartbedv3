#!/usr/bin/env python3
"""Sinh tập mẫu ngáy có nhãn bằng cách trộn ngáy thật với nhiễu nền phòng đã thu.

Vì sao cần: model snore hiện train trên Khan 2019 (ngáy thu gần, phòng thu sạch) nên vỡ trên audio
phòng ngủ thật — đo 17/08 thấy chuỗi score có tự tương quan trễ-1 chỉ 0,16-0,65 dù hai cửa sổ liền
kề chồng nhau 75%, tức là gần như nhiễu. Thứ model chưa từng thấy là tiếng ngáy LẪN TRONG nhiễu nền
phòng ngủ, ở mức tín hiệu của mic đặt cách giường 30-40cm.

Cách này KHÔNG cần loa và KHÔNG cần ai ngáy: ngáy thật lấy từ nguồn CC0/CC-BY (xem
/mnt/d/snore-dataset/nguon-mau-freesound/), nhiễu nền lấy từ chính các đoạn thu phòng yên của
voice-node. Đây là thứ rẻ nhất có thể làm ngay.

Giới hạn phải biết: không mô phỏng được phản xạ phòng và hướng nguồn âm. Mẫu sinh ra là "ngáy sạch
cộng nhiễu", khác "ngáy thu trong phòng". Dùng để train và để dò tham số thì tốt; để NGHIỆM THU thì
vẫn cần mẫu thu thật qua mic.

Chạy:

    docker run --rm -v D:/snore-dataset:/ds -v D:/esp32-presence-ac:/repo \\
      tensorflow/tensorflow:latest sh -c \\
      "pip install -q soundfile && python /repo/scripts/sinh-mau-augmentation.py \\
         --ngay /ds/nguon-mau-freesound --nhieu /ds/quiet --ra /ds/augment"
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

SAMPLE_RATE = 16000
DAI_DOAN_S = 60.0

# Các mức SNR sinh ra. Trải rộng có chủ đích: ngáy to sát mic lẫn ngáy nhỏ ở cuối giường đều phải
# có trong tập, nếu không model chỉ học được một mức âm lượng.
SNR_DB = (0, 5, 10, 15, 20)

# Lọc bỏ dưới ngưỡng này ở nguồn ngáy. Mẫu fudgealtoid có 60% năng lượng ở 20-100Hz — nghi ù nền
# hoặc rung chạm mic, không phải tiếng ngáy. Mic INMP441 cũng không đáp ứng tốt vùng đó.
CAT_HA_TAN_HZ = 80.0


def doc_mono_16k(path):
    """Đọc file audio bất kỳ về mono 16kHz float64, chuẩn hoá biên độ về [-1,1]."""
    x, sr = sf.read(str(path), always_2d=True)
    x = x.mean(axis=1)
    if sr != SAMPLE_RATE:
        # Lấy mẫu lại bằng nội suy tuyến tính trên lưới thời gian mới. Đủ dùng ở đây: nguồn là
        # 44,1/48kHz xuống 16kHz và ta đã cắt hạ tần, còn nội dung trên 8kHz thì tiếng ngáy vốn
        # không có gì đáng kể (đo được: >4kHz chỉ chiếm 0,1-1,3% năng lượng).
        t_cu = np.arange(len(x)) / sr
        t_moi = np.arange(0, t_cu[-1], 1.0 / SAMPLE_RATE)
        x = np.interp(t_moi, t_cu, x)
    dinh = np.max(np.abs(x))
    return x / dinh if dinh > 0 else x


def cat_ha_tan(x, f_cat=CAT_HA_TAN_HZ):
    """Cắt dưới f_cat bằng FFT. Xoá ù nền/rumble mà mic INMP441 cũng không thu được."""
    pho = np.fft.rfft(x)
    tan_so = np.fft.rfftfreq(len(x), d=1.0 / SAMPLE_RATE)
    pho[tan_so < f_cat] = 0
    return np.fft.irfft(pho, n=len(x))


def cong_theo_snr(tin_hieu, nhieu, snr_db):
    """Trộn sao cho tỉ số công suất tín hiệu/nhiễu đúng bằng snr_db."""
    p_tin = float(np.mean(tin_hieu ** 2))
    p_nhieu = float(np.mean(nhieu ** 2))
    if p_tin <= 0 or p_nhieu <= 0:
        return tin_hieu + nhieu
    # Chỉnh biên độ tín hiệu chứ không chỉnh nhiễu: nhiễu nền là mức thật của căn phòng, giữ nguyên
    # nó thì mẫu sinh ra vẫn đúng mức nền mà board sẽ gặp.
    he_so = np.sqrt(p_nhieu * (10 ** (snr_db / 10.0)) / p_tin)
    return tin_hieu * he_so + nhieu


def ghi_wav(path, x):
    """Ghi PCM16 16kHz — đúng định dạng voice-node thu, để chấm bằng cùng bộ script."""
    dinh = np.max(np.abs(x))
    if dinh > 1.0:            # chống clip sau khi trộn
        x = x / dinh
    sf.write(str(path), (x * 32767).astype(np.int16), SAMPLE_RATE, subtype="PCM_16")


def lay_doan(x, dai_mau, rng):
    """Cắt một đoạn dài dai_mau; lặp lại tín hiệu nếu nguồn ngắn hơn."""
    if len(x) < dai_mau:
        x = np.tile(x, int(np.ceil(dai_mau / len(x))))
    dau = rng.integers(0, len(x) - dai_mau + 1)
    return x[dau:dau + dai_mau]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ngay", required=True, help="thư mục chứa nguồn ngáy sạch")
    ap.add_argument("--nhieu", required=True, help="thư mục chứa nhiễu nền phòng đã thu")
    ap.add_argument("--ra", required=True, help="thư mục xuất")
    ap.add_argument("--so-mau", type=int, default=5, help="số mẫu mỗi (nguồn ngáy x SNR)")
    ap.add_argument("--seed", type=int, default=1, help="seed để sinh lại được đúng tập cũ")
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    dai_mau = int(DAI_DOAN_S * SAMPLE_RATE)

    nguon_ngay = sorted(p for d in ("*.mp3", "*.wav", "*.flac")
                        for p in Path(args.ngay).glob(d))
    nguon_nhieu = sorted(Path(args.nhieu).glob("*.wav"))
    if not nguon_ngay or not nguon_nhieu:
        print(f"thiếu nguồn: ngáy={len(nguon_ngay)} nhiễu={len(nguon_nhieu)}", file=sys.stderr)
        return 1

    ra_ngay = Path(args.ra) / "ngay"
    ra_khong = Path(args.ra) / "khong-ngay"
    ra_ngay.mkdir(parents=True, exist_ok=True)
    ra_khong.mkdir(parents=True, exist_ok=True)

    nhieu = [doc_mono_16k(p) for p in nguon_nhieu]
    print(f"nguồn ngáy: {len(nguon_ngay)} | nhiễu nền: {len(nhieu)}")

    dem = 0
    for p in nguon_ngay:
        ngay = cat_ha_tan(doc_mono_16k(p))
        for snr in SNR_DB:
            for i in range(args.so_mau):
                n = lay_doan(nhieu[rng.integers(0, len(nhieu))], dai_mau, rng)
                s = lay_doan(ngay, dai_mau, rng)
                ghi_wav(ra_ngay / f"{p.stem}-snr{snr:02d}-{i:03d}.wav", cong_theo_snr(s, n, snr))
                dem += 1

    # Mẫu ÂM TÍNH lấy thẳng từ nhiễu nền, qua đúng đường ghi file như mẫu dương tính. Quan trọng:
    # nếu hai lớp đi qua hai đường xử lý khác nhau thì model học được sự khác nhau đó thay vì học
    # tiếng ngáy.
    for j, p in enumerate(nguon_nhieu):
        for i in range(args.so_mau):
            n = lay_doan(nhieu[j], dai_mau, rng)
            ghi_wav(ra_khong / f"{p.stem}-{i:03d}.wav", n)
            dem += 1

    print(f"đã sinh {dem} mẫu 60s vào {args.ra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
