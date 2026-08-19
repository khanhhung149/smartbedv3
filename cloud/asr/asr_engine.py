"""Hai engine ASR sau một interface chung, chọn bằng biến môi trường ASR_ENGINE.

Vì sao có hai: đo trên 15 mẫu giọng thật ngày 2026-08-14 (xem
plans/reports/...voice-accuracy...), Zipformer và Whisper-small khớp lệnh NGANG NHAU (12/15) nhưng
Zipformer nhanh hơn ~5 lần (0,20s so với ~1s mỗi câu) và không kéo theo PyTorch. Chọn Zipformer làm
mặc định vì tốc độ; giữ Whisper làm đường lui vì nó đã chạy ổn định nhiều tuần và là thứ duy nhất
score_samples.py biết chấm điểm.

Khác biệt đầu ra cần biết khi đọc log: Zipformer trả chữ IN HOA không dấu câu ("BẬT MÁY LẠNH"),
Whisper trả chữ thường có dấu câu ("Bật máy lạnh."). ParseVietCommand phía Go đã ToLower + bỏ dấu
trước khi so nên cả hai dạng đều khớp — đừng "sửa" bằng cách ép định dạng ở đây.
"""
import io
import logging
import os
import wave

logger = logging.getLogger("asr.engine")

# Model Zipformer RNN-T 30M do sherpa-onnx đóng gói sẵn (encoder/decoder/joiner + tokens), train
# trên ~6000h tiếng Việt. Tải về volume cache dùng chung với Whisper nên đổi qua lại không phải
# tải lại từ đầu.
SHERPA_REPO = os.getenv("SHERPA_REPO", "csukuangfj/sherpa-onnx-zipformer-vi-2025-04-20")
SHERPA_ENCODER = "encoder-epoch-12-avg-8.onnx"
SHERPA_DECODER = "decoder-epoch-12-avg-8.onnx"
SHERPA_JOINER = "joiner-epoch-12-avg-8.onnx"


def _read_wav_mono16k(wav_bytes: bytes):
    """WAV bytes -> (sample_rate, float32 numpy [-1,1]). Backend luôn gửi PCM16 mono 16kHz."""
    import numpy as np

    with wave.open(io.BytesIO(wav_bytes)) as w:
        if w.getsampwidth() != 2 or w.getnchannels() != 1:
            raise ValueError(
                f"cần PCM16 mono, nhận được {w.getsampwidth()*8}-bit {w.getnchannels()} kênh"
            )
        sr = w.getframerate()
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    return sr, pcm.astype(np.float32) / 32768.0


class SherpaEngine:
    """sherpa-onnx Zipformer RNN-T — ONNX Runtime, không cần PyTorch."""

    name = "sherpa-zipformer-vi"

    def __init__(self, num_threads: int = 4):
        import sherpa_onnx
        from huggingface_hub import snapshot_download

        # snapshot_download dùng chung HF cache với faster-whisper (volume asr-model-cache), nên
        # model chỉ tải một lần và sống qua các lần recreate container.
        d = snapshot_download(SHERPA_REPO)
        self._rec = sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=os.path.join(d, SHERPA_ENCODER),
            decoder=os.path.join(d, SHERPA_DECODER),
            joiner=os.path.join(d, SHERPA_JOINER),
            tokens=os.path.join(d, "tokens.txt"),
            num_threads=num_threads,
            sample_rate=16000,
            feature_dim=80,
            decoding_method="greedy_search",
        )
        logger.info("nạp xong %s từ %s", self.name, SHERPA_REPO)

    def transcribe(self, wav_bytes: bytes) -> str:
        sr, samples = _read_wav_mono16k(wav_bytes)
        stream = self._rec.create_stream()
        stream.accept_waveform(sr, samples)
        self._rec.decode_stream(stream)
        return stream.result.text.strip()


class WhisperEngine:
    """faster-whisper — đường lui. Tham số nằm ở transcribe_opts.py, dùng chung score_samples.py."""

    name = "faster-whisper"

    def __init__(self, model_name: str, compute_type: str = "int8"):
        from faster_whisper import WhisperModel

        self._model = WhisperModel(model_name, device="cpu", compute_type=compute_type)
        self.name = f"faster-whisper:{model_name}"
        logger.info("nạp xong %s", self.name)

    def transcribe(self, wav_bytes: bytes) -> str:
        from transcribe_opts import TRANSCRIBE_OPTS

        segments, _info = self._model.transcribe(io.BytesIO(wav_bytes), **TRANSCRIBE_OPTS)
        return "".join(seg.text for seg in segments).strip()


def build_engine():
    """Dựng engine theo ASR_ENGINE. Lỗi nạp sherpa KHÔNG được làm chết service — rơi về Whisper,
    vì mất giọng nói hoàn toàn tệ hơn nhiều so với chạy chậm hơn một chút."""
    choice = os.getenv("ASR_ENGINE", "sherpa").strip().lower()
    whisper_model = os.getenv("ASR_MODEL", "small")

    if choice == "sherpa":
        try:
            return SherpaEngine()
        except Exception as exc:  # noqa: BLE001 - lý do ghi rõ rồi rơi về đường lui
            logger.warning("nạp sherpa lỗi (%s) -> rơi về faster-whisper", exc)
    return WhisperEngine(whisper_model)
