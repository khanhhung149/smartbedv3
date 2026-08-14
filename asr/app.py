# Service ASR self-host dùng faster-whisper, nhận WAV -> trả text tiếng Việt.
# Chạy cạnh backend Go (docker-compose service "asr"), không expose ra ngoài LAN —
# backend gọi nội bộ qua network compose (http://asr:9000/transcribe), audio không rời máy.
import io
import logging
import os
import wave
from datetime import datetime

from fastapi import FastAPI, File, HTTPException, UploadFile

from asr_engine import build_engine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("asr")

# Lưu mẫu WAV để đo độ chính xác. TẮT mặc định (không set env = không lưu) vì thư mục sẽ
# phình vô hạn khi chạy thường. Bật bằng: ASR_DUMP_DIR=/samples docker compose up -d asr
#
# Vì sao cần: suốt 30/07 mọi thay đổi đều phán xét bằng MỘT lần thử, nên hồi quy initial_prompt
# lọt qua (whisper nghe "Bật"->"Bọc") mà không ai phát hiện. Không có bộ mẫu cố định thì không
# so sánh được model/tham số — chỉ so được cảm giác.
DUMP_DIR = os.getenv("ASR_DUMP_DIR", "").strip()

# Engine tải 1 lần lúc khởi động tiến trình. Mặc định sherpa-onnx Zipformer (ASR_ENGINE=sherpa);
# đặt ASR_ENGINE=whisper để về faster-whisper, và ASR_MODEL chọn cỡ model cho riêng đường đó.
# Lý do chọn mặc định và số đo so sánh: xem docstring asr_engine.py.
engine = build_engine()
MODEL_NAME = engine.name

app = FastAPI(title="asr-service")


@app.get("/healthz")
def healthz():
    """Health check cho compose/monitor — xác nhận process sống và model nào đang load."""
    return {"status": "ok", "model": MODEL_NAME, "dump_dir": DUMP_DIR or None}


def dump_sample(wav_bytes: bytes) -> str:
    """Lưu WAV thành file RIÊNG mỗi utterance. Trả tên file, hoặc "" nếu tắt/lỗi.

    Tên file mang mốc thời gian tới mili-giây + thời lượng: chọn được mẫu câu TRỌN VẸN mà không
    phải mở từng file. Ghi đè vào một tên cố định là sai lầm đã mắc 30/07 — mọi phân tích sau đó
    chạy trên mảnh vụn 200ms cuối cùng, làm phép so small/medium trở nên vô nghĩa.

    Lỗi lưu file KHÔNG được làm hỏng phiên dịch: đây là công cụ đo, không phải đường chính.
    """
    if not DUMP_DIR:
        return ""
    try:
        with wave.open(io.BytesIO(wav_bytes)) as w:
            secs = w.getnframes() / float(w.getframerate())
        os.makedirs(DUMP_DIR, exist_ok=True)
        name = f"{datetime.now().strftime('%Y%m%d-%H%M%S-%f')[:-3]}-{secs:.1f}s.wav"
        with open(os.path.join(DUMP_DIR, name), "wb") as f:
            f.write(wav_bytes)
        return name
    except Exception as exc:  # noqa: BLE001 - dump hỏng thì bỏ qua, đừng kéo theo cả request
        logger.warning("lưu mẫu lỗi: %s", exc)
        return ""


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    """Nhận WAV (multipart form field "file", 16-bit PCM mono — backend Go build sẵn header),
    trả {"text": "..."} tiếng Việt. Lỗi decode/audio rỗng -> HTTPException rõ ràng, không để
    exception lạ làm crash worker (backend coi lỗi HTTP là "bỏ qua utterance", không crash theo).
    """
    wav_bytes = await file.read()
    if not wav_bytes:
        raise HTTPException(status_code=400, detail="file rỗng, cần WAV bytes")

    sample = dump_sample(wav_bytes)

    try:
        # Engine tự lo tham số riêng của nó (Whisper đọc transcribe_opts.py, sherpa dùng
        # greedy_search) — xem asr_engine.py.
        text = engine.transcribe(wav_bytes)
    except Exception as exc:  # noqa: BLE001 - trả lỗi rõ ràng cho caller thay vì 500 mù mờ
        logger.warning("transcribe lỗi: %s", exc)
        raise HTTPException(status_code=500, detail=f"transcribe lỗi: {exc}") from exc

    # Log cả tên mẫu lẫn text: lúc thu mẫu thấy ngay câu nào hỏng để thu lại, không phải đợi
    # chấm điểm xong mới biết mất công thu.
    logger.info("mẫu=%s text=%r", sample or "-", text)
    return {"text": text}
