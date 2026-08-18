"""Phân loại tư thế nằm từ 33 pose landmark của MediaPipe.

⚠️ LUẬT NÀY CHƯA ĐƯỢC KIỂM CHỨNG. Nó là heuristic hình học viết tay, chưa đối chiếu
với một bộ dữ liệu có nhãn nào. Dùng nó để *quan sát* trong lúc nghiệm thu — xem model
có phân biệt được tư thế không — chứ KHÔNG dùng số nó in ra làm bằng chứng độ chính
xác. Muốn có con số tin được thì phải quay lại có nhãn người chấm rồi so, và việc đó
thuộc Phase 05 (`edge/vision/`), không thuộc PoC này.

Giả định bố trí: camera đặt CAO, chĩa thẳng xuống giường. Đổi sang góc ngang thì mọi
ngưỡng dưới đây sai hết, vì chúng dựa trên hình chiếu cơ thể nhìn từ trên.
"""

import math

# Chỉ số landmark trong mô hình pose 33 điểm của MediaPipe.
_NOSE = 0
_LEFT_EYE = 2
_RIGHT_EYE = 5
_LEFT_SHOULDER = 11
_RIGHT_SHOULDER = 12
_LEFT_HIP = 23
_RIGHT_HIP = 24

# Dưới ngưỡng này coi như model không thật sự nhìn thấy điểm đó.
_MIN_VISIBILITY = 0.5

# Luật hai tầng. MỌI ngưỡng dưới đây lấy từ số đo có nhãn, không từ trực giác — phiên
# 17/08 đã ba lần đặt ngưỡng theo cảm tính rồi mới đo, sai cả ba.
#
# Hai tầng giờ dùng CHUNG một tín hiệu `z_vai_lệch` (left_shoulder.z - right_shoulder.z):
# nằm nghiêng thì một vai lùi ra sau vai kia về phía camera, làm hai vai lệch nhau về
# độ sâu. Tín hiệu này vừa cho biết CÓ nghiêng không (tầng 1) vừa cho biết nghiêng BÊN
# nào (tầng 2) — đã thay `vai_thân` làm tầng 1, vì `vai_thân` KHÔNG tái lập giữa các
# phiên:
#
#     lượt     trung vị vai_thân khi NẰM NGỬA
#     2        1.128
#     4        1.006
#     5        0.829   <- rớt xuống DƯỚI ngưỡng 0.89 cũ, dù người nằm y hệt
#
# TẦNG 1 — có đang nằm nghiêng không. |z_vai_lệch|: nằm ngửa thì hai vai ngang nhau về
# độ sâu nên gần 0; nằm nghiêng thì một vai hẳn ra sau nên |z| lớn. Trung vị 17/08:
#
#     lượt      ngửa |z|   trái |z|   phải |z|
#     ratio       0.013      0.225      0.240
#     2           0.026      0.191      0.274
#     4           0.011      0.265      0.274
#     5           0.057      0.211      0.299
#
# Khoảng trống 0.057–0.191, ngưỡng 0.12 nằm giữa. Ghi chú cũ "z hai vai cho cùng dấu
# ở cả hai bên" là SAI: nó ra từ lần đo đầu chạy trên ảnh lật gương, cùng bug đã từng
# làm oan `vai_thân`.
#
# ⚠️ `z` là chiều sâu ước lượng của MediaPipe, kém tin cậy hơn toạ độ 2D. Nếu lượt đo
# kiểm chứng tới mà tầng 1 trượt, quay về `vai_thân` (bản trước lượt 5).
_SIDE_Z_MAGNITUDE = 0.12

# TẦNG 2 — bên nào. Dấu của `z_vai_lệch`: nghiêng trái luôn dương, phải luôn âm:
#
#     lượt            1       2       3       4       5
#     nghiêng trái  +0.103  +0.113  +0.095  +0.225  +0.191   <- luôn dương
#     nghiêng phải  -0.195  -0.249  -0.271  -0.240  -0.274   <- luôn âm
#
# Đổi dấu đúng CẢ NĂM lượt, ngưỡng 0 nằm chính giữa hai cụm. Đã thử `vai_trái_lệch`
# ngưỡng 0.20 và LOẠI: cửa ngưỡng quá hẹp (phải trung vị +0.26..+0.43, chỉ cách ngưỡng
# ~0.06) nên pha nghiêng phải trượt 31% sang nghiêng trái ở lượt đo 2.
_SIDE_Z_OFFSET = 0.0

# Tín hiệu đã thử và LOẠI cho việc phân biệt bên — đừng thử lại:
#
#   mũi lệch    — nghiêng phải dính sát 0 ở 2/5 lượt (trung vị -0.005, -0.062), đuôi
#                 tràn qua ngưỡng. Không đủ biên.
#   vai_trái_lệch — cửa ngưỡng hẹp (xem trên), nghiêng phải trượt 31% ở lượt đo 2.

# Thân ngắn hơn ngần này pixel thì hình chiếu quá nhỏ để tin — người ở xa, hoặc
# landmark loạn. Thà trả "không rõ" còn hơn đoán bừa.
_MIN_TORSO_PX = 40

# Nằm ngửa thì mặt hướng lên camera nên mắt/mũi nhìn thấy được; nằm sấp thì úp mặt
# xuống nệm và cả ba điểm cùng tụt visibility.
_FACE_VISIBLE_THRESHOLD = 0.5

UNKNOWN = "không rõ"
SUPINE = "nằm ngửa"
PRONE = "nằm sấp"
SIDE_LEFT = "nghiêng trái"
SIDE_RIGHT = "nghiêng phải"


def _point(landmark, width: int, height: int) -> tuple[float, float]:
    """Đổi landmark tỉ lệ 0..1 sang pixel.

    Phải nhân theo kích thước thật mới đo được khoảng cách hình học: khung 640x480
    không vuông, dùng thẳng toạ độ chuẩn hoá sẽ bóp méo mọi tỉ lệ.
    """
    return landmark.x * width, landmark.y * height


def _distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _midpoint(a: tuple[float, float], b: tuple[float, float]) -> tuple[float, float]:
    return (a[0] + b[0]) / 2, (a[1] + b[1]) / 2


def side_signals(landmarks, width: int, height: int) -> dict:
    """Đo các tín hiệu ỨNG VIÊN để phân biệt nghiêng trái/phải. Không phán nhãn.

    Có để chọn luật bằng số đo thay vì bằng phỏng đoán. Phiên 17/08 đã hai lần viết
    luật theo trực giác rồi mới đo, và cả hai lần đều sai; lần này đo phân bố tín hiệu
    theo từng tư thế đã biết nhãn trước, rồi mới quyết dùng tín hiệu nào và ngưỡng nào.

    Trả dict các số có dấu. Tín hiệu nào đổi dấu nhất quán giữa nằm nghiêng trái và
    nghiêng phải thì tín hiệu đó dùng được; tín hiệu nào giữ nguyên dấu ở cả hai thì vô
    dụng — đúng như `z` hai vai đã tỏ ra.
    """
    needed = (_LEFT_SHOULDER, _RIGHT_SHOULDER, _LEFT_HIP, _RIGHT_HIP, _NOSE)
    if any(landmarks[i].visibility < _MIN_VISIBILITY for i in needed):
        return {}

    left_shoulder = _point(landmarks[_LEFT_SHOULDER], width, height)
    right_shoulder = _point(landmarks[_RIGHT_SHOULDER], width, height)
    shoulder_mid = _midpoint(left_shoulder, right_shoulder)
    hip_mid = _midpoint(
        _point(landmarks[_LEFT_HIP], width, height),
        _point(landmarks[_RIGHT_HIP], width, height),
    )
    nose = _point(landmarks[_NOSE], width, height)

    # Trục thân, từ hông lên vai. Mọi thứ dưới đây đo tương đối so với trục này nên
    # không phụ thuộc người nằm dọc hay ngang trong khung.
    axis = (shoulder_mid[0] - hip_mid[0], shoulder_mid[1] - hip_mid[1])
    axis_len = math.hypot(*axis) or 1.0

    def _lateral_offset(point: tuple[float, float]) -> float:
        """Khoảng lệch ngang của điểm so với trục thân, chuẩn hoá theo chiều dài thân.

        Dấu cho biết lệch về phía nào của trục — đây mới là thứ 2D thuần, không dùng
        tới `z` ước lượng vốn kém tin cậy của MediaPipe.
        """
        rel = (point[0] - hip_mid[0], point[1] - hip_mid[1])
        cross = axis[0] * rel[1] - axis[1] * rel[0]
        return cross / (axis_len * axis_len)

    return {
        # TẦNG 2: chọn bên. Đổi dấu đúng 5/5 lượt đo 17/08 — trái dương, phải âm.
        # Xem ghi chú ở đầu file.
        "z_vai_lệch": round(landmarks[_LEFT_SHOULDER].z - landmarks[_RIGHT_SHOULDER].z, 3),
        # ĐÃ LOẠI, giữ để đối chứng: nghiêng phải dính sát 0, không đủ biên.
        "mũi_lệch": round(_lateral_offset(nose), 3),
        # ĐÃ LOẠI, giữ để đối chứng: cửa ngưỡng quá hẹp, nghiêng phải trượt 31%.
        "vai_trái_lệch": round(_lateral_offset(left_shoulder), 3),
        # TẦNG 1: tách nằm-nghiêng khỏi nằm-ngửa. Tín hiệu mạnh nhất tìm được
        # (1.114 vs 0.665/0.676). Từng bị bỏ oan vì lần đo đầu chạy trên ảnh lật
        # gương, sai hướng khung, phát hiện 25%.
        #
        # Chuẩn hoá theo chiều dài thân để không phụ thuộc người ở gần hay xa camera.
        "vai_thân": round(_distance(left_shoulder, right_shoulder) / axis_len, 3),
    }


def classify(landmarks, width: int, height: int) -> tuple[str, dict]:
    """Đoán tư thế nằm. Trả về (nhãn, số đo dùng để ra nhãn đó).

    Trả `UNKNOWN` khi thiếu landmark thân — im lặng đoán bừa lúc không nhìn rõ là
    đúng thứ quy tắc dropout của edge/README.md cấm.
    """
    torso_indices = (_LEFT_SHOULDER, _RIGHT_SHOULDER, _LEFT_HIP, _RIGHT_HIP)
    if any(landmarks[i].visibility < _MIN_VISIBILITY for i in torso_indices):
        return UNKNOWN, {"lý_do": "thiếu landmark thân"}

    torso_length = _distance(
        _midpoint(
            _point(landmarks[_LEFT_SHOULDER], width, height),
            _point(landmarks[_RIGHT_SHOULDER], width, height),
        ),
        _midpoint(
            _point(landmarks[_LEFT_HIP], width, height),
            _point(landmarks[_RIGHT_HIP], width, height),
        ),
    )
    if torso_length < _MIN_TORSO_PX:
        return UNKNOWN, {"lý_do": f"thân quá ngắn ({torso_length:.0f}px)"}

    signals = side_signals(landmarks, width, height)
    if not signals:
        return UNKNOWN, {"lý_do": "không thấy mũi"}

    z_offset = signals["z_vai_lệch"]
    metrics = {"z_vai_lệch": z_offset}

    # Tầng 1: |z_vai_lệch| ≥ 0.12 ⇒ hai vai lệch độ sâu ⇒ nằm nghiêng. Tầng 2: dấu —
    # trái dương, phải âm, ngưỡng 0 (xem ghi chú ở đầu file).
    if abs(z_offset) >= _SIDE_Z_MAGNITUDE:
        return (SIDE_LEFT if z_offset > _SIDE_Z_OFFSET else SIDE_RIGHT), metrics

    face_visibility = (
        landmarks[_NOSE].visibility
        + landmarks[_LEFT_EYE].visibility
        + landmarks[_RIGHT_EYE].visibility
    ) / 3
    metrics["mặt_vis"] = round(face_visibility, 2)

    return (SUPINE if face_visibility >= _FACE_VISIBLE_THRESHOLD else PRONE), metrics
