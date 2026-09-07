-- Phase 01 — Canonical sample stream (schema khớp CSV take-home)
--
-- Bảng samples là chuỗi dữ liệu CHUẨN của hệ thống, đúng 9 cột CSV trong plan:
--   t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity
-- Cộng thêm kênh raw của từng sensor (status, sdata, pdata, movement, snore_count,
-- resp_disorder, pthd, body_temp, ambient temp/humidity) để KHÔNG MẤT kênh nào —
-- yêu cầu "lưu tất cả kênh, kể cả kênh chưa dùng".
--
-- - `t` = thời điểm mẫu. Với sleep pad là epoch MCU (ts gắn tại thiết bị) được đẩy lên
--   qua MQTT; nếu thiếu thì subscriber dùng received_at làm dự phòng (không bao giờ NULL).
-- - presence: pad không có chân OUT — suy từ status/heart_rate/resp_rate khi lệch khỏi 0
--   (bed occupied). hr_bpm = 0 khi sensor dropout (đánh dấu lỗi tường minh, không bịa số).
-- - retention: giữ 30 đêm gần nhất theo mốc UTC nửa đêm (add_retention_policy dựa trên cột t).

CREATE TABLE IF NOT EXISTS samples (
  t              TIMESTAMPTZ NOT NULL,
  device_id      TEXT NOT NULL,

  -- 9 cột CSV take-home
  presence       BOOLEAN NOT NULL DEFAULT FALSE,
  hr_bpm         REAL,             -- 0 = dropout (sensor không đo được), không bịa số
  resp_amplitude REAL,             -- pad: resp_rate (1/phút); sensor khác ghi amplitude
  motion         REAL,             -- pad: movement của frame 0x86; 0 nếu chưa có
  weight_kg      REAL,             -- NULL: pad không đo được cân nặng (giữ kênh, đừng xoá)
  spo2           REAL,             -- NULL: không có SpO2 trên pad (giữ kênh)
  temp_c         REAL,             -- nhiệt độ môi trường (topic /temp); NULL nếu chưa có
  humidity       REAL,             -- độ ẩm môi trường (topic /temp); NULL nếu chưa có

  -- Kênh raw của sleep pad (frame 0x85 / 0x86) — lưu tất cả, kể cả chưa ai dùng
  status         SMALLINT,
  sdata          SMALLINT,
  pdata          SMALLINT,
  movement       SMALLINT,
  snore_count    SMALLINT,
  resp_disorder  SMALLINT,
  pthd           SMALLINT,
  body_temp      REAL,

  -- Cờ lỗi + dấu vết
  uart_ok        BOOLEAN NOT NULL DEFAULT FALSE,  -- khung hợp lệ nhận từ pad
  ts_pad         INTEGER,                          -- mốc pad báo trong frame (nghi ngờ lệch)
  received_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

SELECT create_hypertable('samples', 't', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS idx_samples_device_time ON samples (device_id, t DESC);

-- Retention: giữ 30 đêm. TimescaleDB drop chunk cũ hơn cutoff (theo cột t).
SELECT add_retention_policy('samples', INTERVAL '30 days', if_not_exists => TRUE);

-- Nén chunk cũ hơn 1 ngày (giảm dung lượng ổ đĩa + tăng tốc đọc lịch sử).
-- Bật columnstore trước là bắt buộc: add_compression_policy trên bảng chưa bật
-- sẽ báo "columnstore not enabled" và bỏ qua chính sách nén.
ALTER TABLE samples SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'device_id',
  timescaledb.compress_orderby   = 't DESC'
);
SELECT add_compression_policy('samples', INTERVAL '1 day', if_not_exists => TRUE);