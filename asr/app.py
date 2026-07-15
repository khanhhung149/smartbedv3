# Service ASR self-host dùng faster-whisper, nhận WAV -> trả text tiếng Việt.
# Chạy cạnh backend Go (docker-compose service "asr"), không expose ra ngoài LAN —
# backend gọi nội bộ qua network compose (http://asr:9000/transcribe), audio không rời máy.
import io
import logging
import os

from fastapi import FastAPI, File, HTTPException, UploadFile
from faster_whisper import WhisperModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("asr")

# Model tải 1 lần lúc khởi động tiến trình. "small" mặc định (cân bằng tốc độ CPU/độ chính xác
# tiếng Việt); đổi ASR_MODEL=tiny nếu máy yếu, base/medium nếu cần chính xác hơn (chậm hơn).
# device="cpu" + compute_type="int8" để chạy được trên máy không có GPU (MVP, xem risk ở plan).
MODEL_NAME = os.getenv("ASR_MODEL", "small")
model = WhisperModel(MODEL_NAME, device="cpu", compute_type="int8")

app = FastAPI(title="asr-service")


@app.get("/healthz")
def healthz():
    """Health check cho compose/monitor — xác nhận process sống và model nào đang load."""
    return {"status": "ok", "model": MODEL_NAME}


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    """Nhận WAV (multipart form field "file", 16-bit PCM mono — backend Go build sẵn header),
    trả {"text": "..."} tiếng Việt. Lỗi decode/audio rỗng -> HTTPException rõ ràng, không để
    exception lạ làm crash worker (backend coi lỗi HTTP là "bỏ qua utterance", không crash theo).
    """
    wav_bytes = await file.read()
    if not wav_bytes:
        raise HTTPException(status_code=400, detail="file rỗng, cần WAV bytes")

    try:
        segments, _info = model.transcribe(io.BytesIO(wav_bytes), language="vi")
        text = "".join(seg.text for seg in segments).strip()
    except Exception as exc:  # noqa: BLE001 - trả lỗi rõ ràng cho caller thay vì 500 mù mờ
        logger.warning("transcribe lỗi: %s", exc)
        raise HTTPException(status_code=500, detail=f"transcribe lỗi: {exc}") from exc

    return {"text": text}
