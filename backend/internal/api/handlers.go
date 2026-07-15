package api

import (
	"encoding/json"
	"net/http"
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func badRequest(w http.ResponseWriter, msg string) {
	writeJSON(w, http.StatusBadRequest, map[string]string{"error": msg})
}

// GET /healthz
func (a *API) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "ok",
		"mqtt_connected": a.pub.Connected(),
	})
}

// GET /api/state
func (a *API) getState(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, a.sp.Snapshot())
}

type acReq struct {
	Cmd string `json:"cmd"`
}

// POST /api/ac  {"cmd":"on"|"off"} — override tay, publish 1 lần; state machine vẫn tự điều khiển tiếp.
func (a *API) postAC(w http.ResponseWriter, r *http.Request) {
	var req acReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		badRequest(w, "JSON không hợp lệ")
		return
	}
	if req.Cmd != "on" && req.Cmd != "off" {
		badRequest(w, `cmd phải là "on" hoặc "off"`)
		return
	}
	if err := a.pub.PublishACCmd(req.Cmd); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "publish lỗi: " + err.Error()})
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"published": req.Cmd})
}

type learnReq struct {
	Button string `json:"button"`
}

// POST /api/ac/learn  {"button":"on"|"off"} — trigger room node vào chế độ học mã IR.
func (a *API) postACLearn(w http.ResponseWriter, r *http.Request) {
	var req learnReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		badRequest(w, "JSON không hợp lệ")
		return
	}
	if req.Button != "on" && req.Button != "off" {
		badRequest(w, `button phải là "on" hoặc "off"`)
		return
	}
	if err := a.pub.PublishACLearn(req.Button); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "publish lỗi: " + err.Error()})
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]string{"learn": req.Button})
}
