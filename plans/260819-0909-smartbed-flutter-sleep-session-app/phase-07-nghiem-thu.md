---
phase: 7
title: "Nghiệm thu — chạy 5 tiêu chí, ghi kết quả"
status: partial
priority: P2
dependencies: [6]
repo: smartbedv3 + sleep_pad_AI
---

# Phase 07: Nghiệm thu

## Overview
Chạy 5 tiêu chí nghiệm thu của plan trên hệ thật (dev/local), ghi kết quả bằng số đo thật — kể cả khi trượt.

## Requirements
- Mỗi tiêu chí có bằng chứng kiểm được: lệnh chạy + output, hoặc ảnh chụp màn hình.
- Kết quả trượt phải ghi lại nguyên trạng, **không** sửa tiêu chí cho vừa kết quả.

## Related Code Files
- Create: `smartbedv3/plans/260819-0909-smartbed-flutter-sleep-session-app/reports/nghiem-thu-vong-1.md`
- Modify: `smartbedv3/plans/260819-0909-smartbed-flutter-sleep-session-app/plan.md` — cập nhật `status`

## Implementation Steps

1. **Dựng hệ sạch**
```bash
cd /mnt/d/sleep_pad_AI/backend
docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d
set -a && source .env.dev && set +a
bash scripts/apply-schema.sh          # Phase 01 — idempotent
```

2. **Tiêu chí 1 — một đêm sinh đúng một phiên**
```bash
DC="docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev"
$DC exec fastapi python /app/scripts/seed-night.py \
  --device-id TEST000001 --start 2026-08-18T23:40:00 --hours 8
curl -s -H "Authorization: Bearer $TOKEN" 'localhost:8080/sessions?device_id=TEST000001' | python3 -m json.tool
```
Kiểm: đúng 1 phần tử; `started_at` ≈ 23:40 + 30 giây; `ended_at` = lúc bắt đầu rời giường.

3. **Tiêu chí 2 — `hr_avg` không tụt vì `hr=0`**
Seed hai lần vào hai device (`$DC exec fastapi python /app/scripts/seed-night.py ...`), một lần có `--zero-hr-half`. So `hr_avg`. Chênh lệch phải nằm trong sai số làm tròn, **không** khoảng một nửa.

   Chạy luôn unit test của Phase 02: `cd backend && python -m pytest tests/ -v` (pytest cài từ `requirements-dev.txt`).

4. **Tiêu chí 3 — offline**
Mở app, xem một phiên. Bật chế độ máy bay trên emulator. Mở lại app. Phải thấy phiên cũ + banner ngoại tuyến.

5. **Tiêu chí 4 — 360dp và 800dp**
Chạy `flutter run -d chrome`, kéo cửa sổ qua hai mốc. Chụp màn hình cả hai. Kiểm: không cuộn ngang toàn trang, không chữ tràn, không đè.

6. **Tiêu chí 5 — nhãn wellness**
```bash
grep -rn "tham khảo, không dùng chẩn đoán" /mnt/d/smartbedv3/app/lib | wc -l
```
Phải > 0 và phải nhìn thấy trên **cả hai** màn hình khi chạy thật (grep không đủ — chuỗi có thể nằm trong code chết).

7. **Viết `reports/nghiem-thu-vong-1.md`**: từng tiêu chí — đạt/trượt, số đo thật, lệnh đã chạy. Trượt thì ghi rõ trượt và vì sao.

8. Cập nhật `plan.md`: `status: completed` nếu tất cả đạt; nếu không, ghi rõ tiêu chí nào còn treo và giữ `status: pending`.

## Success Criteria
- [ ] Cả 5 tiêu chí đã chạy và có bằng chứng ghi lại
- [ ] `reports/nghiem-thu-vong-1.md` tồn tại, có số đo thật, không có câu nào kiểu "về cơ bản là chạy"
- [ ] Tiêu chí trượt (nếu có) được ghi nguyên trạng kèm nguyên nhân
- [ ] `plan.md` cập nhật đúng trạng thái thật

<!-- Updated: Validation Session 1 — F-01/F-02/F-03: lệnh dựng hệ dùng apply-schema.sh, seed chạy trong container fastapi, thêm bước chạy pytest -->

## Risk Assessment
- **Sửa tiêu chí cho vừa kết quả:** cấm. Tiêu chí trượt là thông tin, không phải thất bại cần giấu.
- **R1 vẫn còn nguyên sau pha này:** nghiệm thu chạy trên **dữ liệu seed**, không phải đêm ngủ thật. Luật `on_bed` vẫn **chưa được kiểm chứng**. Báo cáo phải nói rõ điều đó, đừng để người đọc sau tưởng đã xác nhận.
- **Nghiệm thu trên dev, không phải prod:** đúng như quyết định #8. Không suy ra kết luận nào về prod.
