#!/usr/bin/env python3
"""Sinh mẫu dương "vừng ơi" bằng VieNeu-TTS chạy localhost — không API ngoài, không tốn tiền.

    # liệt kê giọng preset kèm nhãn miền
    python3 scripts/sinh-mau-tts-local.py --liet-ke

    # nhánh preset: 60 clip mỗi giọng
    python3 scripts/sinh-mau-tts-local.py --ra datasets/generated_samples_moi --so-luong 60 \
        --giong "Minh Triết" --giong "Ngọc Trân" --giong "Thái Sơn"

    # nhánh nhân bản giọng user
    python3 scripts/sinh-mau-tts-local.py --ra datasets/generated_samples_moi --so-luong 150 \
        --ref datasets/tts-spike/ref-giong-user.wav

Chạy bằng venv riêng:  ~/.venvs/tts/bin/python

Vì sao tự host thay vì gọi API: everai khoá API sau gói trả phí (`402`), và gói Free không có
quyền API. VieNeu chạy CPU tại chỗ, miễn phí, không giới hạn số lượng.

Vì sao KHÔNG tự làm augmentation ở đây: ô 14 notebook đã lo EQ/distortion/pitch/RIR/nhạc/ồn.
Làm thêm ở đây là vi phạm DRY và làm lệch phân bố tập train.

Vì sao render lặp lại vẫn ra clip mới: VieNeu KHÔNG tất định — đo 09/08, 3 lần gọi cùng câu cùng
giọng cho 3 hash khác nhau và dốc F0 khác thật. Nên số lượng mẫu không bị chặn bởi số giọng.

Xuất WAV 16 kHz mono: VieNeu ra 48 kHz. Không hạ mẫu ở đây thì lệch tần số chỉ lộ ra tận lúc
train/đo board và rất khó truy ngược.
"""
import argparse
import sys
import time
import unicodedata
from pathlib import Path

SR_DICH = 16000  # khớp clip_duration_ms của model wakeword
BIEN_THE = ["vừng ơi", "Vừng ơi!", "vừng ơi..."]


def slug(s: str) -> str:
    """Bỏ dấu + gạch nối. Tên file ASCII để không vỡ khi nén/giải nén qua Colab."""
    khong_dau = "".join(
        c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn"
    )
    return "".join(c if c.isalnum() else "-" for c in khong_dau.replace("đ", "d").replace("Đ", "D")).strip("-").lower()


def doc_mien(nhan: str) -> str:
    """Tách nhãn miền từ label preset.

    Định dạng label: "Minh Đức — Nam · Bắc · Phong cách tin tức"
                      tên      — giới · MIỀN · phong cách
    Đọc từ label thay vì bảng cứng: thêm/bớt giọng ở bản VieNeu sau vẫn chạy đúng.
    """
    phan = [p.strip() for p in nhan.split("·")]
    return slug(phan[1]) if len(phan) >= 2 else "?"


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--ra", type=Path, help="thư mục ghi WAV")
    ap.add_argument("--giong", action="append", default=[], help="tên giọng preset, lặp cờ để thêm")
    ap.add_argument("--ref", type=Path, help="WAV tham chiếu để nhân bản giọng (3-8 giây)")
    ap.add_argument("--so-luong", type=int, default=60, help="số clip mỗi giọng (hoặc tổng, với --ref)")
    ap.add_argument("--liet-ke", action="store_true", help="in danh sách giọng preset rồi thoát")
    args = ap.parse_args()

    import librosa
    import soundfile as sf
    from vieneu import Vieneu

    print("nạp VieNeu…", file=sys.stderr)
    v = Vieneu()
    presets = {ten: nhan for nhan, ten in v.list_preset_voices()}

    if args.liet_ke:
        for nhan, ten in v.list_preset_voices():
            print(f"  {ten:<14} miền={doc_mien(nhan):<6} {nhan}")
        return 0

    if not args.ra:
        print("LỖI: cần --ra", file=sys.stderr)
        return 2
    if not args.giong and not args.ref:
        print("LỖI: cần --giong hoặc --ref", file=sys.stderr)
        return 2

    thieu = [g for g in args.giong if g not in presets]
    if thieu:
        print(f"LỖI: không có giọng {thieu}. Chạy --liet-ke để xem danh sách.", file=sys.stderr)
        return 2

    args.ra.mkdir(parents=True, exist_ok=True)

    # (nhánh, tên giọng, miền, tham số infer)
    viec = []
    for g in args.giong:
        viec.append(("preset", g, doc_mien(presets[g]), {"voice": g}))
    if args.ref:
        if not args.ref.is_file():
            print(f"LỖI: không thấy {args.ref}", file=sys.stderr)
            return 2
        viec.append(("clone", "user", "user", {"ref_audio": str(args.ref), "denoise": True}))

    t0, tong, loi = time.time(), 0, 0
    for nhanh, ten, mien, kw in viec:
        for i in range(args.so_luong):
            text = BIEN_THE[i % len(BIEN_THE)]
            try:
                audio = v.infer(text=text, **kw)
            except Exception as exc:  # noqa: BLE001 - một clip hỏng không được giết cả lô
                loi += 1
                print(f"  ❌ {ten} #{i}: {type(exc).__name__} {exc}", file=sys.stderr)
                continue

            # Hạ mẫu 48k -> 16k rồi cắt lặng hai đầu, cùng top_db với cổng F0 để hai bên
            # nhìn cùng một tín hiệu.
            y = librosa.resample(audio, orig_sr=v.sample_rate, target_sr=SR_DICH)
            y, _ = librosa.effects.trim(y, top_db=30)

            p = args.ra / f"tts-{nhanh}-{slug(ten)}-{mien}-{i:04d}.wav"
            sf.write(p, y, SR_DICH, subtype="PCM_16")
            tong += 1
            if tong % 25 == 0:
                print(f"  … {tong} clip ({time.time() - t0:.0f}s)", file=sys.stderr)

    dt = time.time() - t0
    print(f"\n=== {tong} clip · {dt:.0f}s ({dt / max(tong, 1):.1f}s/clip) · lỗi {loi} ===")
    print(f"→ {args.ra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
