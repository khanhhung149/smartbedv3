---
type: brainstorm
date: 2026-08-21 10:37
slug: khoang-trong-thuc-giua-hai-repo-va-no-ui-app
status: khảo sát — không đổi kế hoạch nào
branch: master
tiếp nối: brainstorm-260821-0943-port-tang-ai-sleep-tech-projection-phut-tu-sec-data-report.md
---

# Khoảng trống thật giữa smartbedv3 và Sleep-Tech-AI, và món nợ UI của app

## Câu hỏi

"Port những gì còn thiếu thôi, đừng bỏ luôn app hiện tại vì app hiện tại đã ổn rồi."

Hàng rào phòng xa: lo việc "port từ upstream" bị hiểu rộng thành thay cả app và backend.

## Kết luận

**Không đổi kế hoạch nào.** Hàng rào đã dựng sẵn từ trước. Phiên này chỉ ghi lại khảo sát.

## Khoảng trống backend: hẹp hơn tưởng

14 module **giống hệt nhau**: `alerts`, `auth`, `config.py`, `contact`, `data`, `database.py`,
`dependencies.py`, `devices`, `fcm.py`, `main.py`, `mqtt`, `redis_client.py`, `sharing`, `watch`.

Khác đúng ba chỗ:

| Module | Upstream | smartbedv3 |
|---|---|---|
| `ai/` | ✅ | ❌ **thiếu** |
| `sessions/` | ❌ | ✅ |
| `scripts/`, `static/` | ❌ | ✅ |

→ **Module duy nhất còn thiếu là `ai/`**, đúng phạm vi plan `260821-0943`. "Port những gì còn thiếu"
theo nghĩa hẹp nhất **đã chính là kế hoạch hiện tại**.

## Khoảng trống app: hai app khác hẳn nhau

| `flutter_app/` (upstream) | `app/smartbed/` (mình) |
|---|---|
| alerts, auth, coach, data, devices, history, home, onboarding, settings, sharing | radar, realtime, session_detail, sessions, settings |
| l10n vi/en | không |
| **không có radar** | **có radar** |

App upstream nhiều màn hơn, nhưng app mình có `radar` — phần smartbedv3 thêm vào, upstream không có.

`features/coach` của họ là màn diễn giải bằng LLM. Nó **không có gì để nói** với mình vì plan
`260821-0943` đã chốt chưa nối tầng LLM (`narrator`, `fact_guard`, `prompts`).

## Hàng rào đã có sẵn từ trước

Không cần thêm ràng buộc mới. Ba chỗ đã ghi:

1. Plan `260819-0909` **quyết định 1**: *"App mới ở `smartbedv3/app/`, không fork app sleep_pad —
   Hưng chốt."*
2. Plan `260821-0943` **Ngoài phạm vi**: *"Đổi giao diện app để hiện điểm giấc ngủ"*, và *"app không
   thấy gì"* sau pha 04.
3. Plan `260821-1023` **Ngoài phạm vi**: *"Hiện ngáy lên app."*

Không kế hoạch nào chạm một dòng Dart.

## Khoảng trống đáng nói hơn: backend có, app chưa có UI

Đây mới là thứ tốn tiền mà chưa ai dùng được:

| Backend đã có | App có màn chưa |
|---|---|
| `auth/` — đăng ký, đăng nhập, OTP, email | ❌ đang nhúng **dev token hạn 30 ngày** trong config |
| `alerts/` — ngưỡng, cảnh báo, đẩy FCM | ❌ |
| `devices/` — ghép thiết bị, BLE provisioning | ❌ |
| `sharing/` — chia sẻ cho người nhà | ❌ |

Không phải phát hiện mới: plan `260819-0909` **quyết định 10** đã ghi *"UI auth ở pha sau"*.

**Món nợ có hạn sử dụng:** dev token hết hạn là app chết, và không phát được cho người khác dùng thử.

**Quyết định phiên này:** ghi nhận, **chưa làm vòng này**. Ưu tiên bài đo và hai kế hoạch đang dở.

## Việc không bị chặn

Người dùng xác nhận **không chặn gì**. Nghĩa là:

- Quyết định chuyển toàn bộ backend Go sang FastAPI (mức 3, ước 4–6 ngày, chốt sáng 21/08, hoãn tới
  sau demo) **vẫn còn hiệu lực**, không bị huỷ.
- Vòng hiện tại vẫn là hai kế hoạch `260821-0943` và `260821-1023`.

## Việc cần làm tiếp

Không có việc mới từ phiên này. Thứ tự hiện tại giữ nguyên:

1. Dọn 25 file chưa commit từ sáng 21/08 — gồm bản vá `dev-config` và ngưỡng jitter, hai thứ đã cứu
   bài đo mà chưa có mốc lùi.
2. Bài thử ngáy (nằm lên pad, tự phát tiếng ngáy bằng cổ họng) — chặn rủi ro R2 của plan `260821-0943`.
3. Hai kế hoạch đang dở.
4. Sau demo: mức 3 (Go → FastAPI).
5. Nợ UI (auth trước, vì có hạn sử dụng).

## Câu chưa trả lời

- Dev token hết hạn ngày nào? Chưa tra. Quyết định thời điểm phải làm auth UI.
- Khi làm auth UI, lấy từ `flutter_app/features/auth` của upstream hay viết mới? Upstream có sẵn cả
  l10n; nhưng app hai bên khác kiến trúc nên chi phí thích nghi có thể lớn hơn viết mới. Cần một
  phiên riêng.
- `features/coach` của upstream có đáng port khi nào nối LLM không? Chưa cần trả lời vòng này.
