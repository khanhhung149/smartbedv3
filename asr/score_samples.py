"""Chấm điểm model ASR trên MỘT bộ mẫu WAV cố định — công cụ đo, không phải đường chạy thật.

Chạy trong container home-asr (nơi có faster-whisper + cache model):
    docker exec home-asr python /app/score_samples.py small medium

Nhãn đúng lấy từ TIỀN TỐ tên file: "on-*.wav" là câu "bật", "off-*.wav" là câu "tắt".
Đặt tiền tố sau khi thu (xem plans/reports/...voice-accuracy...): thu 10 câu bật -> đổi tên
loạt đó thành on-*, rồi thu 10 câu tắt -> đổi thành off-*.

Nạp model TUẦN TỰ rồi giải phóng, không giữ cả hai trong RAM cùng lúc (medium int8 ~1.5GB).
Service đang chạy KHÔNG bị đụng tới: script tự nạp model riêng, không đổi ASR_MODEL.
"""

import gc
import os
import sys
import time
import unicodedata

from faster_whisper import WhisperModel

from transcribe_opts import TRANSCRIBE_OPTS

SAMPLE_DIR = os.getenv("ASR_DUMP_DIR") or "/samples"


def strip_diacritics(s: str) -> str:
    """Bỏ dấu tiếng Việt. Tương đương bảng rune trong backend/internal/voice/command.go.

    Bảng bên Go chỉ nhận ký tự DỰNG SẴN (NFC). Nếu whisper trả về dạng tổ hợp (NFD) thì Go bỏ
    dấu hụt và câu không khớp lệnh, trong khi hàm này vẫn bỏ được -> điểm đo cao hơn thực tế.
    Vì vậy parse_command cảnh báo khi gặp text không phải NFC thay vì lặng lẽ nuốt.
    """
    decomposed = unicodedata.normalize("NFD", s.replace("đ", "d").replace("Đ", "D"))
    return "".join(c for c in decomposed if not unicodedata.combining(c))


def parse_command(text: str) -> str | None:
    """Bản sao ParseVietCommand (backend/internal/voice/command.go) — NGUỒN SỰ THẬT là file Go.

    Trả "on" / "off" / None. Câu chứa CẢ bật lẫn tắt bị loại (None), không chọn một trong hai.
    """
    if text and not unicodedata.is_normalized("NFC", text):
        print(f"    ⚠️  text không phải NFC — bên Go sẽ bỏ dấu hụt: {text!r}")

    normalized = strip_diacritics(text.strip().lower())
    if "dieu hoa" not in normalized and "may lanh" not in normalized:
        return None

    want_on = "bat" in normalized
    want_off = "tat" in normalized
    if want_on and want_off:
        return None
    if want_on:
        return "on"
    if want_off:
        return "off"
    return None


def load_samples() -> list[tuple[str, str]]:
    """Trả [(đường dẫn, nhãn đúng)] cho các file có tiền tố on-/off-. File chưa gán nhãn bị bỏ."""
    if not os.path.isdir(SAMPLE_DIR):
        sys.exit(f"Không thấy thư mục mẫu {SAMPLE_DIR} — đã bật ASR_DUMP_DIR chưa?")

    samples, unlabeled = [], 0
    for name in sorted(os.listdir(SAMPLE_DIR)):
        if not name.endswith(".wav"):
            continue
        if name.startswith("on-"):
            samples.append((os.path.join(SAMPLE_DIR, name), "on"))
        elif name.startswith("off-"):
            samples.append((os.path.join(SAMPLE_DIR, name), "off"))
        else:
            unlabeled += 1

    if unlabeled:
        print(f"Bỏ qua {unlabeled} file chưa gán nhãn (cần đổi tên thành on-*.wav / off-*.wav)\n")
    if not samples:
        sys.exit("Chưa có mẫu nào được gán nhãn.")
    return samples


def score(model_name: str, samples: list[tuple[str, str]]) -> dict:
    print(f"\n=== {model_name} ===")
    t0 = time.time()
    model = WhisperModel(model_name, device="cpu", compute_type="int8")
    print(f"nạp model: {time.time() - t0:.1f}s")

    tally = {"dung": 0, "sai": 0, "loai": 0, "tong_giay": 0.0}
    try:
        for path, truth in samples:
            t = time.time()
            segments, _info = model.transcribe(path, **TRANSCRIBE_OPTS)
            text = "".join(seg.text for seg in segments).strip()
            elapsed = time.time() - t
            tally["tong_giay"] += elapsed

            got = parse_command(text)
            if got == truth:
                mark, key = "✅", "dung"
            elif got is None:
                mark, key = "➖", "loai"
            else:
                mark, key = "❌", "sai"  # nhận NGƯỢC chiều — nguy hiểm nhất
            tally[key] += 1
            print(f"  {mark} [{truth:>3}->{str(got):>4}] {elapsed:5.1f}s  {text!r}")
    finally:
        del model
        gc.collect()

    return tally


def main() -> None:
    models = sys.argv[1:] or ["small", "medium"]
    samples = load_samples()
    print(f"{len(samples)} mẫu: "
          f"{sum(1 for _, t in samples if t == 'on')} bật / "
          f"{sum(1 for _, t in samples if t == 'off')} tắt")

    results = {name: score(name, samples) for name in models}

    n = len(samples)
    print(f"\n{'model':<10}{'đúng':>8}{'SAI chiều':>12}{'bị loại':>10}{'giây/câu':>11}")
    for name, r in results.items():
        print(f"{name:<10}{r['dung']:>5}/{n:<2}{r['sai']:>12}{r['loai']:>10}"
              f"{r['tong_giay'] / n:>11.1f}")
    print("\nSAI chiều phải là 0 — bật thành tắt là hỏng nặng hơn hẳn không nhận ra lệnh.")


if __name__ == "__main__":
    main()
