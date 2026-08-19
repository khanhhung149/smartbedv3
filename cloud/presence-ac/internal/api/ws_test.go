package api

import (
	"net/http"
	"testing"
)

// Canh route WS được đăng ký ĐÚNG chỗ. Test cũ chỉ kiểm logic hub nên không thấy
// route nằm ở "/ws" (gốc) trong khi app + docs gọi "/api/ws" -> app 404, mất realtime
// mà REST vẫn chạy nên bug ẩn rất kỹ. Bắt tay WS không thành trong httptest, nhưng
// 404 vs không-404 là đủ để phát hiện lệch đường dẫn.
func TestWSRouteRegisteredUnderAPI(t *testing.T) {
	h := NewRouter(fakeSP{}, &fakePub{}, NewHub(), nil)

	w := do(t, h, http.MethodGet, "/api/ws", "")
	if w.Code == http.StatusNotFound {
		t.Fatalf("/api/ws trả 404 — route đăng ký sai chỗ; app sẽ mất realtime")
	}

	// Đường cũ ở gốc phải KHÔNG còn, nếu không là có 2 đường dễ lệch nhau về sau.
	if w2 := do(t, h, http.MethodGet, "/ws", ""); w2.Code != http.StatusNotFound {
		t.Errorf("/ws (gốc) vẫn còn, status=%d — chỉ nên có /api/ws", w2.Code)
	}
}

// Test logic hub không cần WebSocket conn thật (Broadcast chỉ đụng channel send).
func TestHubBroadcastAndRemove(t *testing.T) {
	h := NewHub()
	c := &wsClient{send: make(chan []byte, 4)}
	h.add(c)

	h.Broadcast(map[string]string{"k": "v"})
	select {
	case data := <-c.send:
		if len(data) == 0 {
			t.Fatal("broadcast rỗng")
		}
	default:
		t.Fatal("client không nhận broadcast")
	}

	h.remove(c)
	if _, ok := <-c.send; ok {
		t.Fatal("send phải đóng sau remove")
	}
	// remove lần 2 không được panic
	h.remove(c)
}

func TestHubSlowClientNoBlock(t *testing.T) {
	h := NewHub()
	c := &wsClient{send: make(chan []byte, 1)}
	h.add(c)
	// buffer=1; broadcast nhiều lần không được block (client chậm bị bỏ)
	for i := 0; i < 10; i++ {
		h.Broadcast(map[string]int{"n": i})
	}
	h.remove(c)
}
