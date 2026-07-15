// Package events định nghĩa payload MQTT theo contract firmware/mqtt/README.md.
package events

// Motion — home/door/motion
type Motion struct {
	TS     int64 `json:"ts"`
	Motion bool  `json:"motion"`
}

// Presence — home/room/presence
type Presence struct {
	TS      int64 `json:"ts"`
	Present bool  `json:"present"`
}
