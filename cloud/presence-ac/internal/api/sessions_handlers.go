package api

import (
	"context"
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
	sessions, err := a.sS.ListSessions(ctx, deviceID, start, end, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, sessions)
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
