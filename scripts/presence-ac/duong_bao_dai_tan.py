#!/usr/bin/env python3
"""Đường bao năng lượng theo dải tần — nguồn tín hiệu thay thế cho score model khi chấm nhịp.

Vì sao có module này: đo 17/08 cho thấy chuỗi score của snore.tflite trên audio phòng thật là
nhiễu (tự tương quan trễ-1 chỉ 0,16-0,65 dù hai cửa sổ liền kề chồng nhau 75%), trong khi RMS của
CHÍNH đoạn audio đó trơn (0,77-0,89). Tầng nhịp không có gì để bám vào. Đường bao năng lượng thì
trơn sẵn, nên chấm nhịp trực tiếp trên nó bỏ qua được hoàn toàn khâu model.

Lọc dải 100-600Hz chứ không dùng RMS toàn dải: tiếng ngáy tập trung năng lượng ở đây (rung màn hầu
và mô mềm đường thở trên), còn phần lớn nhiễu phòng ngủ — quạt rít, tiếng động cơ xa, tiếng sột
soạt vải — nằm ngoài. Đây cũng chính là dải mà loa điện thoại cắt mất, lý do mẫu phát qua loa ĐT
không dùng được.

Làm việc trong thang dB: nhịp ngáy là dao động TƯƠNG ĐỐI của năng lượng, và dB biến tỉ lệ thành
hiệu — nhờ vậy ngưỡng bắt đỉnh không phụ thuộc âm lượng tuyệt đối của phòng.
"""

import numpy as np

# Dải tần của tiếng ngáy. 100Hz cận dưới để tránh ù nguồn 50Hz và hài bậc 2 của nó.
DAI_THAP_HZ, DAI_CAO_HZ = 100.0, 600.0

# Khung phân tích. 256ms đủ dài để phân giải được 100Hz (chu kỳ 10ms) mà vẫn ngắn hơn nhiều so với
# đợt ngáy ngắn nhất (0,4s), nên không làm nhoè cạnh đợt.
KHUNG_S = 0.256

# Bước trượt — khớp với hop=15 slice của đường chấm model để hai bên so sánh được trực tiếp trên
# cùng lưới thời gian.
BUOC_S = 0.24


def duong_bao_db(pcm, sample_rate, f_thap=DAI_THAP_HZ, f_cao=DAI_CAO_HZ,
                 khung_s=KHUNG_S, buoc_s=BUOC_S):
    """PCM16 -> (đường bao năng lượng dải tần tính bằng dB, chu kỳ lấy mẫu thực tế).

    Lọc bằng FFT từng khung thay vì thiết kế bộ lọc IIR: không cần scipy, và ở đây ta chỉ cần
    NĂNG LƯỢNG trong dải chứ không cần tín hiệu đã lọc, nên khỏi lo pha.
    """
    n_khung = int(round(khung_s * sample_rate))
    n_buoc = int(round(buoc_s * sample_rate))
    x = np.asarray(pcm, dtype=np.float64)
    if len(x) < n_khung:
        return [], buoc_s

    cua_so = np.hanning(n_khung)
    tan_so = np.fft.rfftfreq(n_khung, d=1.0 / sample_rate)
    trong_dai = (tan_so >= f_thap) & (tan_so <= f_cao)

    ra = []
    for dau in range(0, len(x) - n_khung + 1, n_buoc):
        pho = np.fft.rfft(x[dau:dau + n_khung] * cua_so)
        nang_luong = float(np.sum(np.abs(pho[trong_dai]) ** 2))
        # +1 chặn log(0) ở đoạn im lặng tuyệt đối; ở mọi mức tín hiệu thật nó không đáng kể.
        ra.append(10.0 * np.log10(nang_luong + 1.0))
    return ra, buoc_s
