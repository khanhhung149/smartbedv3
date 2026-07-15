package voice

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"time"
)

// ASRClient gọi service faster-whisper self-host (asr/app.py) qua HTTP multipart POST WAV.
type ASRClient struct {
	url  string
	http *http.Client
}

// NewASRClient tạo client với timeout riêng cho request ASR (không dùng context nền vô hạn —
// tránh treo handler WS khi service ASR chậm/đứng).
func NewASRClient(url string, timeout time.Duration) *ASRClient {
	return &ASRClient{url: url, http: &http.Client{Timeout: timeout}}
}

// transcribeResp — payload trả về từ POST /transcribe: {"text": "..."}.
type transcribeResp struct {
	Text string `json:"text"`
}

// Transcribe gửi wav (WAV bytes 16-bit mono) tới service ASR dưới dạng multipart/form-data
// field "file", trả về text tiếng Việt nhận diện được. Lỗi mạng/timeout/HTTP/parse đều trả về
// error rõ ràng — KHÔNG panic, caller (stream.go) chịu trách nhiệm log rồi bỏ qua utterance.
func (c *ASRClient) Transcribe(ctx context.Context, wav []byte) (string, error) {
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	part, err := mw.CreateFormFile("file", "utterance.wav")
	if err != nil {
		return "", fmt.Errorf("asr: tạo multipart form lỗi: %w", err)
	}
	if _, err := part.Write(wav); err != nil {
		return "", fmt.Errorf("asr: ghi wav vào multipart lỗi: %w", err)
	}
	if err := mw.Close(); err != nil {
		return "", fmt.Errorf("asr: đóng multipart writer lỗi: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.url, &body)
	if err != nil {
		return "", fmt.Errorf("asr: tạo request lỗi: %w", err)
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())

	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("asr: gọi service lỗi: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return "", fmt.Errorf("asr: service trả status %d: %s", resp.StatusCode, string(errBody))
	}

	var out transcribeResp
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", fmt.Errorf("asr: parse JSON response lỗi: %w", err)
	}
	return out.Text, nil
}
