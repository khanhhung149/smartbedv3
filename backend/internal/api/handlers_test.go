package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/hung/home-backend/internal/statemachine"
)

type fakeSP struct{ snap statemachine.Snapshot }

func (f fakeSP) Snapshot() statemachine.Snapshot { return f.snap }

type fakePub struct {
	acCmds    []string
	acTemps   []string
	learns    []string
	connected bool
}

func (f *fakePub) PublishACTemp(dir string, steps int) error {
	f.acTemps = append(f.acTemps, fmt.Sprintf("%s:%d", dir, steps))
	return nil
}
func (f *fakePub) PublishACCmd(cmd string) error { f.acCmds = append(f.acCmds, cmd); return nil }
func (f *fakePub) PublishACLearn(b string) error { f.learns = append(f.learns, b); return nil }
func (f *fakePub) Connected() bool               { return f.connected }

func do(t *testing.T, h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r *http.Request
	if body == "" {
		r = httptest.NewRequest(method, path, nil)
	} else {
		r = httptest.NewRequest(method, path, strings.NewReader(body))
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestGetState(t *testing.T) {
	sp := fakeSP{snap: statemachine.Snapshot{Present: true, Occupied: true, ACDesired: true, LastACCmd: "on"}}
	h := NewRouter(sp, &fakePub{}, nil, nil)
	w := do(t, h, "GET", "/api/state", "")
	if w.Code != 200 {
		t.Fatalf("code=%d", w.Code)
	}
	var got statemachine.Snapshot
	json.Unmarshal(w.Body.Bytes(), &got)
	if !got.Occupied || got.LastACCmd != "on" {
		t.Fatalf("snapshot sai: %+v", got)
	}
}

func TestPostACValid(t *testing.T) {
	pub := &fakePub{}
	h := NewRouter(fakeSP{}, pub, nil, nil)
	w := do(t, h, "POST", "/api/ac", `{"cmd":"on"}`)
	if w.Code != http.StatusAccepted {
		t.Fatalf("code=%d body=%s", w.Code, w.Body.String())
	}
	if len(pub.acCmds) != 1 || pub.acCmds[0] != "on" {
		t.Fatalf("chưa publish đúng: %v", pub.acCmds)
	}
}

func TestPostACInvalid(t *testing.T) {
	pub := &fakePub{}
	h := NewRouter(fakeSP{}, pub, nil, nil)
	w := do(t, h, "POST", "/api/ac", `{"cmd":"banana"}`)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("cmd sai phải 400, got %d", w.Code)
	}
	if len(pub.acCmds) != 0 {
		t.Fatalf("không được publish khi cmd sai: %v", pub.acCmds)
	}
}

func TestPostACLearnValid(t *testing.T) {
	pub := &fakePub{}
	h := NewRouter(fakeSP{}, pub, nil, nil)
	w := do(t, h, "POST", "/api/ac/learn", `{"button":"off"}`)
	if w.Code != http.StatusAccepted {
		t.Fatalf("code=%d", w.Code)
	}
	if len(pub.learns) != 1 || pub.learns[0] != "off" {
		t.Fatalf("learn sai: %v", pub.learns)
	}
}

func TestHealth(t *testing.T) {
	h := NewRouter(fakeSP{}, &fakePub{connected: true}, nil, nil)
	w := do(t, h, "GET", "/healthz", "")
	if w.Code != 200 {
		t.Fatalf("code=%d", w.Code)
	}
	var body map[string]any
	json.Unmarshal(w.Body.Bytes(), &body)
	if body["mqtt_connected"] != true {
		t.Fatalf("healthz phản ánh mqtt_connected sai: %v", body)
	}
}
