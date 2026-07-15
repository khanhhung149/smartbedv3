# Service ASR self-host (faster-whisper + FastAPI). Build từ thư mục asr/ (context ../asr trong
# backend/docker-compose.yml).
FROM python:3.11-slim

WORKDIR /app

# ffmpeg cần cho faster-whisper decode một số định dạng audio; giữ để an toàn dù WAV thường
# decode được trực tiếp qua soundfile/pyav đi kèm.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 9000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "9000"]
