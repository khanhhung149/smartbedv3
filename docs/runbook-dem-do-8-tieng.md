# Runbook — đêm đo 8 tiếng (Phase 01, tiêu chí 1)

Quy trình chạy một đêm đo và đọc kết quả. Viết để người **không viết code** làm theo được.

- **Plan:** [`plans/260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite/plan.md`](../plans/260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite/plan.md)
- **Tiêu chí:** ghi liên tục 8 tiếng, mất dưới 0,1% mẫu.

---

## Hai đường ống, hai cách đếm

Hệ có **hai** đường dữ liệu độc lập. Đừng lẫn chúng — số mẫu, nhịp và cách đếm đều khác nhau.

| | Đường A | Đường B |
|---|---|---|
| Node | `radar-node` (LD2410C) | `sleep-pad-node` |
| Topic | `home/room/sample` | `sleeppad/<id>/sec\|min\|temp` |
| Broker | `home-mqtt`, cổng **1883** | `sleeppad-mosquitto`, cổng **1884** |
| Consumer | backend Go (`cloud/presence-ac`) | FastAPI (`cloud/sleeppad`) |
| Đích | SQLite `samples` | TimescaleDB `sec_data` |
| Nhịp | 10Hz | 1Hz |
| 8 tiếng | **288.000** mẫu | **28.800** khung |
| Đếm mất mẫu bằng | `seq` (chính xác, truy được nguyên nhân) | `received_at` gom theo phút (thô) |

Tiêu chí 1 nằm trên **đường A**. Tiêu chí 5 (3 đêm dữ liệu thật) nằm trên **đường B**.

---

## 1. Chuẩn bị — chiều hôm trước

### Nguồn

- Ổ cắm riêng trên bench rig, **không lấy nguồn từ laptop** (quy tắc chốt 13/07 — laptop ngủ là cắt nguồn).
- Một adapter 5V/2A riêng cho mỗi node. Không dùng hub USB rẻ: hub chia dòng kém, một node kéo dòng làm node kia reset.
- Cáp USB **ngắn, lõi dày**. Cáp dài mỏng sụt áp khi radar kéo dòng đỉnh → ESP32 brownout reset. Reset giữa đêm hiện ra dưới dạng `boot` tăng.

### Máy host

Đây là mắt xích duy nhất phải **thức suốt đêm** (Jetson không tham gia đường đo nào).

- Tắt sleep/hibernate. Máy ngủ lúc 3h sáng là hỏng đêm đo.
- Đủ chỗ trống đĩa: 288.000 mẫu ≈ vài chục MB, nhưng WAL sinh thêm file `-wal`/`-shm` cạnh DB.

### Địa chỉ máy host

Địa chỉ broker của `radar-node` **compile vào firmware** (`firmware/radar-node/include/config.h`, file này bị gitignore). Đổi máy host mà IP đổi ⇒ **flash lại node**.

1. Lấy MAC của máy host, đặt **DHCP reservation** trên router. Router không hỗ trợ thì đặt IP tĩnh trên máy host, ngoài dải DHCP.
2. Xác nhận địa chỉ thật: `ip -4 addr`
3. Đối chiếu với `MQTT_HOST` trong `config.h` của node.

`sleep-pad-node` khác: địa chỉ broker do **BLE provisioning** nạp vào NVS lúc chạy, không compile cứng. Đổi host thì provision lại qua BLE, không phải flash.

Làm bước này một lần thì sau này chuyển stack sang Jetson chỉ cần gán đúng IP đó cho Jetson.

---

## 2. Bật hệ

Thứ tự: broker trước, consumer sau.

Broker phải lên **trước**: nó tạo network `smartbed-mqtt` mà backend khai `external`.

```bash
# Đường A — broker 1883 + backend Go
cd cloud/mqtt        && docker compose up -d
cd ../presence-ac    && docker compose up -d --build

# Đường B — broker 1884 + FastAPI + Postgres + Redis
cd ../sleeppad && docker compose -f docker-compose.yml -f docker-compose.dev.yml \
                    --env-file .env.dev up -d
```

Hai broker chạy cùng máy. `.env.dev` của `sleeppad` phải có `MQTT_HOST_PORT=1884` và `MQTT_WS_HOST_PORT=9002`, nếu không nó tranh cổng 1883 với `home-mqtt`.

### ⚠️ `MQTT_HOST=host.docker.internal` KHÔNG dùng được (Docker Desktop)

**Đã xử lý ở compose:** hai stack dùng chung network `smartbed-mqtt`, `.env` đặt
`MQTT_HOST=home-mqtt`. Phần dưới giữ lại để giải thích vì sao, và để nhận diện triệu chứng.

`cloud/presence-ac/.env.example` để `MQTT_HOST=host.docker.internal`. Trên Docker Desktop giá trị
này **không tới được** cổng publish của `home-mqtt`: container backend nằm ở network riêng, và
đường vòng qua host-gateway về cổng publish của một container khác bị chặn.

Triệu chứng rất dễ hiểu nhầm: `nc -z host.docker.internal 1883` **báo mở**, nhưng client MQTT
không nối được và log broker **không thấy một connection nào**. Backend chỉ in một dòng
`mqtt chưa kết nối trong timeout, retry ở nền` rồi im lặng retry mãi. Đo 20/08.

Cách dùng được — cho hai container chung network rồi gọi bằng tên:

```bash
docker network connect presence-ac_default home-mqtt
# rồi trong cloud/presence-ac/.env:
#   MQTT_HOST=home-mqtt
docker compose up -d --no-deps backend
docker logs home-backend | grep mqtt      # phải thấy: INFO mqtt connected
```

### Cùng lỗi đó chặn luôn ESP32 (đo 20/08)

ESP32 nối tới `192.168.1.120:1883` (IP LAN của máy). Nó **nối được tới Windows** — `netstat` cho
`ESTABLISHED` — nhưng broker không ghi nhận gì, vì Windows chuyển tiếp vào VM `docker-desktop` và
kẹt ở `SYN_SENT`.

Thí nghiệm đối chứng, làm được bằng một lệnh:

```bash
# Đếm số connection broker ghi nhận trước và sau khi nối thử từng đường.
docker logs home-mqtt 2>&1 | grep -c "New connection"
```

Nối vào IP của WSL distro thì con số tăng; nối vào IP LAN của Windows thì **không tăng**.

> **`nc -z`, `Test-NetConnection`, `netstat` đều nói dối ở đây.** Proxy cổng của Docker accept
> kết nối TRƯỚC rồi mới nối lên broker, nên cả ba đều báo "cổng mở" trong khi không gói nào tới
> nơi. Chỉ log broker mới nói thật.

Cách sửa đã thử, theo thứ tự nên làm: reboot Windows → bật WSL mirrored networking
(`.wslconfig`, `networkingMode=mirrored`) → `netsh portproxy` trỏ về IP của WSL distro.
Restart Docker Desktop và `wsl --terminate docker-desktop` **không** đủ.

**Không thấy dòng `INFO mqtt connected` thì đừng đi ngủ.** Backend vẫn lên HTTP bình thường và
trông như đang chạy, nhưng không nhận một mẫu nào.

---

## 3. Kiểm trước khi đi ngủ

Chạy hết bảng này. Bỏ qua một dòng có thể đổi lấy cả đêm đo.

| # | Kiểm | Lệnh | Mong đợi |
|---|---|---|---|
| 0 | Backend đã nối broker | `docker logs home-backend \| grep mqtt` | `INFO mqtt connected` |
| 1 | Node A đang publish | `mosquitto_sub -h <host> -p 1883 -u <user> -P <pass> -t 'home/room/sample' -C 5` | 5 dòng JSON, `seq` tăng đều |
| 2 | Đồng hồ MCU đã sync | nhìn trường `t` ở dòng trên | epoch ms hợp lý, không phải 0 |
| 3 | `boot` ổn định | nhìn trường `boot` | một số cố định — đổi giữa đêm nghĩa là MCU reset |
| 4 | Backend đang ghi | xem mục *Đếm mẫu* bên dưới, chạy 2 lần cách nhau 60s | chênh ≈ 600 |
| 5 | WAL đang bật | mục *Đếm mẫu*, câu `PRAGMA journal_mode` | `wal` |
| 6 | **Node B đã pair** | `docker compose exec postgres psql -U <user> -d <db> -c "SELECT id, last_seen FROM devices;"` | có dòng khớp `device_id` của node |
| 7 | Node B đang vào DB | `SELECT count(*) FROM sec_data;` chạy 2 lần cách nhau 60s | chênh ≈ 60 |
| 8 | Voice-node (ngáy) sẵn sàng | giả tiếng ngáy 3s rồi xem log `docker logs home-backend \| grep snore` | không có lỗi ghi DB |

> **Dòng 6 là bẫy nghiêm trọng nhất.** `cloud/sleeppad/app/mqtt/subscriber.py:108` **drop im lặng** mọi frame từ thiết bị chưa pair. Bỏ qua thì sáng ra 0 dòng, trông y hệt mất 100%.

### Đếm mẫu (đường A)

DB nằm trong volume `home-data` của service `backend`, đường dẫn trong container là `/data/home.db`
(`DB_PATH` trong `.env`).

Image backend là **distroless** — không có shell, không `exec` vào được. Đọc DB bằng một container
phụ mount cùng volume:

```bash
# Tên volume = <tên project compose>_home-data. Kiểm tên thật trước:
docker volume ls | grep home-data

docker run --rm -v presence-ac_home-data:/data alpine:3 sh -c \
  'apk add --no-cache sqlite >/dev/null && sqlite3 /data/home.db \
     "PRAGMA journal_mode; SELECT count(*) FROM samples;"'
```

---

## 4. Sáng hôm sau

### Đường A — đếm và truy nguyên nhân

Đặt `$FROM`/`$TO` là mốc epoch **mili-giây** của đêm đo.

```sql
-- Tổng mẫu nhận được
SELECT count(*) FROM samples WHERE ts >= $FROM AND ts < $TO;

-- Số lần MCU reset trong đêm
SELECT count(DISTINCT boot) FROM samples WHERE ts >= $FROM AND ts < $TO;

-- Lỗ hổng seq: mỗi dòng là một quãng bị mất, kèm số mẫu mất
SELECT prev_seq, seq, seq - prev_seq - 1 AS missing FROM (
  SELECT seq, boot, LAG(seq) OVER (PARTITION BY boot ORDER BY id) AS prev_seq
  FROM samples WHERE ts >= $FROM AND ts < $TO
) WHERE seq - prev_seq > 1;

-- Quãng thời gian MCU trượt nhịp: seq liền nhau nhưng ts cách xa hơn 1 nhịp
SELECT prev_ts, ts, ts - prev_ts AS gap_ms FROM (
  SELECT ts, seq, boot, LAG(ts) OVER (PARTITION BY boot ORDER BY id) AS prev_ts,
         LAG(seq) OVER (PARTITION BY boot ORDER BY id) AS prev_seq
  FROM samples WHERE ts >= $FROM AND ts < $TO
) WHERE seq - prev_seq = 1 AND ts - prev_ts > 200;
```

`PARTITION BY boot` là bắt buộc, nhưng **không** vì lý do dễ đoán. Kiểm chứng trên DB thật
(20/08) cho thấy: bỏ `PARTITION BY` thì lần reset **không** sinh lỗ hổng giả — `seq` tụt từ 20 về 0
cho hiệu số âm, và bộ lọc `> 1` bỏ qua nó im lặng. Hỏng theo chiều ngược lại và khó thấy hơn:
dòng ở ranh giới reset bị **bỏ sót**, nên mẫu mất ngay trước hoặc sau một lần reset không bị phát
hiện, và tổng số mẫu mất cộng ra sẽ thiếu.

**Bảng đọc kết quả:**

| Hiện tượng | Kết luận | Hướng sửa |
|---|---|---|
| `seq` thủng lỗ, `ts` liền mạch | mất trên đường | WiFi, QoS0, broker, ring buffer đầy |
| `seq` liền, `ts` nhảy quãng | MCU trượt nhịp | vòng lặp chính, UART radar |
| `boot` tăng giữa đêm | MCU reset | nguồn yếu, brownout, watchdog |
| `seq` là `NULL` | firmware chưa có bộ đếm | flash lại node |

**Ngưỡng đạt:** mất dưới 0,1% của 288.000 ⇒ không quá **288 mẫu**.

### Đường B — đếm theo `received_at`

Không có `seq` trên đường này. Và **`time` không đáng tin**: pad trôi đồng hồ, firmware không gửi khung sync 0x0B — xem chú thích ở `cloud/sleeppad/app/mqtt/subscriber.py`, hàm `_insert_sec`. Đếm theo `received_at` (mốc do server đóng dấu lúc nhận).

```sql
SELECT date_trunc('minute', received_at) AS phut, count(*) AS khung
FROM sec_data
WHERE received_at >= '<bắt đầu>' AND received_at < '<kết thúc>'
GROUP BY 1 ORDER BY 1;
```

Mỗi phút phải ≈ 60 khung. Phút nào thiếu nhiều là quãng mất.

### Đường Voice (kiểm báo nhầm ngáy)

Đếm sự kiện ngáy để đo tần suất model báo nhầm lúc không có người hoặc lúc ngủ yên:

```sql
SELECT count(*) FROM room_snore_events WHERE t >= '<bắt đầu>' AND t < '<kết thúc>';
```

---

## 5. Lịch bốn đêm

Tiêu chí 5 cần 3 đêm dữ liệu thật. Chốt 20/08: **đêm đầu chỉ soát thiết bị**, không tính điểm.

| Đêm | Vai trò | Hỏng thì làm gì |
|---|---|---|
| 1 | Soát thiết bị — chạy đủ quy trình để lộ lỗi vận hành | Sửa rồi chạy lại đêm 1, không tính vào 3 đêm |
| 2, 3, 4 | Tính điểm cho tiêu chí 1 và tiêu chí 5 | Chạy bù đúng đêm đó |

Ghi rõ đêm đang chạy là đêm nào, để không nhầm đêm soát thành đêm tính điểm.

---

## 6. Điều làm đêm đo mất giá trị

- Máy host ngủ hoặc reboot.
- Cúp điện. WAL + `synchronous=NORMAL` mất các transaction chưa checkpoint — đánh đổi đã chấp nhận để đường ghi theo kịp 10Hz.
- Flash lại firmware giữa đêm: `boot` nhảy, `seq` reset.
- Không có người nằm thật — radar không có gì để đo.
- Copy mỗi file `.db` mà bỏ `-wal`/`-shm`: mất phần dữ liệu chưa checkpoint.
- Chạy `cmd/seed-csv` vào cùng DB: trộn dữ liệu seed (`seq` = `NULL`) với dữ liệu đo thật.
