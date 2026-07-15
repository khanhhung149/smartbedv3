// Package api expose REST cho app Flutter + điều khiển tay.
package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/hung/home-backend/internal/config"
	"github.com/hung/home-backend/internal/statemachine"
	"github.com/hung/home-backend/internal/voice"
)

// StateProvider — state machine cung cấp snapshot (statemachine.Machine thỏa mãn).
type StateProvider interface {
	Snapshot() statemachine.Snapshot
}

// Publisher — MQTT client publish lệnh (mqttclient.Client thỏa mãn).
type Publisher interface {
	PublishACCmd(cmd string) error
	PublishACLearn(button string) error
	Connected() bool
}

type API struct {
	sp  StateProvider
	pub Publisher
}

func NewRouter(sp StateProvider, pub Publisher, hub *Hub) http.Handler {
	a := &API{sp: sp, pub: pub}
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)
	r.Use(corsMiddleware)

	// pub (Publisher) thỏa mãn voice.ACPublisher vì method set là superset (chỉ cần PublishACCmd).
	vc := config.LoadVoice()
	voiceHandler := voice.NewHandler(pub, voice.Config{
		ASRURL:     vc.ASRURL,
		SilenceMS:  vc.ASRSilenceMS,
		MaxUtterMS: vc.ASRMaxUtterMS,
		SampleRate: vc.SampleRate,
	})

	r.Get("/healthz", a.health)
	r.Route("/api", func(r chi.Router) {
		r.Get("/state", a.getState)
		r.Post("/ac", a.postAC)
		r.Post("/ac/learn", a.postACLearn)
		r.Get("/voice/stream", voiceHandler.ServeHTTP)
	})
	if hub != nil {
		r.Get("/ws", hub.serveWS(sp))
	}
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
