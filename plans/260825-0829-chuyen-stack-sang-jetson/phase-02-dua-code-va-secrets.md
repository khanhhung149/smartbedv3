---
phase: 2
title: "Đưa code và secrets sang Jetson"
status: completed
priority: P1
dependencies: [1]
---

# Phase 2: Đưa code và secrets sang Jetson

## Overview
Lấy đúng cây source đã commit lên Jetson qua git (không copy tay), rồi copy các secret thật đang chạy trên laptop sang.

## Requirements
- Functional: Jetson có bản clone repo ở nhánh `master`, đúng commit hiện tại.
- Non-functional: không commit secret vào git; secret copy nguyên giá trị thật, không tự bịa (theo `development-rules.md` mục "Cấu hình máy và bí mật đã tồn tại").

## Architecture
`git clone` qua SSH/HTTPS remote hiện có của repo. Secrets copy qua `scp`/`rsync` trực tiếp từ laptop sang Jetson (không qua git).

## Related Code Files
- Modify: không sửa code, chỉ deploy.
- Cần xác định trước khi copy: `cloud/presence-ac/.env`, `cloud/sleeppad/.env` hoặc `.env.prod`, file service account Firebase (tên file thật đọc trong `.env` liên quan), bất kỳ `config.h` thật nào dùng để build tool phụ (không phải firmware, firmware xử lý ở Phase 4).

## Implementation Steps
1. Trên Jetson: `git clone <remote-url> ~/smartbedv3` (hoặc đường dẫn tương đương), checkout đúng branch `master`.
2. Trên laptop: liệt kê toàn bộ file gitignored đang thực sự dùng (`git status --ignored` ở từng thư mục `cloud/*`), đối chiếu với `.env.example`/`.env.prod.example` để biết tên file thật cần copy.
3. `scp`/`rsync` từng file secret thật từ laptop sang đúng vị trí tương ứng trên Jetson (giữ nguyên đường dẫn tương đối trong repo).
4. Không copy đè nếu đích đã có file khác nội dung — so sánh trước (theo development-rules.md), tránh mất cấu hình đã có sẵn trên Jetson nếu trước đó đã từng thử.

## Success Criteria
- [x] Code trên Jetson khớp working tree laptop — **đổi cách làm**: dùng `rsync` (tôn trọng `.gitignore`) thay vì `git clone`, vì laptop có nhiều thay đổi CHƯA COMMIT nằm đúng trong `cloud/presence-ac` và `cloud/sleeppad` (backend sẽ build). Git clone/bundle theo history sẽ thiếu hoàn toàn phần này.
- [x] Toàn bộ file `.env`/secret cần thiết đã copy sang Jetson đúng path tương đối: `cloud/presence-ac/.env`, `cloud/sleeppad/.env.dev`, `cloud/mqtt/passwd`. `secrets/fcm.json` trên laptop thực ra là thư mục rỗng (Docker tự tạo do chưa có credential Firebase thật) — đã tái tạo y hệt trên Jetson, không phải thiếu sót.

## Kết quả thực thi (2026-08-25)
- `rsync -az --filter=':- .gitignore' --exclude .git/ /mnt/d/smartbedv3/ mp@192.168.1.125:~/smartbedv3/` → 96M, bao gồm cả file untracked mới (vd `cloud/presence-ac/internal/snore/`).
- Secret copy riêng (không qua rsync filter vì bị gitignore che): `.env`, `.env.dev`, `cloud/mqtt/passwd`.
- Sleeppad dùng `.env.dev` (không có `.env.prod` trên laptop) — khớp deployment-guide.md: hệ đang chạy ở chế độ dev.

## Risk Assessment
- Repo có nhiều `.env.example` khác nhau theo service — dễ sót 1 file. Đối chiếu danh sách biến trong mỗi `docker-compose.yml` liên quan trước khi coi là xong.
- Không copy đè secret nếu Jetson đã có bản khác — kiểm tra trước, hỏi user nếu nghi ngờ giá trị nào đúng hơn.
