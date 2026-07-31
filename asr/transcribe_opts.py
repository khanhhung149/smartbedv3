"""Tham số transcribe DÙNG CHUNG giữa service (app.py) và bộ chấm điểm (score_samples.py).

Tách riêng vì phép so model chỉ có nghĩa khi hai bên chạy ĐÚNG cùng cấu hình. Để hai bản sao
thì sớm muộn lệch nhau, và con số đo được là con số của một cấu hình không ai đang chạy.
"""

# Mồi từ vựng miền lệnh -> whisper ưu tiên phiên âm đúng cụm này khi nghe gần giống
# (vd "tắt liều hoài" -> "tắt điều hòa"). Rất hiệu quả cho lệnh ngắn cố định.
#
# PHẢI giữ cả động từ bật/tắt trong prompt. Đã thử bỏ chúng (chỉ để danh từ) ngày 30/07 và
# whisper lập tức nghe "Bật" thành "Bọc", "Tắt" thành "Cắt" -> parser loại hết, không lệnh nào
# ra được. Tiếng Việt đơn âm có dấu rất cần mồi động từ; đừng tin lập luận "bật/tắt là từ phổ
# thông nên vốn nghe đúng".
#
# Rủi ro đi kèm: whisper gặp nhiễu thì nhại lại chính prompt này, và câu nhại chứa cả "bật" lẫn
# "tắt". An toàn vì ParseVietCommand (backend/internal/voice/command.go) LOẠI câu chứa cả hai
# động từ — hai lớp độc lập, prompt không phải gánh việc đó.
INITIAL_PROMPT = "Lệnh điều khiển điều hòa: bật điều hòa, tắt điều hòa, bật máy lạnh, tắt máy lạnh."

# vad_filter: Silero VAD bỏ đoạn không có tiếng -> chống whisper "ảo giác" câu rác khi audio
#   gần im (vd tự bịa lời outro YouTube).
# condition_on_previous_text=False: mỗi câu độc lập, không để câu trước kéo lệch câu sau (lệnh
#   AC ngắn, không cần ngữ cảnh).
TRANSCRIBE_OPTS = {
    "language": "vi",
    "vad_filter": True,
    "condition_on_previous_text": False,
    "initial_prompt": INITIAL_PROMPT,
}
