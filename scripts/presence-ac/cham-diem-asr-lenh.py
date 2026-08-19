#!/usr/bin/env python3
"""Chấm độ chính xác ASR trên bộ mẫu lệnh giọng nói có nhãn.

Nhãn lấy từ TIỀN TỐ tên file, khớp với Kind mà parser trả về:

    on-*.wav    -> "bật điều hoà"        (kind=on)
    off-*.wav   -> "tắt điều hoà"        (kind=off)
    up-*.wav    -> "tăng nhiệt độ"       (kind=temp_up)
    down-*.wav  -> "giảm nhiệt độ"       (kind=temp_down)

Vì sao KHÔNG tự parse trong Python: asr/score_samples.py từng giữ một bản sao thủ công của
ParseVietCommand, và nó lệch ngay lần đầu bản Go đổi (thêm lệnh nhiệt độ, 17/08) — điểm đo khi đó
phản ánh một parser không ai đang chạy. Script này gọi THẲNG bản Go qua backend/bin/parse-cmd.

Vì sao gọi service ASR qua HTTP thay vì tự nạp model: đo đúng thứ đang chạy thật, gồm cả engine
đang cấu hình (sherpa hay whisper) và mọi tham số của nó. Tự nạp model là đo một cấu hình song song.

Chuẩn bị:

    cd backend && CGO_ENABLED=0 go build -o bin/parse-cmd ./cmd/parse-cmd

Chạy:

    docker run --rm --network backend_default \\
      -v D:/snore-dataset:/ds -v D:/esp32-presence-ac:/repo \\
      tensorflow/tensorflow:latest python /repo/scripts/cham-diem-asr-lenh.py /ds/mau-lenh
"""

import argparse
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asr_client import ASR_URL_KHONG_DUMP, goi_asr, wav_bytes  # noqa: E402
from wav_io import doc_wav, liet_ke_wav  # noqa: E402

PARSE_CMD = "/repo/backend/bin/parse-cmd"

# Tiền tố -> Kind mà parser phải trả về.
NHAN = {"on": "on", "off": "off", "up": "temp_up", "down": "temp_down"}


def nhan_tu_ten(path):
    tien_to = path.name.split("-", 1)[0].lower()
    return NHAN.get(tien_to)


def parse_hang_loat(texts, parse_cmd):
    """Đẩy toàn bộ text qua CLI Go một lần, tránh trả phí khởi động tiến trình cho từng câu."""
    if not texts:
        return []
    # Thay newline trong text bằng khoảng trắng: CLI đọc mỗi dòng một câu, một text nhiều dòng sẽ
    # làm lệch hàng kết quả so với hàng đầu vào.
    data = "\n".join(t.replace("\n", " ") for t in texts) + "\n"
    r = subprocess.run([parse_cmd], input=data, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"{parse_cmd} lỗi: {r.stderr.strip()}")
    return [json.loads(line) for line in r.stdout.splitlines() if line.strip()]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("muc_tieu", nargs="+", help="thư mục chứa WAV đã đặt tiền tố nhãn")
    ap.add_argument("--url", default=ASR_URL_KHONG_DUMP)
    ap.add_argument("--parse-cmd", default=PARSE_CMD)
    args = ap.parse_args()

    mau = []
    for m in args.muc_tieu:
        for p in liet_ke_wav(m):
            nhan = nhan_tu_ten(p)
            if nhan is None:
                print(f"BỎ QUA {p.name}: tiền tố không nằm trong {sorted(NHAN)}", file=sys.stderr)
                continue
            mau.append((p, nhan))

    if not mau:
        print("không có mẫu nào có nhãn hợp lệ", file=sys.stderr)
        return 1

    texts = []
    for p, _ in mau:
        try:
            texts.append(goi_asr(wav_bytes(doc_wav(p)), args.url).get("text", ""))
        except Exception as e:
            texts.append(f"<LỖI ASR: {e}>")

    ket = parse_hang_loat(texts, args.parse_cmd)

    dung = 0
    sai = []
    theo_nhan = Counter()
    dung_theo_nhan = Counter()
    for (p, nhan), text, kq in zip(mau, texts, ket):
        theo_nhan[nhan] += 1
        if kq["ok"] and kq["kind"] == nhan:
            dung += 1
            dung_theo_nhan[nhan] += 1
        else:
            sai.append((p.name, nhan, text, kq["kind"] if kq["ok"] else "(không khớp)"))

    n = len(mau)
    print(f"\n=== {dung}/{n} khớp lệnh đúng ({100 * dung / n:.0f}%) ===\n")
    print(f"{'nhãn':10s} {'đúng':>6s} {'tổng':>6s}")
    for nhan in sorted(theo_nhan):
        print(f"{nhan:10s} {dung_theo_nhan[nhan]:6d} {theo_nhan[nhan]:6d}")

    if sai:
        # In text ASR trả về cho từng câu sai — đây là chỗ phân biệt "ASR nghe sai chữ" với "audio
        # thiếu chữ" với "parser không khớp", ba loại lỗi cần ba cách sửa khác nhau.
        print(f"\n--- {len(sai)} câu sai ---")
        for ten, nhan, text, ra in sai:
            print(f"  {ten:34s} muốn={nhan:9s} ra={ra:9s} asr={text!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
