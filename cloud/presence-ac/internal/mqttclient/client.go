// Package mqttclient bọc paho MQTT: connect, subscribe room sensors, publish ac_cmd/ac_learn.
package mqttclient

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"

	"github.com/hung/home-backend/internal/events"
)

const (
	topicMotion   = "home/door/motion"
	topicPresence = "home/room/presence"
	topicSnore    = "home/room/snore_event"
	topicSample   = "home/room/sample"
	topicACCmd    = "home/room/ac_cmd"
	topicACLearn  = "home/room/ac_learn"
	topicACState  = "home/room/ac_state"
)

type Handlers struct {
	OnMotion   func(events.Motion)
	OnPresence func(events.Presence)
	// OnSnore — voice-node báo ngáy đã xác nhận. Tùy chọn: nil thì không subscribe.
	OnSnore func(events.SnoreEvent)
	// OnSample — mẫu 10Hz (schema CSV take-home + kênh raw radar). Tùy chọn: nil thì không subscribe.
	OnSample func(events.Sample)
	// OnACCmd — mọi lệnh AC đi qua bus, BẤT KỂ ai phát (app, voice, hay ESP32 sau này).
	// Backend không còn tự quyết định AC (ESP32 lo), nhưng lịch sử vẫn phải ghi được lệnh
	// đã xảy ra thật. Nghe topic thì bắt hết; ghi ở chỗ publish thì sót lệnh của người khác.
	OnACCmd func(cmd string)
	// OnACState — voice-node báo trạng thái điều hoà sau mỗi lần bắn IR. Nguồn duy nhất cho biết
	// nhiệt độ đang đặt là bao nhiêu; backend không tự suy ra được vì lệnh chỉ nói "tăng/giảm".
	OnACState func(power bool, temp int)
}

type Client struct {
	c mqtt.Client
}

func New(host string, port int, user, pass, clientID string, h Handlers) *Client {
	opts := mqtt.NewClientOptions()
	opts.AddBroker(fmt.Sprintf("tcp://%s:%d", host, port))
	opts.SetUsername(user)
	opts.SetPassword(pass)
	opts.SetClientID(clientID)
	opts.SetAutoReconnect(true)
	opts.SetConnectRetry(true)

	// Subscribe trong OnConnect -> tự re-subscribe sau reconnect (subscription mất khi rớt).
	opts.SetOnConnectHandler(func(c mqtt.Client) {
		slog.Info("mqtt connected")
		c.Subscribe(topicMotion, 1, func(_ mqtt.Client, msg mqtt.Message) {
			var m events.Motion
			if err := json.Unmarshal(msg.Payload(), &m); err != nil {
				slog.Warn("payload motion sai", "err", err, "raw", string(msg.Payload()))
				return
			}
			h.OnMotion(m)
		})
		c.Subscribe(topicPresence, 1, func(_ mqtt.Client, msg mqtt.Message) {
			var p events.Presence
			if err := json.Unmarshal(msg.Payload(), &p); err != nil {
				slog.Warn("payload presence sai", "err", err, "raw", string(msg.Payload()))
				return
			}
			h.OnPresence(p)
		})
		if h.OnSnore != nil {
			c.Subscribe(topicSnore, 1, func(_ mqtt.Client, msg mqtt.Message) {
				var s events.SnoreEvent
				if err := json.Unmarshal(msg.Payload(), &s); err != nil {
					slog.Warn("payload snore sai", "err", err, "raw", string(msg.Payload()))
					return
				}
				h.OnSnore(s)
			})
		}
		if h.OnSample != nil {
			c.Subscribe(topicSample, 1, func(_ mqtt.Client, msg mqtt.Message) {
				var sm events.Sample
				if err := json.Unmarshal(msg.Payload(), &sm); err != nil {
					slog.Warn("payload sample sai", "err", err, "raw", string(msg.Payload()))
					return
				}
				h.OnSample(sm)
			})
		}
		// Nghe chính lệnh AC để ghi lịch sử. Nil-check vì handler này tuỳ chọn.
		if h.OnACCmd != nil {
			c.Subscribe(topicACCmd, 1, func(_ mqtt.Client, msg mqtt.Message) {
				var a struct {
					Cmd string `json:"cmd"`
				}
				if err := json.Unmarshal(msg.Payload(), &a); err != nil || a.Cmd == "" {
					slog.Warn("payload ac_cmd sai", "raw", string(msg.Payload()))
					return
				}
				h.OnACCmd(a.Cmd)
			})
		}
		if h.OnACState != nil {
			c.Subscribe(topicACState, 1, func(_ mqtt.Client, msg mqtt.Message) {
				// Con trỏ để phân biệt "field vắng mặt" với "false/0". Payload thiếu field là
				// payload sai contract, không phải "điều hoà đang tắt ở 0 độ".
				var a struct {
					Power *bool `json:"power"`
					Temp  *int  `json:"temp"`
				}
				if err := json.Unmarshal(msg.Payload(), &a); err != nil || a.Power == nil || a.Temp == nil {
					slog.Warn("payload ac_state sai", "raw", string(msg.Payload()))
					return
				}
				h.OnACState(*a.Power, *a.Temp)
			})
		}
	})
	opts.SetConnectionLostHandler(func(_ mqtt.Client, err error) {
		slog.Warn("mqtt mất kết nối", "err", err)
	})

	return &Client{c: mqtt.NewClient(opts)}
}

// Connect thử kết nối, chờ tối đa timeout rồi trả về DÙ chưa xong — ConnectRetry
// vẫn retry ở nền. Không block khởi động khi broker chưa sẵn (HTTP vẫn lên được).
func (cl *Client) Connect(timeout time.Duration) {
	t := cl.c.Connect()
	if !t.WaitTimeout(timeout) {
		slog.Warn("mqtt chưa kết nối trong timeout, retry ở nền", "timeout", timeout)
		return
	}
	if err := t.Error(); err != nil {
		slog.Warn("mqtt connect lỗi, retry ở nền", "err", err)
	}
}

// publishTimeout — không để handler HTTP / caller treo nếu broker nửa vời (QoS1 chờ PUBACK).
const publishTimeout = 5 * time.Second

func (cl *Client) PublishACCmd(cmd string) error {
	payload := fmt.Sprintf(`{"cmd":%q}`, cmd)
	t := cl.c.Publish(topicACCmd, 1, false, payload)
	if !t.WaitTimeout(publishTimeout) {
		return fmt.Errorf("publish ac_cmd timeout sau %s", publishTimeout)
	}
	return t.Error()
}

// PublishACTemp gửi lệnh đổi nhiệt độ. Tách khỏi PublishACCmd vì lệnh này mang thêm số bước, mà
// PublishACCmd đang phục vụ POST /api/ac với payload {"cmd":"on"|"off"} — đổi chữ ký của nó sẽ kéo
// theo cả đường đó.
//
// dir là "temp_up" hoặc "temp_down"; steps là số bậc nhiệt độ. Cùng topic ac_cmd, retain=false —
// đây là LỆNH, retain lại sẽ khiến voice-node đổi nhiệt độ mỗi lần nó subscribe lại.
func (cl *Client) PublishACTemp(dir string, steps int) error {
	payload := fmt.Sprintf(`{"cmd":%q,"steps":%d}`, dir, steps)
	t := cl.c.Publish(topicACCmd, 1, false, payload)
	if !t.WaitTimeout(publishTimeout) {
		return fmt.Errorf("publish ac_cmd (temp) timeout sau %s", publishTimeout)
	}
	return t.Error()
}

func (cl *Client) PublishACLearn(button string) error {
	payload := fmt.Sprintf(`{"button":%q}`, button)
	t := cl.c.Publish(topicACLearn, 1, false, payload)
	if !t.WaitTimeout(publishTimeout) {
		return fmt.Errorf("publish ac_learn timeout sau %s", publishTimeout)
	}
	return t.Error()
}

// Connected phản ánh kết nối THẬT đang mở (IsConnected() báo true cả khi đang retry).
func (cl *Client) Connected() bool { return cl.c.IsConnectionOpen() }

func (cl *Client) Disconnect() { cl.c.Disconnect(250) }
