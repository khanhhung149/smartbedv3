---
type: brainstorm-report
slug: ws-user-stabilization
date: 2026-08-02
status: approved
branch: feat/ws-user-combined
supersedes: none
related-plan: plans/260603-0958-user-keyed-realtime-ws/plan.md
---

# Ổn định `feat/ws-user-combined` (Phase 5) — không merge main

## Vấn đề

Yêu cầu ban đầu "thực hiện tiếp" mơ hồ. Scout xác định được mạch việc: branch
`origin/feat/ws-user-combined` đã hoàn thành Phase 0–4 của plan
`260603-0958-user-keyed-realtime-ws`, còn Phase 5 (test & verify) dở dang.

Ràng buộc user chốt: **không đưa về `main`** vì ảnh hưởng nhóm. Làm riêng trên
branch, ổn định rồi merge sau.

## Trạng thái codebase (verified)

### Chia tách main vs branch

| | `main` (= `dev/khanhhung`, HEAD `9ff259e`) | `origin/feat/ws-user-combined` |
|---|---|---|
| Backend `/ws/user` | ✅ đầy đủ | ✅ **giống hệt** |
| Flutter user-keyed Home | ❌ vẫn device-keyed | ✅ |
| Watch BLE subsystem | ❌ | ✅ |
| Firmware DHT22 → `/temp` | ❌ | ✅ |

`git diff main origin/feat/ws-user-combined -- backend/` → **trống**. 6 commit
backend trên main là cherry-pick tương đương của branch.

Divergence: main 6 ahead / 20 behind. `git merge-tree --write-tree` → exit 0, **0 conflict**.

### Lỗi end-to-end đang tồn tại trên main

Backend trên main subscribe `sleeppad/{id}/temp` (`6f1a930`) + ACL đã mở
(`69f2bdb`), nhưng firmware trên main không publish topic đó
(`git grep dht22 main -- firmware_espidf` trống — code nằm ở branch). Tính năng
nhiệt độ môi trường không chạy trên main cho tới khi branch được merge.
Không xử lý đợt này theo quyết định của user.

## Phase 5 — gap thực tế

| Mục | Trạng thái |
|---|---|
| `flutter analyze` clean | ✅ |
| `CombinedRealtimeData.fromJson` unit test | ✅ 4/4 pass |
| `grep selectedDeviceProvider lib` trống | ✅ |
| `/ws/user`: auth reject / combined frame / watch snapshot / ping | ❌ 0 test, **không có infra** |
| `get_watch_snapshot` query correctness | ❌ |
| Home render với mock provider override | ❌ |
| `flutter test` + build smoke | ❌ chưa chạy |

Repo **chưa có bất kỳ test backend nào** → phải dựng `conftest.py` + fixture từ đầu,
không phải thêm một file test.

## Toolchain khả dụng

| Tool | Trạng thái | Hệ quả |
|---|---|---|
| `flutter 3.44.6` | ✅ | analyze / test / build chạy được |
| `python3 3.12.3` | ✅ | pytest được |
| `docker 29.6.1` | ✅ | Postgres(timescale) + Redis fixture được |
| `idf.py` | ❌ **thiếu** | firmware DHT22 không build/flash được ở máy này |

## Giải pháp chốt

### 1. Đưa branch về local
```
git fetch origin
git checkout -b feat/ws-user-combined origin/feat/ws-user-combined
```
Không merge ngược lên `main`. Không cần merge `main` xuống branch (backend giống hệt,
merge chỉ thêm noise vào history).

### 2. Dựng test backend (~70% công việc, ước lượng ~300 LOC)
- `backend/tests/` mới: pytest + pytest-asyncio + httpx
- `conftest.py`: docker container Postgres(timescale) + Redis; apply
  `postgres/init.sql` + `postgres/smart_watch_data.sql`
- 4 case `/ws/user` theo spec Phase 5: auth reject (no/invalid token → 1008),
  combined frame khi pad publish lên pubsub, watch snapshot fields populated,
  ping heartbeat
- `get_watch_snapshot` với seeded `watch_data`. **Ưu tiên case steps = tổng ngày**
  vì đó là bug thật vừa fix ở `9ff259e` (trước đó lấy bucket cuối)

### 3. Flutter test còn thiếu
- Home widget test với `userRealtimeProvider` override, 4 trạng thái:
  chỉ pad / chỉ watch / cả hai / pad offline
- `flutter test` + build smoke

### 4. Verify tay E2E
Theo mục Manual của Phase 5: login → Home hiện pad live + watch synced; pad offline
→ dot đổi; watch sync → steps/spo2/bp refresh trong 30s.

## Phương án đã cân nhắc và loại

| Phương án | Lý do loại |
|---|---|
| Merge branch → main trước rồi test trên main | User loại: ảnh hưởng nhóm |
| Chỉ merge Flutter, hoãn firmware | Cùng lý do; ngoài ra tách ra thì nhiệt độ môi trường vẫn không chạy |
| Chỉ làm backend test, bỏ Home widget test | Home là màn bị viết lại nhiều nhất mà không có test nào |
| Verify tay trước, test sau | User chọn theo plan thay vì thăm dò |
| Phase 5 + unit test watch sync service | Ngoài scope plan; user chọn bám plan |

## Rủi ro

1. **Watch BLE subsystem ship không test.** Phase 5 viết **trước khi** subsystem này
   tồn tại (commit `1079334`, `a771d27` thêm 1222 LOC sau đó):
   `watch_ble_service.dart` 182 · `watch_sync_service.dart` 199 ·
   `watch_settings_service.dart` 68 · `watch_ble_scan_screen.dart` 427 ·
   `watch_pairing_progress_screen.dart` 346.
   "Làm đúng Phase 5" ≠ "code đã được test". User đã biết và chấp nhận.
2. **Firmware không verify được ở máy này** (`idf.py` thiếu) — phần DHT22 phải flash
   ở máy khác.
3. **Branch càng để lâu càng lệch main.** Hiện merge sạch; mỗi commit backend mới trên
   main làm tăng rủi ro. Nên kiểm tra lại `git merge-tree` định kỳ.
4. **Test backend cần docker chạy** — CI hiện chưa có job nào cho backend, test mới sẽ
   chỉ chạy local cho tới khi thêm workflow.

## Trade-off đã chấp nhận (kế thừa từ report Phase 0–4)

- Pad secondary tiles rút còn Movement + Snores (S-Data/P-Data không có trong payload `/ws/user`)
- Nhiều sleep pad gộp vào một object `pad`, last-write-wins — chấp nhận cho user 1 pad
- Home sparkline bỏ preload từ history (trước keyed theo deviceId); buffer fill từ live frame
- history/alerts chỉ hiện primary sleep_pad (bỏ selector theo thiết kế đã duyệt)

## Tiêu chí nghiệm thu

- `pytest backend/tests` pass toàn bộ, gồm 4 case `/ws/user` + `get_watch_snapshot`
- `flutter analyze lib` → No issues
- `flutter test` pass toàn bộ, gồm Home widget test 4 trạng thái
- Build smoke thành công
- Checklist E2E tay hoàn tất
- `git merge-tree --write-tree main feat/ws-user-combined` vẫn exit 0

## Ngoài scope đợt này

- Merge vào `main` (làm sau khi ổn định)
- Test watch BLE subsystem
- Build/flash firmware
- Unresolved #2 (multi-pad primary vs last-active) và #4 (quy trình apply
  `smart_watch_data.sql` mỗi env)
- CI workflow cho test backend

## Câu hỏi chưa giải quyết

1. Test backend chạy ở đâu ngoài local? Chưa có CI job cho backend — cần thêm workflow
   hay chấp nhận local-only tới khi merge?
2. `smart_watch_data.sql` apply thế nào cho từng env trước deploy? (kế thừa từ report cũ,
   chưa có quy trình)
3. Multi-pad: `pad` nên hiện primary do user chọn hay last-active? (kế thừa, còn treo)
4. Ai flash được firmware DHT22 để verify phần `/temp` end-to-end?
