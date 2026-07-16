// Backend presence + AC control.
// Phase 1-2: connect MQTT, subscribe motion+presence, state machine vào/ra, publish ac_cmd.
// REST API (Phase 3) + WebSocket (Phase 4) sẽ bổ sung sau.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/hung/home-backend/internal/api"
	"github.com/hung/home-backend/internal/config"
	"github.com/hung/home-backend/internal/events"
	"github.com/hung/home-backend/internal/mqttclient"
	"github.com/hung/home-backend/internal/statemachine"
	"github.com/hung/home-backend/internal/store"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}

	machine := statemachine.New(statemachine.Config{
		EnterWindow: cfg.EnterWindow,
		ExitTimeout: cfg.ExitTimeout,
	})

	// Lịch sử event. DB hỏng KHÔNG chặn khởi động: presence/AC/voice vẫn phải chạy,
	// chỉ mất /api/events (trả 503). Đây là tính năng phụ, không phải đường sống của hệ.
	var st *store.Store
	if cfg.DBPath != "" {
		var err error
		if st, err = store.Open(cfg.DBPath); err != nil {
			slog.Warn("không mở được DB lịch sử, chạy tiếp không có lịch sử", "path", cfg.DBPath, "err", err)
			st = nil
		} else {
			slog.Info("lịch sử event", "db", cfg.DBPath)
			defer st.Close()
		}
	}
	// record ghi 1 event, nuốt lỗi thành log — không được làm hỏng luồng MQTT.
	record := func(kind, value, source string, ts int64) {
		if st == nil {
			return
		}
		if err := st.Append(store.Event{TS: ts, Kind: kind, Value: value, Source: source}); err != nil {
			slog.Warn("ghi lịch sử lỗi", "kind", kind, "err", err)
		}
	}

	hub := api.NewHub()

	var client *mqttclient.Client
	publish := func(cmd *string) {
		if cmd == nil {
			return
		}
		if err := client.PublishACCmd(*cmd); err != nil {
			slog.Warn("publish ac_cmd lỗi", "err", err)
			return
		}
		slog.Info("published ac_cmd", "cmd", *cmd)
		record(store.KindACCmd, *cmd, "backend", time.Now().Unix())
	}

	// Push snapshot lên WS khi bất kỳ trường nào đổi (Snapshot comparable).
	var snapMu sync.Mutex
	var lastSnap statemachine.Snapshot
	broadcastIfChanged := func() {
		snap := machine.Snapshot()
		snapMu.Lock()
		changed := snap != lastSnap
		lastSnap = snap
		snapMu.Unlock()
		if changed {
			hub.Broadcast(snap)
		}
	}

	client = mqttclient.New(cfg.MQTTHost, cfg.MQTTPort, cfg.MQTTUser, cfg.MQTTPass, cfg.MQTTClientID,
		mqttclient.Handlers{
			OnMotion: func(m events.Motion) {
				slog.Info("motion", "ts", m.TS)
				record(store.KindMotion, strconv.FormatBool(m.Motion), "voice-node", m.TS)
				publish(machine.OnMotion(m.TS, time.Now()))
				broadcastIfChanged()
			},
			OnPresence: func(p events.Presence) {
				slog.Info("presence", "present", p.Present, "ts", p.TS)
				record(store.KindPresence, strconv.FormatBool(p.Present), "room-node", p.TS)
				publish(machine.OnPresence(p.Present, p.TS, time.Now()))
				broadcastIfChanged()
			},
		})

	client.Connect(5 * time.Second) // không block nếu broker chưa sẵn; retry ở nền
	defer client.Disconnect()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// HTTP API (Phase 3) — machine thỏa StateProvider, client thỏa Publisher.
	// ev phải là interface nil THẬT khi không có store: gán thẳng con trỏ nil vào tham số
	// interface sẽ tạo interface non-nil (có type, không có value) → handler check nil hụt.
	var ev api.EventLister
	if st != nil {
		ev = st
	}
	srv := &http.Server{Addr: cfg.HTTPAddr, Handler: api.NewRouter(machine, client, hub, ev)}
	go func() {
		slog.Info("HTTP API", "addr", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("http server", "err", err)
		}
	}()

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	slog.Info("backend chạy", "enter_window", cfg.EnterWindow, "exit_timeout", cfg.ExitTimeout)
	for {
		select {
		case <-ctx.Done():
			slog.Info("đang tắt")
			shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			_ = srv.Shutdown(shutCtx)
			cancel()
			return
		case <-ticker.C:
			publish(machine.Tick(time.Now()))
			broadcastIfChanged()
		}
	}
}
