#!/usr/bin/env python3
"""Đọc WAV thu từ voice-node. Tách riêng để cả đường chấm model (cần TensorFlow) lẫn đường chấm
năng lượng (chỉ cần numpy) dùng chung một hàm, không nhân bản định dạng."""

import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 16000


def doc_wav(path):
    """Đọc WAV mono 16-bit 16kHz thành mảng int16. Từ chối thẳng định dạng khác thay vì tự chuyển
    đổi — mẫu thu từ voice-node luôn đúng định dạng này, file lệch nghĩa là nhầm nguồn dữ liệu."""
    with wave.open(str(path)) as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != SAMPLE_RATE:
            raise ValueError(
                f"{Path(path).name}: cần mono/16-bit/{SAMPLE_RATE}Hz, gặp {w.getnchannels()}ch/"
                f"{w.getsampwidth() * 8}bit/{w.getframerate()}Hz"
            )
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


def liet_ke_wav(muc_tieu):
    """Trả danh sách file WAV từ một đường dẫn file hoặc thư mục."""
    p = Path(muc_tieu)
    if p.is_dir():
        return sorted(p.glob("*.wav"))
    if p.is_file():
        return [p]
    raise FileNotFoundError(muc_tieu)
