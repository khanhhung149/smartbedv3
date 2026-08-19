---
type: plan
date: 2026-08-02 22:03
slug: ws-user-phase5-stabilization
status: pending
branch: feat/ws-user-combined
continues: plans/260603-0958-user-keyed-realtime-ws/plan.md (Phase 5)
brainstorm: plans/reports/brainstorm-260802-2203-ws-user-stabilization.md
blockedBy: []
blocks: []
---

# Ổn định `feat/ws-user-combined` — Phase 5 test & verify

Hoàn thành Phase 5 (test & verify) của plan `260603-0958-user-keyed-realtime-ws`.
Branch đã xong Phase 0–4; đây là bước cuối trước khi đủ điều kiện merge.

**Ràng buộc user chốt: KHÔNG merge vào `main` trong đợt này.** Nhóm đang dùng main.
Ổn định trên branch, merge sau.

## Bối cảnh

| | `main` (= `dev/khanhhung`, `9ff259e`) | `origin/feat/ws-user-combined` |
|---|---|---|
| Backend `/ws/user` | ✅ | ✅ giống hệt (`git diff main <branch> -- backend/` trống) |
| Flutter user-keyed Home | ❌ | ✅ |
| Watch BLE subsystem | ❌ | ✅ |
| Firmware DHT22 → `/temp` | ❌ | ✅ |

Merge sạch (`git merge-tree --write-tree` exit 0) nhưng không thực hiện đợt này.

## Phases

| # | File | Nội dung | Ưu tiên |
|---|------|----------|---------|
| 1 | `phase-01-branch-setup-test-harness.md` | Checkout branch, thêm test deps, dựng `conftest.py` + fixture docker | P1 |
| 2 | `phase-02-ws-user-tests.md` | 4 case `/ws/user`: auth reject, combined frame, watch snapshot, ping | P1 |
| 3 | `phase-03-watch-snapshot-tests.md` | `get_watch_snapshot` + case steps = tổng ngày | P1 |
| 4 | `phase-04-flutter-home-widget-test.md` | Home widget test 4 trạng thái + `flutter test` + build smoke | P2 |
| 5 | `phase-05-manual-e2e-verify.md` | Checklist verify tay E2E | P2 |

## Dependencies

- Phase 2, 3 phụ thuộc Phase 1 (không có harness thì không chạy được).
- Phase 4 độc lập với 1–3, chạy song song được.
- Phase 5 phụ thuộc 1–4 (verify sau khi test tự động xanh).

## Quyết định thiết kế chính

**Test app tối thiểu, không dùng lifespan thật.** `main.py` lifespan khởi động MQTT
subscriber + alert engine + watch worker — sẽ cố nối mosquitto và fail trong test.
Fixture dựng `FastAPI()` rỗng, mount `data_router`, gán `app.state.db_pool` +
`app.state.redis` thủ công.

**`pythonpath = backend/app`.** Backend import bằng tên module trần
(`from data.router import ...`, `from config import get_settings`) — không có package
`app.`. pytest phải set `pythonpath` tương ứng.

## Tiêu chí nghiệm thu

- [ ] `pytest backend/tests` pass toàn bộ (4 case `/ws/user` + `get_watch_snapshot`)
- [ ] `flutter analyze lib` → No issues
- [ ] `flutter test` pass toàn bộ, gồm Home widget test 4 trạng thái
- [ ] Build smoke thành công
- [ ] Checklist E2E tay hoàn tất
- [ ] `git merge-tree --write-tree main feat/ws-user-combined` vẫn exit 0
- [ ] Phase 5 trong `plans/260603-0958-user-keyed-realtime-ws/plan.md` đổi ✅

## Ngoài scope

Merge vào `main` · test watch BLE subsystem (1222 LOC, ship không test — rủi ro đã
chấp nhận) · build/flash firmware (`idf.py` không có trên máy này) · CI workflow ·
unresolved multi-pad primary vs last-active · quy trình apply `smart_watch_data.sql`
theo env.

## Toolchain

`flutter 3.44.6` ✅ · `python3 3.12.3` ✅ · `docker 29.6.1` ✅ · `idf.py` ❌ thiếu

## Câu hỏi chưa giải quyết

1. Test backend chạy ở đâu ngoài local? Chưa có CI job cho backend.
2. Quy trình apply `smart_watch_data.sql` cho từng env trước deploy?
3. Multi-pad: `pad` nên hiện primary do user chọn hay last-active?
4. Ai flash được firmware DHT22 để verify `/temp` end-to-end?
