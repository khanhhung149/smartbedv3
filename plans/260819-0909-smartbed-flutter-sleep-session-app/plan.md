---
type: plan
date: 2026-08-19 09:09
slug: smartbed-flutter-sleep-session-app
status: in-progress
priority: P1
branch: master
brainstorm: plans/reports/brainstorm-to-planner-260819-0909-smartbed-flutter-sleep-session-app-report.md
repos: [smartbedv3, sleep_pad_AI]
blockedBy: []
blocks: []
---

# App Flutter SmartBed — vòng 1: báo cáo giấc ngủ

App Flutter riêng ở `smartbedv3/app/`, nuôi bằng dữ liệu thật từ backend `sleep_pad_AI`.
Backend thêm khái niệm **phiên ngủ** (`sleep_sessions`) + 3 endpoint.

**Nguồn:** [`brainstorm report`](../reports/brainstorm-to-planner-260819-0909-smartbed-flutter-sleep-session-app-report.md)

## Bối cảnh 1 đoạn

Plan `260713-1019-smartbed-v3-mvp` đặt app ở Phase 06, phụ thuộc Phase 02–05 — **cả 8 phase đều chưa bắt đầu**, smartbedv3 chưa sinh ra dữ liệu nào được lưu. Nhưng `phase-02` ("sleep tracker phi tiếp xúc dạng tấm dưới nệm") về mặt dữ liệu **đã tồn tại** ở repo `sleep_pad_AI`, đang chạy thật. Vòng này dựng app trên dữ liệu đó.

## Quyết định đã khoá

| # | Quyết định | Vì sao |
|---|---|---|
| 1 | App mới ở `smartbedv3/app/`, không fork app sleep_pad | Hưng chốt. Chi phí viết lại đã được nêu và Hưng giữ quyết định |
| 2 | Backend = FastAPI `sleep_pad_AI`, **không phải K8s** | Cầu tạm. **Không đảo ngược quyết định K8s của Michael** — ghi vào docs |
| 3 | Luật phiên chạy **server-side**, không trong Dart | Viết một lần, có test, mọi client cho cùng kết quả |
| 4 | Trục thời gian truy vấn = cột `time` | **Sửa ở Session 2:** `time` **đã là** giờ ingest do backend đóng dấu (`subscriber.py:108`), không phải giờ thiết bị. `ts` của pad bị vứt, không lưu ở đâu |
| 5 | `received_at` là cột **nullable, ghi nhưng không query** | **Sửa ở Session 2:** đo bằng `EXPLAIN` — `COALESCE(received_at, time)` mất index range scan và phá chunk exclusion của Timescale (quét mọi chunk thay vì 1). Giữ cột để dành cho lúc sửa firmware `0x0B` |
| 6 | **Không** bảng `session_events` riêng | Đếm tổng ở `sleep_sessions`; `/timeline` suy sự kiện từ `sec_data.status` |
| 7 | Seed script ghi **thẳng DB**, không qua MQTT | Vòng này nghiệm thu luật phiên, không nghiệm thu ingest (ingest đã chạy thật) |
| 8 | **Chỉ dev/local**, không đụng prod `api.sleeptech.me` | Hưng chốt. Viết sẵn file migration, chưa chạy lên prod |
| 9 | Backend làm trên branch mới tách từ `dev/khanhhung` | Tránh `feat/ws-user-combined` — plan `260802-2203` đang dở ở đó |
| 10 | Auth = **dev token** (JWT curl, hạn 30 ngày) trong config app | Không sửa backend, không đục lỗ auth. UI auth ở pha sau |
| 11 | Không có UI điều khiển | Hưng: "chỉ có mỗi sensor và pipeline thôi chưa có giường thật" |
| 12 | Bootstrap **pytest tối thiểu** (chỉ `requirements-dev.txt` + 1 file test thuần) | Validate F-01: repo không có pytest ở đâu. `rules.py` là hàm thuần → không cần conftest/fixture docker, không đụng harness của plan `260802-2203` |
| 13 | Áp schema bằng `scripts/apply-schema.sh`, không dùng `initdb.d` | Validate F-02: compose chỉ mount `init.sql`; `initdb.d` chỉ chạy khi volume rỗng. Script vá luôn lỗ hổng đang có với `smart_watch_data.sql` |
| 14 | `seed-night.py` chạy **trong container `fastapi`** | Validate F-03: `backend/scripts/` là thư mục shell, host chưa có môi trường Python sẵn. Container đã có đủ thư viện DB và `DATABASE_URL` |

## Luật phiên ngủ — lấy từ PDF giao thức, không tự nghĩ

Nguồn: `/mnt/d/sleep_pad_AI/Legact Pro_V2 data transfer protocol en20230130_1.pdf`

```
on_bed      := hr > 0 OR rr > 0              # tr.4 §2.4.1: hr/rr = 0 khi rời giường
mở phiên    := on_bed liên tục >= 30 GIÂY     # tr.2, đúng số của nhà sản xuất
đóng phiên  := NOT on_bed liên tục >= 30 PHÚT, hoặc chạm trần 1440 phút
tóm tắt     := AVG(hr) FILTER (WHERE hr > 0)  # tr.4 §2.4.1, BẮT BUỘC
```

`status` **không phải** trạng thái trên/rời giường mà là **mã sự kiện** của giây đó (tr.4 §2.4.1):
`01` rời giường · `02` cử động · `03` ngồi dậy · `04` ngủ · `05` tỉnh · `06` vật nặng · `07` ngáy · `08` thở yếu.
Không tồn tại mã "đang nằm trên giường" → không được viết `WHERE status = ...`.

## Phases

| # | File | Repo | Nội dung | Ưu tiên | Phụ thuộc | Trạng thái |
|---|------|------|----------|---------|-----------|------------|
| 01 | [phase-01-backend-schema-received-at.md](phase-01-backend-schema-received-at.md) | sleep_pad_AI | Schema `sleep_sessions` + cột `received_at` + ghi lúc ingest | P1 | — | done |
| 02 | [phase-02-backend-session-builder.md](phase-02-backend-session-builder.md) | sleep_pad_AI | Máy trạng thái dựng phiên + unit test | P1 | 01 | done |
| 03 | [phase-03-backend-api-va-seed.md](phase-03-backend-api-va-seed.md) | sleep_pad_AI + smartbedv3 | `/sessions`, `/timeline`, seed script, file hợp đồng API | P1 | 02 | done |
| 04 | [phase-04-app-scaffold-va-tang-du-lieu.md](phase-04-app-scaffold-va-tang-du-lieu.md) | smartbedv3 | Scaffold Flutter, core, repository, cache sqflite | P2 | 03 | done |
| 05 | [phase-05-app-man-hinh-danh-sach-phien.md](phase-05-app-man-hinh-danh-sach-phien.md) | smartbedv3 | Màn hình danh sách phiên + tóm tắt | P2 | 04 | done |
| 06 | [phase-06-app-chi-tiet-phien.md](phase-06-app-chi-tiet-phien.md) | smartbedv3 | Chi tiết phiên + biểu đồ timeline | P2 | 05 | done |
| 07 | [phase-07-nghiem-thu.md](phase-07-nghiem-thu.md) | cả hai | Chạy 5 tiêu chí nghiệm thu | P2 | 06 | 4/5 đạt · 1 treo (mắt người) |

## Tiêu chí nghiệm thu (toàn plan)

- [x] Seed một đêm → `GET /sessions` trả **đúng 1 phiên** — 1 phiên, 15:00:00 → 22:59:59, 28 799s
- [x] Seed nửa đêm `hr=0` → `hr_avg` **không** tụt — 63.74, trùng khít trung bình nửa đầu của đêm đối chứng
- [x] Ngoại tuyến vẫn mở được phiên đã tải — 1 phiên + 480 điểm đọc lại từ cache sqflite thật, `isStale=true`
- [ ] Layout không vỡ ở **360dp** và **800dp** — widget test đạt (bắt được 2 lỗi tràn thật, đã sửa); **chưa nhìn bằng mắt**
- [x] Mọi chỉ số gắn nhãn **"tham khảo, không dùng chẩn đoán"** — 1 nơi định nghĩa, 2 màn hình render

Kết quả chi tiết: [`reports/nghiem-thu-vong-1.md`](reports/nghiem-thu-vong-1.md)

## Ngoài phạm vi

Điều khiển tư thế · môi trường · template · capability manifest §5 · K8s cloud · pose/camera · gộp presence + AC · UI auth/OTP · chia sẻ · BLE pairing · FCM · realtime WebSocket · build iOS · firmware `0x0B`/`0x13`/`0x14` · deploy prod.

## Rủi ro

| # | Rủi ro | Giảm thiểu |
|---|---|---|
| R1 | `on_bed := hr>0 OR rr>0` là **suy luận** — PDF nói `0` cũng nghĩa "không tính được" | Ngưỡng nằm trong config, không hardcode. Kiểm bằng đêm thật trước khi coi là chân lý |
| R2 | `ts` của pad không tin được: firmware `mqtt-client.cpp:296` forward nguyên, `main.cpp` chưa từng gửi `0x0B` | **Đã trung hoà sẵn:** `subscriber.py:108` ghi `now()` vào `time` và vứt `ts`. `to_timestamptz()` ở `parser.py:58` là code chết (0 caller). Query dùng `time`. Rủi ro còn lại chỉ ở firmware — sửa `0x0B` ở pha sau |
| R3 | Backend FastAPI ≠ K8s mà Michael đã chốt | Ghi rõ trong `smartbedv3/docs/` là cầu tạm. **Không sửa `phase-06` của plan MVP** |
| R4 | Coupling 2 repo, không CI chung | File hợp đồng API ở `smartbedv3/docs/`, sửa cùng lúc với endpoint (Phase 03) |
| R5 | Dev token hết hạn sau 30 ngày | App bắt 401 và hiện thông báo rõ, không im lặng |
| R6 | Branch `feat/ws-user-combined` của plan `260802-2203` đang sửa `data/router.py` | Module `sessions/` là thư mục mới, không đụng `data/router.py`. Tách branch từ `dev/khanhhung` |
| R7 | Wellness device, cấm claim y tế | Nhãn "tham khảo, không dùng chẩn đoán" là tiêu chí nghiệm thu, không phải tuỳ chọn |

## Câu hỏi chưa giải quyết

1. Ngưỡng `on_bed` có đúng không — chỉ trả lời được bằng một đêm dữ liệu thật.
2. `sec_data`/`min_data` hiện lưu `ts` sai bao nhiêu? Chưa đo trên thiết bị thật.
3. Bao giờ đọc `0x13`/`0x14` — hypnogram Deep/Light/REM + AHI có sẵn trong phần cứng, đang bỏ phí.
4. `persons`/`person_sources` (gộp nhiều nguồn về một người) hoãn — sẽ cần khi thêm presence.


---

## Validation Log

### Session 1 — 2026-08-19

**Tier:** Full (7 phases → cả 4 role: Fact Checker, Flow Tracer, Scope Auditor, Contract Verifier)

#### Verification Results
- Claims checked: **20**
- Verified: **16** | Failed: **3** | Contract gap: **1**

**VERIFIED (trích dẫn):**

| Claim | Bằng chứng |
|---|---|
| `devices(id)` FK dùng được | `backend/postgres/init.sql:75,91,107` |
| `gen_random_uuid()` khả dụng | `init.sql:5` `CREATE EXTENSION pgcrypto` |
| `_insert_sec` / `_insert_min` đúng shape | `app/mqtt/subscriber.py:172,183` |
| Khuôn task nền | `app/alerts/engine.py` `run_alert_engine(pool, rds, stop)` |
| Task wire trong lifespan | `app/main.py:55` `alerts_task` |
| Kiểm quyền device | `app/data/service.py:17` `user_can_access_device` |
| Whitelist hằng số cho SQL | `app/data/service.py:212` `_RANGE_PARAMS` |
| Login trả `access_token` | `app/auth/models.py:24` `class Token` |
| **Router KHÔNG có prefix** | `app/main.py:99-105` — endpoint trần, `/sessions` chứ không `/api/sessions` |
| `history` thiếu movement/snore | `app/data/service.py:214-228` |
| `sync` có đủ trường | `app/data/service.py:238-257` |
| Flutter 3.44.6 / Dart 3.12.2 | `flutter --version` |
| `ts` forward nguyên | `firmware/src/mqtt-client.cpp:296` |
| Firmware chỉ gửi `0x04`/`0x08` | `firmware/src/main.cpp:53-57` |
| Backend hiểu `ts` là epoch UTC | `app/mqtt/parser.py` `to_timestamptz` |
| Luật phiên 30s/30phút/1440 | PDF Legact tr.2 |

**FAILED → đã sửa:**

| # | Sai gì | Bằng chứng | Quyết định |
|---|---|---|---|
| F-01 | Plan giả định có pytest | `app/requirements.txt` không có pytest; không có `pytest.ini`/`pyproject.toml`/`setup.cfg`; không file `test_*.py`/`conftest.py` nào | Bootstrap `requirements-dev.txt` chỉ với `pytest` + 1 file test thuần. Không conftest, không fixture docker → không đụng harness của plan `260802-2203` (branch `feat/ws-user-combined`) |
| F-02 | Plan bảo thêm `\i` vào `init.sql` | `docker-compose.yml:21` chỉ mount `init.sql`. `smart_watch_data.sql` **không được mount và không có gì trong repo tham chiếu** — cơ chế áp schema phụ không tồn tại. `initdb.d` chỉ chạy khi volume rỗng | Viết `backend/scripts/apply-schema.sh` (idempotent, dùng `docker exec`), vá luôn lỗ hổng của `smart_watch_data.sql`, ghi vào `backend/README.md` |
| F-03 | `seed-night.py` đặt ở `backend/scripts/` chạy từ host | Thư mục đó chỉ có `setup-mosquitto-passwords.sh` — quy ước shell; host chưa có môi trường Python sẵn | Chạy trong container `fastapi` qua `docker compose exec`; thêm mount `./scripts:/app/scripts:ro` |

**Contract gap → đã sửa:** thêm task vào `lifespan` mà không thêm vào list của `_stop_tasks` (`app/main.py:63`) thì task không bị huỷ lúc shutdown. Bổ sung vào Phase 02 bước 5 + một tiêu chí nghiệm thu.

#### Phase propagation

| File | Thay đổi |
|---|---|
| `phase-01` | `init.sql \i` → `apply-schema.sh`; bỏ tiêu chí `pytest`; thêm bước ghi `backend/README.md` |
| `phase-02` | Thêm bước 0 bootstrap pytest; `_stop_tasks` vào Related Files + bước 5 + tiêu chí |
| `phase-03` | `seed-night.py` chạy trong container; thêm mount compose |
| `phase-07` | Lệnh dựng hệ dùng `apply-schema.sh`; seed qua `docker compose exec`; thêm bước chạy `pytest` |

#### Whole-Plan Consistency Sweep
- Grep toàn plan cho lệnh cũ (`python scripts/seed-night`, redirect trực tiếp `sleep_sessions.sql`, `thêm \i`) → **0 kết quả còn sót**
- Quyết định #12–14 khớp với nội dung phase 01/02/03/07
- Sở hữu file không chồng chéo: `app/README.md` → Phase 04; `backend/README.md` → Phase 01; `docker-compose.dev.yml` → Phase 03
- **Unresolved contradictions: 0**

### Session 2 — 2026-08-19 (phát hiện lúc thực thi Phase 01)

**F-04 — tiền đề của Quyết định #4/#5 sai với code hiện tại.**

| Plan nói | Đo được |
|---|---|
| `parser.py` hiểu `ts` là epoch UTC → `time` = giờ thiết bị | `to_timestamptz()` (`parser.py:58`) **0 caller** trong toàn `app/` — code chết |
| `received_at` là trục thật, khác `time` | `subscriber.py:108` `now = datetime.now(tz=utc)` → `time` **đã là** giờ ingest. Bản ghi MQTT test: `time` và `received_at` lệch **210 µs** |
| `COALESCE(received_at, time)` để đọc dữ liệu cũ | `EXPLAIN` trên `sec_data` (17 584 dòng, 2 chunk): bản `time` → Index Only Scan, **1 chunk**. Bản `COALESCE` → Seq Scan + **quét cả 2 chunk**, mất chunk exclusion |

**Quyết định (Hưng chốt, phương án A):** SQL của Phase 02/03 truy vấn trên `time`. Cột `received_at` vẫn tạo và vẫn ghi lúc ingest, nhưng **không đọc** — để dành cho lúc sửa firmware gửi `0x0B`, khi đó `time` có thể đổi nghĩa và `received_at` là trục liên tục duy nhất còn lại.

**Lan truyền:** Quyết định #4, #5, R2 ở trên; SQL trong `phase-02` và `phase-03`; bảng lý do trong `phase-01`.

### Session 3 — 2026-08-19 (thực thi Phase 02–03)

**F-05 — SQL trong plan sai cú pháp.** Plan viết `AVG(heart_rate)::real FILTER (WHERE heart_rate > 0)`.
Postgres từ chối: `syntax error at or near "FILTER"` — cast phải bọc ngoài toàn bộ biểu thức tổng hợp.
Đúng: `(AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real`. Đã sửa ở `sessions/service.py`
(cả `_summarize` và `get_timeline`); mẫu SQL trong `phase-02`/`phase-03` cũng đã sửa theo.

**F-06 — luật phiên thiếu một trường hợp.** `build_sessions` không đóng phiên khi dữ liệu
**ngừng hẳn** lúc đang trên giường (pad rút điện buổi sáng): không có dòng `off_bed` nào để
đếm 30 phút, nên phiên treo mở vĩnh viễn và app hiện một đêm không có giờ kết thúc.
Bổ sung tham số `now`: im lặng quá `session_close_seconds` thì đóng phiên **tại mẫu cuối cùng**
— thời điểm cuối cùng có bằng chứng người còn trên giường. Thêm 2 unit test.

**F-07 — seed script che mất mã sự kiện.** Nhánh `i % 900` (cử động) đứng trước
`i % 7200` (ngồi dậy) và `i % 5400` (tỉnh); cả hai số đều chia hết cho 900 nên hai mã hiếm
không bao giờ được sinh → `sit_up_count = wake_count = 0`. Đảo thứ tự: mã hiếm kiểm trước.

**Cải tiến ngoài plan:** `seed-night.py` thêm `--owner-email`. Trước đó script gán device cho
"user cũ nhất trong DB" — ngầm và sai lệch trên bất kỳ DB nào không phải mới tinh.

### Session 4 — 2026-08-19 (redesign UI theo yêu cầu user)

**Nhiệm vụ user:** nâng UI lên chuyên nghiệp, dễ nhìn, có biểu đồ phân tích, kèm visual design
decisions, interaction patterns, và UX quality control.

**Đã làm (11 file UI + theme):**

| File | Thay đổi |
|---|---|
| `app/lib/core/app_theme.dart` | `MetricColors` (semantic màu theo chỉ số: heart/breath/movement/snore/respDisorder), surface tối phân tầng, tabular figures, border thẻ, chip/divider/appBar |
| `app/lib/features/sessions/widgets/metric_tile.dart` | icon + màu tint, `Fmt` helper, `MetricIdentity` |
| `app/lib/features/sessions/widgets/session_card.dart` | pill thời lượng, lưới metric 2 cột |
| `app/lib/features/sessions/sessions_screen.dart` | `_SectionHeader` + badge đếm, Wrap 2–3 cột |
| `app/lib/features/session_detail/widgets/summary_header.dart` | hero thời lượng + `_HeartRateStrip` min→max fill + tick avg |
| `app/lib/features/session_detail/widgets/timeline_chart.dart` | tooltip khi chạm (giờ + giá trị), gradient area dưới đường, 4 nhãn trục giờ, tooltip cột |
| `app/lib/features/session_detail/widgets/bed_state_band.dart` | icon + legend, band 20px, ô gap phân biệt |
| `app/lib/features/session_detail/widgets/event_markers.dart` | nhóm sự kiện theo loại ("label · N lần") |
| `app/lib/features/session_detail/session_detail_screen.dart` | layer mang icon/màu từ `MetricIdentity`, hint "Chạm vào biểu đồ..." |
| `app/lib/features/sessions/widgets/empty_state.dart`, `stale_data_banner.dart` | chỉnh surface/tone |

**Lỗi bị widget test bắt và đã sửa:** `MetricTile` value Row tràn 5.8px ở 136–161px (bọc
`Flexible` + ellipsis); header summary tràn 88px (bọc `Flexible`); dòng nhãn `_HeartRateStrip`
tràn 75px (đổi `spaceBetween` → `Expanded` + ellipsis).

**Kiểm chứng:** `flutter analyze` sạch; `flutter test` 19/19 pass (giữ ràng buộc 360/800dp,
không cuộn ngang, đúng 1 em-dash + 1 số 0 khi null). Web release build chụp qua Chromium
(`reports/evidence/ui-*.png`): cả 4 màn (list/detail × 360/800) `scrollWidth == clientWidth`,
không sọc overflow. Pixel vàng rà được là màu icon cử động, không phải overflow.

**Bổ sung 3 test cho tiêu chí phase chưa có phủ test (Session 5):**

| Tiêu chí | Test mới |
|---|---|
| Phase 05 "kéo để làm mới gọi lại API" | `sessions_screen_test.dart` — `pull to refresh re-runs the sessions provider` (fling + đếm số lần provider chạy) |
| Phase 06 "dải trên/rời giường khớp `bed_state` API" | `session_detail_screen_test.dart` — `the bed band paints on/off exactly as bed_state says` (30 ô on + 10 ô off + 30 ô on, đếm màu cell trong ClipRRect của band) |
| Phase 06 "sự kiện ngáy/ngồi dậy hiện đúng vị trí" | `session_detail_screen_test.dart` — `event markers list the right events at the right clock times` (gộp "Ngồi dậy · 1 lần", "Ngáy · 2 lần", khớp giờ địa phương; scope vào cây `EventMarkers` để không trùng nhãn trục chart) |

Tổng test Flutter: **22/22 pass**.

**Thay đổi ngoài phạm vi đã làm** (theo đúng yêu cầu UI/UX của user): các chỉnh sửa thuần giao
diện ở trên — không đụng tầng dữ liệu, API, hay logic phiên.
