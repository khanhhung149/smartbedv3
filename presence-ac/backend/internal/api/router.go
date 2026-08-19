// Package api expose REST cho app Flutter + điều khiển tay.
package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/hung/home-backend/internal/config"
	"github.com/hung/home-backend/internal/statemachine"
	"github.com/hung/home-backend/internal/store"
	"github.com/hung/home-backend/internal/voice"
)

// StateProvider — state machine cung cấp snapshot (statemachine.Machine thỏa mãn).
type StateProvider interface {
	Snapshot() statemachine.Snapshot
}

// Publisher — MQTT client publish lệnh (mqttclient.Client thỏa mãn).
type Publisher interface {
	PublishACCmd(cmd string) error
	PublishACTemp(dir string, steps int) error
	PublishACLearn(button string) error
	Connected() bool
}

// EventLister — nguồn lịch sử event cho GET /api/events (store.Store thỏa mãn).
// Cho phép nil: khi không cấu hình được DB, backend vẫn chạy và /api/events trả 503
// thay vì chết hẳn — presence/AC/voice không phụ thuộc lịch sử.
type EventLister interface {
	List(limit int, before int64) ([]store.Event, error)
}

// SampleLister — nguồn mẫu 10Hz cho GET /api/samples (dashboard "xem lại một đêm").
type SampleLister interface {
	SamplesBetween(fromMs, toMs int64) ([]store.Sample, error)
}

type API struct {
	sp  StateProvider
	pub Publisher
	ev  EventLister
	sl  SampleLister
	sS  SessionLister
}

func NewRouter(sp StateProvider, pub Publisher, hub *Hub, ev EventLister) http.Handler {
	return NewRouterSamples(sp, pub, hub, ev, nil)
}

// NewRouterSamples giống NewRouter + thêm nguồn mẫu 10Hz (dashboard Phase 01).
// sl=nil thì /api/samples trả 503 thay vì chết.
func NewRouterSamples(sp StateProvider, pub Publisher, hub *Hub, ev EventLister, sl SampleLister) http.Handler {
	return NewRouterFull(sp, pub, hub, ev, sl, nil)
}

// NewRouterFull là điểm đăng ký đầy đủ: samples + sleep sessions. sS=nil thì
// các endpoint /api/sessions* trả 503 thay vì chết — radar/AC không phụ thuộc.
func NewRouterFull(sp StateProvider, pub Publisher, hub *Hub, ev EventLister, sl SampleLister, sS SessionLister) http.Handler {
	a := &API{sp: sp, pub: pub, ev: ev, sl: sl, sS: sS}
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)
	r.Use(corsMiddleware)

	// Dashboard local web (Phase 01): /dashboard — xem realtime + xem lại một đêm.
	// Serve HTML trực tiếp từ embed để backend tự chứa dashboard, không cần copy tài nguyên.
	dash, err := dashboardFS()
	if err != nil {
		panic(err) // embed hỏng là bug build, fail sớm
	}
	r.Handle("/dashboard/*", http.StripPrefix("/dashboard/", http.FileServer(http.FS(dash))))
	r.Get("/dashboard", http.RedirectHandler("/dashboard/", http.StatusFound).ServeHTTP)

	// pub (Publisher) thỏa mãn voice.ACPublisher vì method set là superset (chỉ cần PublishACCmd).
	vc := config.LoadVoice()
	voiceHandler := voice.NewHandler(pub, voice.Config{
		ASRURL:     vc.ASRURL,
		SilenceMS:  vc.ASRSilenceMS,
		MaxUtterMS: vc.ASRMaxUtterMS,
		MinUtterMS: vc.ASRMinUtterMS,
		SampleRate: vc.SampleRate,
	})

	r.Get("/healthz", a.health)
	r.Route("/api", func(r chi.Router) {
		r.Get("/state", a.getState)
		r.Get("/events", a.getEvents)
		r.Get("/samples", a.getSamples)
		r.Post("/ac", a.postAC)
		r.Post("/ac/learn", a.postACLearn)
		r.Get("/sessions", a.listSessions)
		r.Get("/sessions/{id}", a.getSession)
		r.Get("/sessions/{id}/timeline", a.getTimeline)
		r.Get("/voice/stream", voiceHandler.ServeHTTP)
		// Chỉ đăng ký khi VOICE_RECORD_DIR được set — công cụ thu dữ liệu huấn luyện, không nên
		// tồn tại trong bản chạy thường (xem voice/record.go).
		if rec := voice.NewRecordHandler(vc.RecordDir, vc.RecordSegmentS, vc.SampleRate); rec != nil {
			r.Get("/voice/record", rec.ServeHTTP)
		}
		// WS state phải nằm TRONG /api cho khớp docs + app + mọi endpoint khác.
		// Trước đây nó đăng ký ở gốc ("/ws") nên app gọi /api/ws bị 404 và mất realtime
		// im lặng — REST vẫn chạy nên bug ẩn rất kỹ.
		if hub != nil {
			r.Get("/ws", hub.serveWS(sp))
		}
	})
	return r
}

// corsMiddleware — CORS mở cho app LAN (MVP). Siết lại nếu mở ra internet.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
