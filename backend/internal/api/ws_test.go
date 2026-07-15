package api

import (
	"testing"
)

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
