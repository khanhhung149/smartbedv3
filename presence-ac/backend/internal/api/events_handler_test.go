package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/hung/home-backend/internal/store"
)

// fakeLister ghi lại tham số nhận được để test kiểm chứng handler truyền đúng xuống store.
type fakeLister struct {
	events    []store.Event
	err       error
	gotLimit  int
	gotBefore int64
}

func (f *fakeLister) List(limit int, before int64) ([]store.Event, error) {
	f.gotLimit, f.gotBefore = limit, before
	return f.events, f.err
}

func TestGetEventsReturnsEvents(t *testing.T) {
	lister := &fakeLister{events: []store.Event{
		{ID: 2, TS: 1784214584, Kind: store.KindACCmd, Value: "on", Source: "backend"},
		{ID: 1, TS: 0, Kind: store.KindPresence, Value: "true", Source: "room-node"},
	}}
	h := NewRouter(fakeSP{}, &fakePub{}, nil, lister)

	w := do(t, h, http.MethodGet, "/api/events", "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, muốn 200. body=%s", w.Code, w.Body.String())
	}
	var body struct {
		Events []store.Event `json:"events"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v — body=%s", err, w.Body.String())
	}
	if len(body.Events) != 2 {
		t.Fatalf("muốn 2 event, có %d", len(body.Events))
	}
	if body.Events[0].ID != 2 {
		t.Errorf("event đầu ID=%d, muốn 2 (mới nhất trước)", body.Events[0].ID)
	}
	// ts=0 phải giữ nguyên qua JSON để app tự quyết hiển thị "không rõ giờ".
	if body.Events[1].TS != 0 {
		t.Errorf("ts=0 bị đổi thành %d", body.Events[1].TS)
	}
}

// Nếu bug nil-interface tái xuất (truyền con trỏ nil vào tham số interface), test này
// sẽ panic nil-pointer thay vì thấy 503 — đó chính là điều nó canh.
func TestGetEventsNilStoreReturns503(t *testing.T) {
	h := NewRouter(fakeSP{}, &fakePub{}, nil, nil)

	w := do(t, h, http.MethodGet, "/api/events", "")
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, muốn 503 khi chưa bật lịch sử", w.Code)
	}
}

func TestGetEventsPassesQueryParams(t *testing.T) {
	lister := &fakeLister{}
	h := NewRouter(fakeSP{}, &fakePub{}, nil, lister)

	do(t, h, http.MethodGet, "/api/events?limit=10&before=99", "")
	if lister.gotLimit != 10 || lister.gotBefore != 99 {
		t.Errorf("store nhận limit=%d before=%d, muốn 10/99", lister.gotLimit, lister.gotBefore)
	}
}

func TestGetEventsRejectsGarbageParams(t *testing.T) {
	h := NewRouter(fakeSP{}, &fakePub{}, nil, &fakeLister{})

	for _, q := range []string{"?limit=abc", "?before=xyz", "?limit=9999999999999999999999"} {
		w := do(t, h, http.MethodGet, "/api/events"+q, "")
		if w.Code != http.StatusBadRequest {
			t.Errorf("%s → status %d, muốn 400", q, w.Code)
		}
	}
}

func TestGetEventsStoreErrorReturns500(t *testing.T) {
	h := NewRouter(fakeSP{}, &fakePub{}, nil, &fakeLister{err: errors.New("db hỏng")})

	w := do(t, h, http.MethodGet, "/api/events", "")
	if w.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, muốn 500 khi store lỗi", w.Code)
	}
}

// Vắng param → 0, để store tự áp default/bỏ qua. Không được thành 400.
func TestGetEventsWithoutParamsPassesZero(t *testing.T) {
	lister := &fakeLister{}
	h := NewRouter(fakeSP{}, &fakePub{}, nil, lister)

	w := do(t, h, http.MethodGet, "/api/events", "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, muốn 200", w.Code)
	}
	if lister.gotLimit != 0 || lister.gotBefore != 0 {
		t.Errorf("muốn truyền 0/0 khi vắng param, có %d/%d", lister.gotLimit, lister.gotBefore)
	}
}
