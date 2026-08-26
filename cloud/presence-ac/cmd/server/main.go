// Backend presence + AC — CHỈ HIỂN THỊ + chuyển tiếp lệnh tay.
//
// ESP32 (voice-node) là nơi DUY NHẤT quyết định bật/tắt AC tự động: nó tự gộp radar
// (qua ESP-NOW) + PIR rồi bắn IR ngay tại board. Backend KHÔNG tự publish ac_cmd nữa —
// nếu cả hai cùng quyết thì chúng lệch nhau theo thời gian và không ai biết tin bên nào.
//
// Backend vẫn giữ statemachine để nuôi /api/state + /api/ws cho app, ghi lịch sử event,
// và chuyển tiếp lệnh TAY: POST /api/ac và voice (whisper -> ParseVietCommand) -> ac_cmd.
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
	"github.com/hung/home-backend/internal/sessions"
	"github.com/hung/home-backend/internal/snore"
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

	// Ghi mẫu 10Hz (schema CSV take-home). Lỗi KHÔNG được làm hỏng luồng MQTT — log rồi thôi.
	recordSample := func(sm events.Sample) {
		if st == nil {
			return
		}
		if err := st.AppendSample(store.Sample{
			TS:            sm.TS,
			Presence:      sm.Presence,
			HRBpm:         sm.HRBpm,
			RespAmplitude: sm.RespAmplitude,
			Motion:        sm.Motion,
			WeightKg:      sm.WeightKg,
			Spo2:          sm.Spo2,
			TempC:         sm.TempC,
			Humidity:      sm.Humidity,
			MovingDistCm:  sm.MovingDistCm,
			MovingEnergy:  sm.MovingEnergy,
			StillDistCm:   sm.StillDistCm,
			StillEnergy:   sm.StillEnergy,
			UARTOK:        sm.UARTOK,
			Seq:           sm.Seq,
			Boot:          sm.Boot,
		}); err != nil {
			slog.Warn("ghi sample lỗi", "ts", sm.TS, "err", err)
		}
	}

	hub := api.NewHub()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Sleep sessions (TimescaleDB) — CHỈ ĐỌC. Bên ghi duy nhất là builder FastAPI
	// (cloud/sleeppad/app/sessions/). Trước đây cả hai cùng upsert lên khóa
	// (device_id, started_at) với tham số luật khác nhau, nên ended_at của phiên
	// đang mở lật giữa có giờ và NULL theo bên nào tick sau.
	// DB hỏng KHÔNG chặn khởi động: presence/AC/voice vẫn chạy, chỉ /api/sessions* trả 503.
	var pg *sessions.PGStore
	var sS api.SessionLister
	if cfg.PostgresURL != "" {
		if p, err := sessions.NewPGStore(ctx, cfg.PostgresURL); err != nil {
			slog.Warn("không mở được Postgres, /api/sessions* tắt", "err", err)
		} else {
			pg = p
			sS = pg
			defer pg.Close()
			slog.Info("sleep sessions", "pg", cfg.RedactedPostgresURL())
		}
	}

	var recordSnore func(events.SnoreEvent)
	var snoreReader api.SnoreCounter
	if pg != nil {
		if ss, err := snore.Open(pg.DB()); err != nil {
			slog.Warn("không mở được bảng ngáy, bỏ qua ghi ngáy", "err", err)
		} else {
			snoreReader = ss
			recordSnore = func(s events.SnoreEvent) {
				ms := int64(s.TS)
				ev := snore.Event{
					T:          time.Now().UTC(),
					DeviceMS:   &ms,
					Confidence: s.Confidence,
					DurationMS: int(s.DurationMS),
					Source:     "voice-node",
				}
				if err := ss.Append(context.Background(), ev); err != nil {
					slog.Warn("ghi ngáy lỗi", "err", err)
				}
			}
		}
	}

	var client *mqttclient.Client

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
				// KHÔNG publish ac_cmd nữa: ESP32 (voice-node) tự fusion radar+PIR và bắn IR.
				// Để cả hai cùng quyết định thì chúng lệch nhau theo thời gian và không ai biết
				// tin bên nào. Vẫn nuôi machine để /api/state + /api/ws có dữ liệu cho app.
				machine.OnMotion(m.TS, time.Now())
				broadcastIfChanged()
			},
			OnPresence: func(p events.Presence) {
				slog.Info("presence", "present", p.Present, "ts", p.TS)
				record(store.KindPresence, strconv.FormatBool(p.Present), "room-node", p.TS)
				machine.OnPresence(p.Present, p.TS, time.Now())
				broadcastIfChanged()
			},
			OnSnore: recordSnore,
			// Mẫu 10Hz ồn (10 mẫu/giây) nên KHÔNG bắn WS/broadcast — chỉ ghi DB.
			OnSample: recordSample,
			// Ghi lịch sử MỌI lệnh AC trên bus, bất kể ai phát (app, voice, ESP32).
			// UnixMilli chứ không Unix: contract quy định ts là epoch MILI-giây, motion và
			// presence từ firmware đều theo đó — trộn giây vào là app hiển thị lệch 1000 lần.
			OnACCmd: func(cmd string) {
				slog.Info("ac_cmd trên bus", "cmd", cmd)
				record(store.KindACCmd, cmd, "bus", time.Now().UnixMilli())
				// Trạng thái mong muốn phải bám theo lệnh THẬT trên bus, không chỉ
				// theo suy luận occupied. Thiếu bước này thì công tắc trong app luôn
				// nảy về chỗ cũ sau khi bấm (ac_desired không bao giờ đổi), người dùng
				// tưởng bấm hụt nên bấm lại nhiều lần.
				// CHỈ lệnh bật/tắt mới đổi trạng thái mong muốn. Lệnh nhiệt độ (temp_up/temp_down)
				// đi qua ĐÚNG topic này, nên viết `cmd == "on"` trần sẽ cho ra false và tắt
				// acDesired mỗi lần người dùng chỉnh nhiệt độ — công tắc trong app tự nảy về OFF
				// dù không ai bảo tắt.
				if cmd == "on" || cmd == "off" {
					machine.SetManual(cmd == "on")
				}
				broadcastIfChanged()
			},
			// Trạng thái thật do voice-node báo. Không ghi vào lịch sử event: đây là báo cáo lặp
			// lại sau mỗi lệnh, không phải sự kiện mới.
			OnACState: func(power bool, temp int) {
				slog.Info("ac_state", "power", power, "temp", temp)
				machine.SetACState(power, temp)
				broadcastIfChanged()
			},
		})

	client.Connect(5 * time.Second) // không block nếu broker chưa sẵn; retry ở nền
	defer client.Disconnect()

	// Retention mẫu: giữ 30 đêm gần nhất (theo mốc UTC nửa đêm), quét mỗi giờ.
	if st != nil {
		go func() {
			retainTicker := time.NewTicker(time.Hour)
			defer retainTicker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-retainTicker.C:
					if err := st.RetainNights(30); err != nil {
						slog.Warn("retention samples", "err", err)
					}
				}
			}
		}()
	}

	// HTTP API (Phase 3) — machine thỏa StateProvider, client thỏa Publisher.
	// ev/sl phải là interface nil THẬT khi không có store: gán thẳng con trỏ nil vào tham số
	// interface sẽ tạo interface non-nil (có type, không có value) → handler check nil hụt.
	var ev api.EventLister
	if st != nil {
		ev = st
	}
	var sl api.SampleLister
	if st != nil {
		sl = st
	}

	srv := &http.Server{Addr: cfg.HTTPAddr, Handler: api.NewRouterFull(machine, client, hub, ev, sl, sS, snoreReader)}
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
			machine.Tick(time.Now()) // chỉ cập nhật Snapshot cho app; không ra lệnh AC
			broadcastIfChanged()
		}
	}
}
