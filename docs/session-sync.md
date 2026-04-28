# Session Sync

> Cross-environment session state for Sleep Pad project. Updated via memory-sync skill.

## Last Export

**Date:** 2026-04-29
**Branch:** main @ `0acd92a`

---

## Session Summary (2026-04-22 → 2026-04-29)

End-to-end pipeline verified: ESP32 mock firmware → BLE provisioning → MQTT → FastAPI backend → Redis pubsub → WS → Flutter app on iPhone. Major polish pass on Flutter UI plus firmware/backend bug fixes. 3 commits pushed `94ca5f6 → e944a19 → 0acd92a`.

### Backend (`94ca5f6`)
- Sharing: `GET /share/pending` + auto-resolve invites by email on register
- Devices: `DELETE /devices/{id}` (owner-only, cascade FK) + MQTT retained `factory_reset` cmd
- New `app/mqtt/publisher.py` (one-shot aiomqtt for device commands)
- Subscriber: publish min-frame realtime to Redis (temp/movement/snore reach WS)
- Data: `HistoryRange.hour` + `temp` field (`AVG(temp)::real`) for Home sparkline preload
- Compose: `MQTT_DOMAIN: tcp://192.168.1.15:1883` override for dev (was `ws://...:9001` - PubSubClient doesn't speak ws)

### Firmware (`e944a19`)
- BLE: GATT max_handles 15→30 (was dropping DeviceId char silently)
- BLE: `ble_reset_pending_writes()` + `ble_user_cancelled()` for in-place retry
- main: `while(true)` provisioning retry loop keeps BLE alive across WiFi/MQTT attempts; granular status `wifi_connecting → wifi_connected → mqtt_connecting → connected`
- MQTT: subscribe `sleeppad/{id}/cmd`, `factory_reset` clears retained msg first → NVS erase → restart (was looping)
- MQTT: publish temp as `d.temp / 10.0` (actual °C) - backend Pydantic rejected raw 376
- Parser: use 2-byte length field as authoritative frame boundary, NOT `0x0D` (content bytes like `movement=13`/`sdata=13` triggered early termination)

### Flutter (`0acd92a`)
- **Home redesign:** compact StatusHero + 4 MetricCards (HR/RR/Temp + secondary grid). Movement shows count per protocol (not Low/Medium/High).
- **1h preload:** `initState` postFrameCallback fetches `historyProvider(hour)` → populates HR/RR/Temp sparklines + sets initial `_latest.temp` so card shows immediately
- **WS merge logic:** preserve min-only fields across sec frames so temp/movement/snore survive interleaved updates
- **Provisioning retry (Option C):** single-session BLE keeps connection across pair+writes+notify; `ProvisioningWifiFailedRetryable`/`MqttFailedRetryable` states with retry sheet; unlimited retries; disconnect = cancel; rewrite triggers reconnect
- iOS: skip `permission_handler`, let `flutter_blue_plus` trigger native CB prompt
- **Pending invites:** UI section with Accept/Decline tiles + auto-resolve on register
- **Delete device:** UI button → factory-reset remote via MQTT
- App bars: `topInset` for Dynamic Island overflow (5 screens fixed)
- Bottom nav: Material Icons + `main_shell.dart` for animated tab switching (no whole-screen slide)
- `alert_bell_button.dart`: red dot on unread + `lastSeen` tracking
- `DeviceLinkState` (renamed from `ConnectionState` - collided with Flutter's async.dart)
- Data models: fix WS field mapping (`heart_rate→hr`, `resp_rate→rr`, etc.) + `temp` field

---

## Key Decisions

- **Mock firmware mode** (`MOCK_SLEEPPAD` compile flag) is dev/sim-only; real LSM-800-TP integration deferred
- **Provisioning UX:** chose Option C (in-place retry + disconnect-cancel + rewrite-trigger + unlimited) over wipe-and-restart
- **iOS permissions:** `permission_handler` silently denies BLE on iOS - skip it, let native flow run
- **Parser:** length field is authoritative; `0x0D` is decoration only
- **Temp scaling:** firmware divides ×10 before publishing (avoids backend Pydantic `le=60` reject); DB stores actual °C
- **History ranges:** added `hour` for Home sparkline preload (1min buckets, 1h window)

---

## Pending / Next

- **History screen redesign** - was queued ("giờ tới screen history nha") but session paused before specifics. Likely additions: Temperature card chart, possibly Hour range tab.
- User confirmed VPN on Mac caused L2 isolation between Mac (192.168.1.15) and ESP32 (192.168.1.25); disconnect VPN to restore LAN MQTT connectivity.

---

## Infra / Config

- Mac dev IP: `192.168.1.15`
- ESP32 IP: `192.168.1.25` (DHCP)
- MQTT broker: `tcp://192.168.1.15:1883` (mosquitto in docker)
- Backend stack: postgres + timescale, redis, mosquitto, fastapi - all running healthy on 0.0.0.0
- Flutter app deployed: iPhone 17 Pro Max + iOS sim
- `.opencode/` added to `.gitignore`

---

## File Hotspots (changed this session)

Backend: `app/data/{models,service}.py`, `app/sharing/*`, `app/devices/{router,service}.py`, `app/mqtt/{publisher,subscriber}.py`, `app/auth/router.py`, `docker-compose.dev.yml`
Firmware: `src/{ble-provisioning,main,mqtt-client,uart-parser}.{cpp,h}`
Flutter: `lib/features/home/*`, `lib/features/devices/*`, `lib/shared/widgets/{metric_card,status_badge,app_bottom_nav,alert_bell_button,main_shell}.dart`, `lib/features/data/models/{realtime_data,history_response}.dart`

---

## Open Questions

- History screen scope: confirm with user whether to mirror Home's Temperature addition, add Hour range tab, or other changes.
- Real LSM-800-TP integration timeline: still deferred behind `MOCK_SLEEPPAD` flag.
