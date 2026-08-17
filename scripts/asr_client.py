#!/usr/bin/env python3
"""Gọi service ASR đang chạy thật. Dùng chung cho các script đo.

Gọi service qua HTTP thay vì tự nạp model: đo ĐÚNG thứ đang chạy, gồm cả engine đang cấu hình
(sherpa hay whisper) và mọi tham số của nó. Tự nạp model là đo một cấu hình song song mà không ai
đang dùng.
"""

import json
import urllib.request
import wave
from io import BytesIO

import numpy as np

# Service ASR không expose ra host, nên script gọi nó phải chạy trong mạng compose
# (docker run --network backend_default ...).
ASR_URL = "http://asr:9000/transcribe"

SAMPLE_RATE = 16000


def wav_bytes(pcm, sample_rate=SAMPLE_RATE):
    """PCM16 -> nội dung file WAV trong bộ nhớ, khỏi ghi ra đĩa."""
    buf = BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(np.asarray(pcm, dtype=np.int16).tobytes())
    return buf.getvalue()


def goi_asr(data, url=ASR_URL, timeout=120):
    """POST multipart/form-data bằng stdlib — khỏi cài requests vào container chấm điểm."""
    bien = "----docasr"
    than = (
        f"--{bien}\r\n"
        'Content-Disposition: form-data; name="file"; filename="a.wav"\r\n'
        "Content-Type: audio/wav\r\n\r\n"
    ).encode() + data + f"\r\n--{bien}--\r\n".encode()

    req = urllib.request.Request(
        url, data=than, headers={"Content-Type": f"multipart/form-data; boundary={bien}"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())
