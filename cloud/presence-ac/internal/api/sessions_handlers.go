package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/hung/home-backend/internal/sessions"
)

// SessionLister supplies sleep sessions to the API.
type SessionLister interface {
	ListSessions(ctx context.Context, deviceID string, start, end *time.Time, limit int) ([]sessions.SessionRow, error)
	GetSession(ctx context.Context, id string) (*sessions.SessionRow, error)
	GetTimeline(ctx context.Context, deviceID string, start time.Time, end *time.Time, interval string) ([]sessions.TimelinePoint, error)
	GetLatestSec(ctx context.Context, deviceID string) (*sessions.LatestSec, error)
}

// timeline interval is a server-owned constant, never a query-string value.
const timelineInterval = "1 minute"

func (a *API) listSessions(w http.ResponseWriter, r *http.Request) {
	if a.sS == nil {
		http.Error(w, `{"error":"sleep sessions chưa được bật (thiếu POSTGRES_URL)"}`, http.StatusServiceUnavailable)
		return
	}
	q := r.URL.Query()
	deviceID := q.Get("device_id")
	if deviceID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "thiếu device_id"})
		return
	}
	limit := 100
	if v := q.Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}
	var start, end *time.Time
	if v := q.Get("start"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			start = &t
		}
	}
	if v := q.Get("end"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			end = &t
		}
	}

	ctx := r.Context()
	rows, err := a.sS.ListSessions(ctx, deviceID, start, end, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	// Slice nil trong Go encode ra `null`, không phải `[]`. Client nào ép thẳng
	// sang mảng sẽ nổ khi thiết bị chưa có phiên nào — đã xảy ra với app Flutter.
	// Danh sách rỗng của một API JSON phải là `[]`.
	if rows == nil {
		rows = []sessions.SessionRow{}
	}
	writeJSON(w, http.StatusOK, rows)
}

func (a *API) getSession(w http.ResponseWriter, r *http.Request) {
	if a.sS == nil {
		http.Error(w, `{"error":"sleep sessions chưa được bật (thiếu POSTGRES_URL)"}`, http.StatusServiceUnavailable)
		return
	}
	id := r.PathValue("id")
	sess, err := a.sS.GetSession(r.Context(), id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	if sess == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "phiên không tồn tại"})
		return
	}
	writeJSON(w, http.StatusOK, sess)
}

func (a *API) getTimeline(w http.ResponseWriter, r *http.Request) {
	if a.sS == nil {
		http.Error(w, `{"error":"sleep sessions chưa được bật (thiếu POSTGRES_URL)"}`, http.StatusServiceUnavailable)
		return
	}
	id := r.PathValue("id")
	sess, err := a.sS.GetSession(r.Context(), id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	if sess == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "phiên không tồn tại"})
		return
	}

	points, err := a.sS.GetTimeline(r.Context(), sess.DeviceID, sess.StartedAt, sess.EndedAt, timelineInterval)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"session_id": sess.ID,
		"bucket":     "1m",
		"points":     points,
	})
}

// getRealtime trả mẫu mới nhất của thiết bị cho màn xem trực tiếp.
//
// Không có auth: backend này chỉ chạy trong LAN, giống mọi endpoint còn lại
// (xem docs/sleep-session-api-contract.md). Client tự quyết định mẫu cũ bao nhiêu
// thì coi là mất tín hiệu — server không đoán hộ vì ngưỡng đó phụ thuộc cách hiển thị.
func (a *API) getRealtime(w http.ResponseWriter, r *http.Request) {
	if a.sS == nil {
		http.Error(w, `{"error":"sleep sessions chưa được bật (thiếu POSTGRES_URL)"}`, http.StatusServiceUnavailable)
		return
	}
	deviceID := r.URL.Query().Get("device_id")
	if deviceID == "" {
		http.Error(w, `{"error":"thiếu device_id"}`, http.StatusBadRequest)
		return
	}
	row, err := a.sS.GetLatestSec(r.Context(), deviceID)
	if err != nil {
		http.Error(w, `{"error":"truy vấn thất bại"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if row == nil {
		// Thiết bị hợp lệ nhưng chưa có mẫu nào — khác lỗi, nên trả 200 với null
		// để client phân biệt "chưa có dữ liệu" với "gọi hỏng".
		_, _ = w.Write([]byte("null"))
		return
	}
	_ = json.NewEncoder(w).Encode(row)
}
