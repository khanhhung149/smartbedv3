---
type: brainstorm-report
slug: device-id-mac-derived
date: 2026-05-06
status: approved
---

# Device ID: MAC-derived per chip

## Problem
- `firmware/src/main.cpp:20`: `static const char* DEVICE_ID = "CNU2000001"` hardcoded → mọi ESP32 flashed cùng repo có cùng ID.
- DB `devices.id PRIMARY KEY` → first owner claim, second account nhận 409 "already paired".
- Mosquitto ACL `pattern write sleeppad/%c/*` với `%c=client_id=device_id` → 2 chips cùng ID race-condition publish overwrite.
- Symptom (5 May 2026): anh thời pair `CNU2000001` từ HN → user flash cùng ID ở SG → app lỗi "Device already paired to another account".

## Decisions (user-confirmed)
| Axis | Choice |
|---|---|
| ID source | Chip eFuse / MAC auto-derive |
| Format | `CNU` + 7 hex chars uppercase = 10 chars (giữ Legact V2 protocol compat) |
| Migration | Wipe row `CNU2000001`, anh thời's chip + new chip cùng tự-derive ID mới sau re-flash |
| Permissions | Owner-only (KISS, không thay đổi) |

## Verified constraints (Legact Pro V2 protocol PDF, pages 2 + 5)
- Sleep pad hardware **không validate** DEVICE_ID trong UART command frames — passthrough tag, ESP32 chọn tự do.
- Response frames (0x85/0x86/0x87) **không embed** DEVICE_ID — chỉ có 1-byte cyclic serial counter.
- → MAC-derive trên ESP32 không break sleep pad protocol.

## Implementation
**Firmware (~20 LOC, 1 file):**
```cpp
// main.cpp
static char DEVICE_ID[11];

static void derive_device_id() {
    uint64_t mac = ESP.getEfuseMac();
    snprintf(DEVICE_ID, sizeof(DEVICE_ID), "CNU%07llX", mac & 0xFFFFFFFULL);
}

void setup() {
    derive_device_id();
    Serial.printf("[Boot] device_id=%s\n", DEVICE_ID);
    // ... unchanged downstream — DEVICE_ID now per-chip
}
```

**Backend:** zero code change. Pair endpoint, ACL pattern, schema all already accept any 10-char ID.

**DB migration:** `DELETE FROM devices WHERE id='CNU2000001';` (cascade clears thresholds + alerts + shares).

**Anh thời's HN chip:** anh ấy `git pull && pio run -t upload` → chip tự derive ID mới → app pair lại bình thường.

## Trade-offs
- **Collision space:** 28 bits = 256M unique IDs. Birthday-50% ở ~16K chips. Sleep pad consumer scale < 100K → ~1% collision OK.
- **Future scale > 1M chips:** bump format (vd 10-char base32 = 50 bits) hoặc đổi sang full MAC hash. Out of scope cho v1.
- **Backward compat:** existing prod row `CNU2000001` bị wipe — anh thời mất threshold/alert config (chưa có nhiều, beta state).

## Validation
1. Flash 2 chips (ESP32 classic + ESP32-C3) → boot log show 2 different `CNU<7-hex>` IDs.
2. Pair từ 2 accounts khác nhau → cả 2 success, no 409.
3. MQTT subscriber log thấy 2 device_ids độc lập publish telemetry.

## Unresolved
None — protocol PDF resolved last open question.
