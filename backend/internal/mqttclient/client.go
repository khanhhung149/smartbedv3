// Package mqttclient bọc paho MQTT: connect, subscribe motion+presence, publish ac_cmd/ac_learn.
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
	topicMotion  = "home/door/motion"
	topicPresence = "home/room/presence"
	topicACCmd   = "home/room/ac_cmd"
	topicACLearn = "home/room/ac_learn"
)

type Handlers struct {
	OnMotion   func(events.Motion)
	OnPresence func(events.Presence)
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
