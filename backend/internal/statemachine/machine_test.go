package statemachine

import (
	"testing"
	"time"
)

func cfg() Config {
	return Config{EnterWindow: 15 * time.Second, ExitTimeout: 60 * time.Second}
}

func TestEnterTurnsOn(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	if cmd := m.OnMotion(1, base); cmd != nil {
		t.Fatalf("motion đơn lẻ không nên ra lệnh, got %v", *cmd)
	}
	cmd := m.OnPresence(true, 2, base.Add(2*time.Second))
	if cmd == nil || *cmd != "on" {
		t.Fatalf("expected on, got %v", cmd)
	}
}

func TestPresenceWithoutMotionNoOn(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	if cmd := m.OnPresence(true, 1, base); cmd != nil {
		t.Fatalf("presence không kèm motion không nên bật (chống false-positive), got %v", *cmd)
	}
}

func TestMotionTooOldNoOn(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	// presence tới sau EnterWindow (15s) -> không coi là vào
	if cmd := m.OnPresence(true, 2, base.Add(20*time.Second)); cmd != nil {
		t.Fatalf("motion quá cũ không nên bật, got %v", *cmd)
	}
}

func TestExitAfterTimeout(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	if cmd := m.OnPresence(true, 2, base.Add(1*time.Second)); cmd == nil || *cmd != "on" {
		t.Fatalf("expected on, got %v", cmd)
	}
	if cmd := m.OnPresence(false, 3, base.Add(10*time.Second)); cmd != nil {
		t.Fatalf("không nên tắt ngay khi presence false, got %v", *cmd)
	}
	if cmd := m.Tick(base.Add(30 * time.Second)); cmd != nil {
		t.Fatalf("chưa đủ ExitTimeout không nên tắt, got %v", *cmd)
	}
	cmd := m.Tick(base.Add(75 * time.Second)) // false từ +10s, +60s = +70s
	if cmd == nil || *cmd != "off" {
		t.Fatalf("expected off, got %v", cmd)
	}
}

func TestFlickerNoOff(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	m.OnPresence(true, 2, base.Add(1*time.Second)) // on
	m.OnPresence(false, 3, base.Add(5*time.Second)) // blip false
	m.OnPresence(true, 4, base.Add(10*time.Second)) // true lại trước timeout
	if cmd := m.Tick(base.Add(120 * time.Second)); cmd != nil {
		t.Fatalf("nhấp nháy presence không nên tắt, got %v", *cmd)
	}
}

func TestReentryTurnsOnAgain(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	m.OnPresence(true, 2, base.Add(1*time.Second))  // on
	m.OnPresence(false, 3, base.Add(10*time.Second)) // rời
	if cmd := m.Tick(base.Add(75 * time.Second)); cmd == nil || *cmd != "off" {
		t.Fatalf("expected off, got %v", cmd)
	}
	// vào lại: motion + presence
	m.OnMotion(4, base.Add(100*time.Second))
	cmd := m.OnPresence(true, 5, base.Add(101*time.Second))
	if cmd == nil || *cmd != "on" {
		t.Fatalf("vào lại phải bật, got %v", cmd)
	}
}
