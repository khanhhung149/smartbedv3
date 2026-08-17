#!/usr/bin/env python3
"""Đẩy các đoạn CÓ TIẾNG NÓI trong bản ghi voice-node qua service ASR, in text trả về.

Vì sao cần: parser lệnh (backend/internal/voice/command.go) chỉ so khớp chuỗi, nên nó bất lực nếu
ASR nghe sai chữ. Trước khi thêm lệnh mới thì phải biết ASR THỰC SỰ trả về gì cho câu đó, đo trên
đúng mic INMP441 và đúng vị trí đặt board — chứ không phải đoán.

Cắt theo năng lượng thay vì đẩy nguyên file 60s: đường chạy thật gom từng utterance rồi mới gọi
ASR (xem voice/stream.go), đẩy cả phút im lặng vào sẽ đo một thứ khác với thứ đang chạy.

Chạy trong mạng compose vì service ASR không expose ra host:

    docker run --rm --network backend_default \\
      -v backend_voice-records:/data -v D:/esp32-presence-ac:/repo \\
      tensorflow/tensorflow:latest python /repo/scripts/thu-asr-tren-ban-ghi.py /data/<file>.wav
"""

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from asr_client import ASR_URL, goi_asr, wav_bytes  # noqa: E402
from wav_io import SAMPLE_RATE, doc_wav, liet_ke_wav  # noqa: E402

# Khung đo năng lượng để dò tiếng nói.
KHUNG_S = 0.032

# Ngưỡng = nền + NGUONG_TREN_NEN_DB. Tương đối so với nền của chính đoạn ghi, vì mức nhiễu mỗi
# buổi mỗi khác (đo được 17/08: cùng phòng nhưng biên độ chênh nhau hàng chục dB giữa các buổi).
NGUONG_TREN_NEN_DB = 12.0

# Nối các khung có tiếng cách nhau dưới mức này thành một utterance — khoảng lặng giữa các từ
# trong một câu thường ngắn hơn nhiều so với khoảng lặng giữa hai câu.
NOI_KHOANG_LANG_S = 0.5

# Bỏ đoạn quá ngắn (tiếng động) hoặc quá dài (nguồn ồn liên tục, không phải câu nói).
DOAN_MIN_S, DOAN_MAX_S = 0.5, 12.0

# Đệm hai đầu để không cắt cụt phụ âm đầu/cuối — mất chúng là ASR nghe sai hẳn từ.
DEM_S = 0.3


def tim_doan_noi(pcm, nguong_tren_nen_db=NGUONG_TREN_NEN_DB):
    """Trả danh sách (mẫu_đầu, mẫu_cuối) của các đoạn nghi có tiếng nói."""
    n = int(KHUNG_S * SAMPLE_RATE)
    x = np.asarray(pcm, dtype=np.float64)
    so_khung = len(x) // n
    if so_khung == 0:
        return []

    khung = x[: so_khung * n].reshape(so_khung, n)
    db = 10 * np.log10((khung ** 2).mean(axis=1) + 1.0)
    nguong = np.median(db) + nguong_tren_nen_db

    co_tieng = db > nguong
    doan, dau = [], None
    khoang_lang_toi_da = int(NOI_KHOANG_LANG_S / KHUNG_S)
    lang = 0
    for i, c in enumerate(co_tieng):
        if c:
            if dau is None:
                dau = i
            lang = 0
        elif dau is not None:
            lang += 1
            if lang > khoang_lang_toi_da:
                doan.append((dau, i - lang))
                dau = None
    if dau is not None:
        doan.append((dau, len(co_tieng)))

    dem = int(DEM_S * SAMPLE_RATE)
    ra = []
    for d, c in doan:
        dai_s = (c - d) * KHUNG_S
        if DOAN_MIN_S <= dai_s <= DOAN_MAX_S:
            ra.append((max(0, d * n - dem), min(len(x), c * n + dem)))
    return ra


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("muc_tieu", nargs="+", help="file WAV hoặc thư mục")
    ap.add_argument("--url", default=ASR_URL)
    ap.add_argument("--nguong-db", type=float, default=NGUONG_TREN_NEN_DB,
                    help=f"ngưỡng dò tiếng nói, tính bằng dB TRÊN NỀN (mặc định {NGUONG_TREN_NEN_DB})")
    args = ap.parse_args()

    for muc_tieu in args.muc_tieu:
        for p in liet_ke_wav(muc_tieu):
            pcm = doc_wav(p)
            doan = tim_doan_noi(pcm, args.nguong_db)
            print(f"\n=== {p.name}: {len(doan)} đoạn nghi có tiếng nói ===")
            for dau, cuoi in doan:
                try:
                    kq = goi_asr(wav_bytes(pcm[dau:cuoi]), args.url)
                    text = kq.get("text", "")
                except Exception as e:
                    text = f"<LỖI: {e}>"
                print(f"  [{dau / SAMPLE_RATE:6.1f}s -{(cuoi - dau) / SAMPLE_RATE:5.1f}s] {text!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
