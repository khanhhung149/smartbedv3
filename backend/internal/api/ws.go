package api

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// Hub quản lý các client WebSocket, broadcast snapshot khi state đổi.
type Hub struct {
	mu      sync.Mutex
	clients map[*wsClient]struct{}
}

type wsClient struct {
	conn *websocket.Conn
	send chan []byte
}

func NewHub() *Hub {
	return &Hub{clients: make(map[*wsClient]struct{})}
}

// Broadcast gửi v (JSON) tới mọi client. Client chậm bị bỏ qua (non-blocking),
// sẽ được dọn khi write lỗi.
func (h *Hub) Broadcast(v any) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		select {
		case c.send <- data:
		default:
		}
	}
}

func (h *Hub) add(c *wsClient) {
	h.mu.Lock()
	h.clients[c] = struct{}{}
	h.mu.Unlock()
}

func (h *Hub) remove(c *wsClient) {
	h.mu.Lock()
	if _, ok := h.clients[c]; ok {
		delete(h.clients, c)
		close(c.send)
	}
	h.mu.Unlock()
}

// serveWS — GET /ws: gửi snapshot hiện tại rồi push mỗi lần state đổi.
func (h *Hub) serveWS(sp StateProvider) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
			OriginPatterns: []string{"*"}, // LAN nội bộ, cho mọi origin (siết nếu mở internet)
		})
		if err != nil {
			return
		}
		c := &wsClient{conn: conn, send: make(chan []byte, 16)}
		h.add(c)
		defer func() {
			h.remove(c)
			conn.Close(websocket.StatusNormalClosure, "")
		}()

		ctx, cancel := context.WithCancel(r.Context())
		defer cancel()

		// Snapshot hiện tại ngay khi connect
		if data, err := json.Marshal(sp.Snapshot()); err == nil {
			c.send <- data
		}

		// Reader: phát hiện client đóng → cancel để writer thoát
		go func() {
			for {
				if _, _, err := conn.Read(ctx); err != nil {
					cancel()
					return
				}
			}
		}()

		// Writer
		for {
			select {
			case <-ctx.Done():
				return
			case data, ok := <-c.send:
				if !ok {
					return
				}
				wctx, wcancel := context.WithTimeout(ctx, 5*time.Second)
				err := conn.Write(wctx, websocket.MessageText, data)
				wcancel()
				if err != nil {
					return
				}
			}
		}
	}
}
