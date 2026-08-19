#!/usr/bin/env python3
"""Phát hiện ngáy bằng NHỊP của chuỗi score, thay cho ngưỡng đơn trên từng cửa sổ.

Vì sao cần: đo 17/08 cho thấy ngưỡng đơn bất khả thi. Phòng yên có p95=0,49 trong khi đoạn có
tiếng ngáy chỉ median 0,38 — hai phân bố chồng lấn, đặt ngưỡng ở đâu cũng sai. Nhưng ngáy có cấu
trúc THỜI GIAN mà nhiễu nền không có: từng đợt 0,5-2 giây, lặp theo nhịp thở đều đặn mỗi 2-6 giây,
kéo dài hàng chục phút. Module này chấm cái cấu trúc đó.

Điểm mấu chốt: mọi ngưỡng ở đây đều TƯƠNG ĐỐI so với nền của chính đoạn tín hiệu (median + MAD),
không phải hằng số tuyệt đối. Nhờ vậy nó miễn nhiễm với việc model lệch miền và trả score thấp
toàn cục — model chỉ cần PHẢN ỨNG với tiếng ngáy, không cần chấm CHÍNH XÁC. Đó là khác biệt so với
SNORE_SCORE_THRESHOLD=0.5 cứng trong firmware hiện tại.

Không import TensorFlow: chạy/tự kiểm được trên host mà không cần Docker, và là đặc tả tham chiếu
khi port sang C++ cho snoreTask.

Tự kiểm (không cần model, không cần WAV):

    python3 scripts/snore_nhip.py --tu-kiem
"""

import statistics

# Chu kỳ thở lúc ngủ: 10-30 nhịp/phút -> khoảng cách giữa hai tiếng ngáy liên tiếp 2-6 giây.
KHOANG_NHIP_MIN_S, KHOANG_NHIP_MAX_S = 2.0, 6.0

# Độ dài một tiếng ngáy. Ngắn hơn là nhiễu xung (cửa đóng, tiếng gõ), dài hơn là nguồn ồn liên tục
# (quạt, xe chạy) chứ không phải một hơi thở.
DOT_MIN_S, DOT_MAX_S = 0.4, 2.5

# Hệ số biến thiên tối đa của khoảng cách giữa các đợt. Đây là THAM SỐ QUAN TRỌNG NHẤT của module:
# nó phân biệt "đều đặn như nhịp thở" với "ngẫu nhiên như tiếng ồn". 0,35 là điểm khởi đầu suy từ
# dao động sinh lý của nhịp thở, CHƯA tune trên dữ liệu — xem báo cáo đo để chốt số thật.
CV_TOI_DA = 0.35

# Số đợt tối thiểu trong cửa sổ phân tích. Dưới mức này thì hệ số biến thiên tính trên quá ít mẫu,
# rất dễ "đều" do ngẫu nhiên.
SO_DOT_TOI_THIEU = 8

# Ngưỡng bắt đỉnh = nền + HE_SO_MAD*MAD, nhưng không thấp hơn DELTA_TOI_THIEU. Chặn dưới là cần:
# đoạn tín hiệu phẳng lì có MAD ~ 0, khi đó ngưỡng tụt sát nền và mọi gợn nhiễu đều thành "đợt".
HE_SO_MAD = 1.5
DELTA_TOI_THIEU = 0.05


# Làm trơn chuỗi score trước khi bắt đỉnh, tính bằng GIÂY.
#
# Vì sao bắt buộc: cửa sổ model dài 1s còn bước trượt chỉ 0,24s, nên hai score liền kề nhìn vào
# 75% cùng một đoạn audio — lẽ ra phải gần bằng nhau. Đo thật 17/08 lại thấy chúng nhảy 0,02 <-> 0,94
# giữa hai mẫu liền kề. Đó là nhiễu của model (rất nhạy với vị trí căn chỉnh), không phải tín hiệu.
# Không làm trơn thì bộ bắt đỉnh bắt phải gai nhiễu một mẫu, và mọi file đều ra CV lớn như nhau.
#
# Dùng lọc TRUNG VỊ chứ không phải trung bình trượt. Đã thử trung bình trượt trước: nó nhoè cạnh
# của đợt, làm hai đợt cách nhau 1,4s dính thành một khối dài rồi bị loại vì quá DOT_MAX_S — ca tự
# kiểm "ngáy đều 2,2s" fail. Trung vị xoá gai đơn lẻ mà giữ nguyên cạnh, đúng thứ cần ở đây.
#
# 0,72s = 3 mẫu ở 4,2Hz: cửa sổ nhỏ nhất còn có trung vị nghĩa lý, khử được gai một mẫu.
LAM_TRON_S = 0.72


def lam_tron(xs, chu_ky_mau_s, cua_so_s=LAM_TRON_S):
    """Lọc trung vị, giữ nguyên độ dài chuỗi (cửa sổ co lại ở hai biên)."""
    k = max(1, round(cua_so_s / chu_ky_mau_s))
    if k < 3 or len(xs) < k:
        return list(xs)
    ban_kinh = k // 2
    return [
        statistics.median(xs[max(0, i - ban_kinh):min(len(xs), i + ban_kinh + 1)])
        for i in range(len(xs))
    ]


def _mad(xs, trung_vi):
    """Median absolute deviation — đo độ phân tán, không bị kéo lệch bởi chính các đỉnh ngáy mà ta
    đang muốn tìm (khác hẳn độ lệch chuẩn)."""
    return statistics.median([abs(x - trung_vi) for x in xs])


def tim_dot(scores, chu_ky_mau_s, nen=None, he_so_mad=HE_SO_MAD, delta_toi_thieu=DELTA_TOI_THIEU):
    """Tìm các 'đợt' — quãng score liên tiếp vượt nền đủ lâu để là một tiếng ngáy.

    Trả (danh sách đợt, ngưỡng đã dùng, nền đã dùng). Mỗi đợt là dict {tam_s, dai_s, dinh}.
    """
    if not scores:
        return [], 0.0, 0.0

    scores = lam_tron(scores, chu_ky_mau_s)
    if nen is None:
        nen = statistics.median(scores)
    nguong = nen + max(he_so_mad * _mad(scores, nen), delta_toi_thieu)

    dot = []
    dau = None
    for i, s in enumerate(scores):
        if s > nguong and dau is None:
            dau = i
        elif s <= nguong and dau is not None:
            dot.append((dau, i))
            dau = None
    if dau is not None:
        dot.append((dau, len(scores)))

    ket_qua = []
    for dau, cuoi in dot:
        dai_s = (cuoi - dau) * chu_ky_mau_s
        if DOT_MIN_S <= dai_s <= DOT_MAX_S:
            ket_qua.append({
                "tam_s": (dau + cuoi) / 2 * chu_ky_mau_s,
                "dai_s": dai_s,
                "dinh": max(scores[dau:cuoi]),
            })
    return ket_qua, nguong, nen


def phan_tich_nhip(scores, chu_ky_mau_s, so_dot_toi_thieu=SO_DOT_TOI_THIEU, cv_toi_da=CV_TOI_DA,
                   he_so_mad=HE_SO_MAD, delta_toi_thieu=DELTA_TOI_THIEU):
    """Chấm xem chuỗi giá trị có nhịp kiểu ngáy không.

    `chu_ky_mau_s` = khoảng thời gian giữa hai giá trị liên tiếp. Với hop=15 slice thì là 0,24s
    (~4,2Hz). Lấy mẫu 1Hz KHÔNG đủ: chu kỳ ngáy ngắn nhất là 2s, sát giới hạn Nyquist, đo nhịp
    không tin được.

    Chuỗi đầu vào không nhất thiết là score model — đường bao năng lượng dải tần tính bằng dB
    (xem duong_bao_dai_tan.py) dùng được y hệt, chỉ cần đổi `delta_toi_thieu` sang thang dB.

    Trả dict — luôn có khoá 'la_ngay' (bool) và 'ly_do' (chuỗi giải thích khi không đạt).
    """
    dot, nguong, nen = tim_dot(scores, chu_ky_mau_s, he_so_mad=he_so_mad,
                               delta_toi_thieu=delta_toi_thieu)
    kq = {
        "so_dot": len(dot),
        "nen": round(nen, 4),
        "nguong": round(nguong, 4),
        "khoang_trung_vi_s": None,
        "cv": None,
        "la_ngay": False,
        "ly_do": "",
    }

    if len(dot) < so_dot_toi_thieu:
        kq["ly_do"] = f"chỉ {len(dot)} đợt, cần ≥{so_dot_toi_thieu}"
        return kq

    khoang = [dot[i + 1]["tam_s"] - dot[i]["tam_s"] for i in range(len(dot) - 1)]
    trung_vi = statistics.median(khoang)
    # Chia cho trung vị chứ không cho trung bình: một khoảng trống dài (người trở mình, ngừng ngáy
    # một lúc) kéo trung bình lên hẳn và làm CV nhỏ đi giả tạo.
    cv = statistics.pstdev(khoang) / trung_vi if trung_vi > 0 else float("inf")
    kq["khoang_trung_vi_s"] = round(trung_vi, 3)
    kq["cv"] = round(cv, 3)

    if not KHOANG_NHIP_MIN_S <= trung_vi <= KHOANG_NHIP_MAX_S:
        kq["ly_do"] = f"khoảng {trung_vi:.2f}s ngoài dải nhịp thở {KHOANG_NHIP_MIN_S}-{KHOANG_NHIP_MAX_S}s"
    elif cv > cv_toi_da:
        kq["ly_do"] = f"CV {cv:.2f} > {cv_toi_da} — không đều, nghi nhiễu ngẫu nhiên"
    else:
        kq["la_ngay"] = True
    return kq


# ── Tự kiểm ────────────────────────────────────────────────────────────────────
# Chuỗi score tổng hợp, không cần model/WAV. Mục đích: chứng minh thuật toán tách được nhịp đều
# khỏi nhiễu ngẫu nhiên TRƯỚC khi đem chấm dữ liệu thật — nếu nó fail ở đây thì kết quả trên WAV
# không diễn giải được.

def _chuoi_nhip(chu_ky_mau_s, tong_s, khoang_s, dai_dot_s, nen, dinh, jitter=0.0):
    """Sinh chuỗi có đợt lặp đều mỗi khoang_s giây. jitter = lệch tương đối của từng khoảng."""
    n = int(tong_s / chu_ky_mau_s)
    xs = [nen] * n
    t = 0.0
    k = 0
    while t < tong_s:
        dau = int(t / chu_ky_mau_s)
        cuoi = min(n, dau + max(1, int(dai_dot_s / chu_ky_mau_s)))
        for i in range(dau, cuoi):
            xs[i] = dinh
        # Lệch luân phiên +/- để nhịp không đều mà không cần random (giữ tự kiểm tất định).
        lech = khoang_s * jitter * (1 if k % 2 else -1)
        t += khoang_s + lech
        k += 1
    return xs


def _tu_kiem():
    chu_ky = 0.24  # hop=15 slice
    ca = []

    # Ngáy điển hình: đợt 1s mỗi 3s, biên độ gấp đôi nền.
    ca.append(("ngáy đều 3s", _chuoi_nhip(chu_ky, 60, 3.0, 1.0, 0.17, 0.38), True))

    # Ngáy nhịp nhanh hơn, vẫn trong dải sinh lý.
    ca.append(("ngáy đều 2,2s", _chuoi_nhip(chu_ky, 60, 2.2, 0.8, 0.20, 0.45), True))

    # Nhịp thở dao động nhẹ (sinh lý thật) — vẫn phải nhận.
    ca.append(("ngáy jitter 15%", _chuoi_nhip(chu_ky, 60, 3.0, 1.0, 0.17, 0.38, jitter=0.15), True))

    # Phòng yên: phẳng, không đợt nào.
    ca.append(("phòng yên phẳng", [0.17] * 250, False))

    # Nguồn ồn liên tục (quạt): score cao đều nhưng KHÔNG có đợt tách rời.
    ca.append(("ồn liên tục", [0.45] * 250, False))

    # Nhiễu xung đủ nhiều để qua được bộ đếm đợt, nhưng khoảng cách rất không đều -> phải bị CV
    # loại. Ca này cố tình ép vào ĐÚNG nhánh CV: đủ 8+ đợt và trung vị khoảng cách vẫn nằm trong
    # dải nhịp thở, nên hai bộ lọc kia không cứu được, chỉ tính đều mới phân biệt nổi.
    xung = [0.17] * 250
    for t in (2, 5, 11, 13, 24, 27, 29, 41, 44, 55):
        for i in range(int(t / chu_ky), int(t / chu_ky) + 4):
            xung[i] = 0.6
    ca.append(("xung không đều", xung, False))

    # Nhịp quá chậm (12s) — ngoài dải nhịp thở, không phải ngáy.
    ca.append(("nhịp 12s quá chậm", _chuoi_nhip(chu_ky, 120, 12.0, 1.0, 0.17, 0.5), False))

    dat = True
    for ten, xs, mong_doi in ca:
        kq = phan_tich_nhip(xs, chu_ky)
        ok = kq["la_ngay"] == mong_doi
        dat = dat and ok
        print(f"  [{'OK ' if ok else 'SAI'}] {ten:22s} -> la_ngay={kq['la_ngay']} "
              f"đợt={kq['so_dot']} khoảng={kq['khoang_trung_vi_s']} CV={kq['cv']} {kq['ly_do']}")
    print("TỰ KIỂM: " + ("PASS" if dat else "FAIL"))
    return 0 if dat else 1


if __name__ == "__main__":
    import sys
    if "--tu-kiem" in sys.argv:
        sys.exit(_tu_kiem())
    print(__doc__)
