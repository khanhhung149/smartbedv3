/**
 * News article metadata and body module loader.
 *
 * Article bodies live in ./bodies/{slug}.{lang}.svelte
 * Sub-agents B-E add body files here; the glob loader auto-wires them.
 *
 * Usage:
 *   import { ARTICLES, getArticle, listArticles } from '$lib/news/articles';
 */
import type { Component } from 'svelte';
export type ArticleCategory = 'sleep_tech_ai' | 'sleep_care' | 'elderly_care';
export type ArticleLang = 'en' | 'ja' | 'th' | 'vi';

export type ArticleMeta = {
  slug: string;
  category: ArticleCategory;
  date: string; // ISO YYYY-MM-DD
  read_minutes: number;
  feature_image: string; // path under /generated/news-{slug}.png
  i18n: Record<
    ArticleLang,
    {
      title: string;
      excerpt: string; // 2-sentence summary for index card + meta description
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      body_module?: () => Promise<{ default: Component<any> }>;
    }
  >;
};

// --- Dynamic body loader via Vite glob ---
// Keys: ./bodies/{slug}.{lang}.svelte
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const bodyModules = import.meta.glob<{ default: Component<any> }>('./bodies/*.svelte', { eager: false });

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function bodyLoader(slug: string, lang: ArticleLang): (() => Promise<{ default: Component<any> }>) | undefined {
  const key = `./bodies/${slug}.${lang}.svelte`;
  const loader = bodyModules[key];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return loader ? (loader as () => Promise<{ default: Component<any> }>) : undefined;
}

// --- Article data ---

export const ARTICLES: ArticleMeta[] = [
  // ── Sleep Tech AI (7) ──
  {
    slug: 'how-ai-revolutionizes-sleep-monitoring',
    category: 'sleep_tech_ai',
    date: '2026-01-08',
    read_minutes: 10,
    feature_image: '/generated/news-how-ai-revolutionizes-sleep-monitoring.png',
    i18n: {
      en: {
        title: 'How AI Is Revolutionizing Sleep Monitoring',
        excerpt:
          'Machine learning models can now detect sleep stages, apnea events, and cardiac arrhythmias from a thin pad under your mattress. We explore the algorithms reshaping bedtime health.',
      },
      ja: {
        title: 'AIはいかにして睡眠モニタリングを革新しているか',
        excerpt:
          '機械学習モデルがマットレス下の薄いパッドから睡眠段階、無呼吸イベント、不整脈を検出できるようになった。就寝時の健康を再定義するアルゴリズムを探る。',
      },
      th: {
        title: 'AI กำลังปฏิวัติการติดตามการนอนอย่างไร',
        excerpt:
          'โมเดลการเรียนรู้ของเครื่องสามารถตรวจจับระยะการนอน เหตุการณ์หยุดหายใจ และหัวใจเต้นผิดปกติจากแผ่นบางใต้ที่นอนได้แล้ว เราสำรวจอัลกอริทึมที่กำลังเปลี่ยนแปลงสุขภาพยามนอน',
      },
      vi: {
        title: 'AI Đang Cách Mạng Hóa Theo Dõi Giấc Ngủ Như Thế Nào',
        excerpt:
          'Các mô hình học máy giờ đây có thể phát hiện giai đoạn ngủ, sự kiện ngưng thở và rối loạn nhịp tim từ tấm pad mỏng dưới đệm. Chúng ta khám phá các thuật toán đang định hình lại sức khỏe lúc ngủ.',
      },
    },
  },
  {
    slug: 'heart-rate-variability-explained',
    category: 'sleep_tech_ai',
    date: '2026-01-22',
    read_minutes: 9,
    feature_image: '/generated/news-heart-rate-variability-explained.png',
    i18n: {
      en: {
        title: 'Heart Rate Variability Explained: The Secret Signal in Your Sleep',
        excerpt:
          'HRV measures the millisecond-by-millisecond variation between heartbeats and serves as a window into your autonomic nervous system. Understanding it can transform how you interpret your nightly data.',
      },
      ja: {
        title: '心拍変動（HRV）解説：睡眠に潜む秘密のシグナル',
        excerpt:
          'HRVは拍動間のミリ秒単位の変動を測り、自律神経系への窓口となる。これを理解することで夜間データの解釈が根本から変わる。',
      },
      th: {
        title: 'Heart Rate Variability อธิบาย: สัญญาณลับในการนอนของคุณ',
        excerpt:
          'HRV วัดการเปลี่ยนแปลงระหว่างการเต้นของหัวใจในระดับมิลลิวินาที และเป็นหน้าต่างสู่ระบบประสาทอัตโนมัติของคุณ การเข้าใจมันสามารถเปลี่ยนแปลงวิธีที่คุณตีความข้อมูลกลางคืนได้',
      },
      vi: {
        title: 'Biến Thiên Nhịp Tim Giải Thích: Tín Hiệu Bí Mật Trong Giấc Ngủ',
        excerpt:
          'HRV đo sự biến thiên từng mili giây giữa các nhịp đập và là cửa sổ nhìn vào hệ thần kinh tự chủ. Hiểu nó có thể thay đổi cách bạn diễn giải dữ liệu đêm của mình.',
      },
    },
  },
  {
    slug: 'wearables-vs-non-contact-sensors',
    category: 'sleep_tech_ai',
    date: '2026-02-05',
    read_minutes: 11,
    feature_image: '/generated/news-wearables-vs-non-contact-sensors.png',
    i18n: {
      en: {
        title: 'Wearables vs. Non-Contact Sensors: Which Wins for Sleep Tracking?',
        excerpt:
          'Smartwatches dominate fitness tracking, but non-contact under-mattress sensors offer unique advantages for sleep health — no charging, no pressure points, no forgetting. We compare accuracy, comfort, and clinical validity.',
      },
      ja: {
        title: 'ウェアラブルvs非接触センサー：睡眠トラッキングに最適なのはどちら？',
        excerpt:
          'スマートウォッチはフィットネス追跡で優位だが、非接触のマットレス下センサーは充電不要・圧迫ゼロ・忘れなしという独自の優位性を持つ。精度・快適性・臨床的妥当性を比較する。',
      },
      th: {
        title: 'อุปกรณ์สวมใส่ vs เซ็นเซอร์ไร้สัมผัส: อะไรชนะสำหรับการติดตามการนอน?',
        excerpt:
          'สมาร์ทวอทช์ครองตลาดฟิตเนส แต่เซ็นเซอร์ใต้ที่นอนแบบไม่สัมผัสมีข้อได้เปรียบพิเศษ — ไม่ต้องชาร์จ ไม่มีจุดกดทับ ไม่มีการลืม เราเปรียบเทียบความแม่นยำ ความสะดวกสบาย และความถูกต้องทางคลินิก',
      },
      vi: {
        title: 'Thiết Bị Đeo vs Cảm Biến Không Tiếp Xúc: Cái Nào Tốt Hơn Cho Theo Dõi Giấc Ngủ?',
        excerpt:
          'Đồng hồ thông minh thống lĩnh theo dõi thể dục, nhưng cảm biến dưới đệm không tiếp xúc có những ưu điểm độc đáo — không cần sạc, không điểm áp lực, không quên đeo. Chúng ta so sánh độ chính xác, sự thoải mái và hiệu lực lâm sàng.',
      },
    },
  },
  {
    slug: 'privacy-first-sleep-ai',
    category: 'sleep_tech_ai',
    date: '2026-02-19',
    read_minutes: 8,
    feature_image: '/generated/news-privacy-first-sleep-ai.png',
    i18n: {
      en: {
        title: 'Privacy-First Sleep AI: Why Your Biometric Data Should Never Leave Your Home',
        excerpt:
          'Sleep data is among the most intimate data types humans generate. We examine edge-processing architectures, encryption standards, and the ethical case for keeping AI inference local.',
      },
      ja: {
        title: 'プライバシー優先の睡眠AI：生体データをなぜ家の外に出してはいけないか',
        excerpt:
          '睡眠データは人間が生成する中で最もプライベートなデータの一つだ。エッジ処理アーキテクチャ、暗号化標準、AIを手元に置く倫理的根拠を検証する。',
      },
      th: {
        title: 'Sleep AI ที่ให้ความสำคัญกับความเป็นส่วนตัว: ทำไมข้อมูลชีวภาพของคุณจึงไม่ควรออกจากบ้าน',
        excerpt:
          'ข้อมูลการนอนเป็นหนึ่งในประเภทข้อมูลที่ส่วนตัวที่สุดที่มนุษย์สร้าง เราตรวจสอบสถาปัตยกรรมการประมวลผล edge มาตรฐานการเข้ารหัส และกรณีด้านจริยธรรมสำหรับการเก็บการอนุมาน AI ไว้ภายในเครื่อง',
      },
      vi: {
        title: 'AI Giấc Ngủ Ưu Tiên Quyền Riêng Tư: Tại Sao Dữ Liệu Sinh Trắc Không Nên Rời Khỏi Nhà Bạn',
        excerpt:
          'Dữ liệu giấc ngủ là một trong những loại dữ liệu riêng tư nhất con người tạo ra. Chúng ta xem xét kiến trúc xử lý biên, tiêu chuẩn mã hóa, và lập luận đạo đức cho việc giữ suy luận AI cục bộ.',
      },
    },
  },
  {
    slug: 'ballistocardiography-future-sleep-tech',
    category: 'sleep_tech_ai',
    date: '2026-03-04',
    read_minutes: 12,
    feature_image: '/generated/news-ballistocardiography-future-sleep-tech.png',
    i18n: {
      en: {
        title: 'Ballistocardiography: The 70-Year-Old Science Powering Tomorrow\'s Sleep Tech',
        excerpt:
          'BCG captures the micro-mechanical forces of each heartbeat through any surface. Once confined to hospital carts, it now fits under a mattress and powers AI sleep monitoring for millions.',
      },
      ja: {
        title: '心弾動図（BCG）：明日の睡眠テクノロジーを支える70年前の科学',
        excerpt:
          'BCGは心拍ごとの微小な力学的力をあらゆる面から捉える。かつては病院のカートに限られていた技術が、今やマットレス下に収まり数百万人のAI睡眠モニタリングを支えている。',
      },
      th: {
        title: 'Ballistocardiography: วิทยาศาสตร์อายุ 70 ปีที่ขับเคลื่อนเทคโนโลยีการนอนแห่งอนาคต',
        excerpt:
          'BCG จับแรงกลไกขนาดเล็กของแต่ละการเต้นของหัวใจผ่านพื้นผิวใดก็ได้ เทคโนโลยีที่เคยจำกัดอยู่แต่ในโรงพยาบาลตอนนี้พอดีกับใต้ที่นอนและขับเคลื่อนการติดตามการนอน AI สำหรับล้านคน',
      },
      vi: {
        title: 'Ballistocardiography: Khoa Học 70 Năm Tuổi Đang Cung Cấp Năng Lượng Cho Công Nghệ Giấc Ngủ Tương Lai',
        excerpt:
          'BCG nắm bắt các lực cơ học vi mô của mỗi nhịp tim qua bất kỳ bề mặt nào. Từng bị giới hạn trong các xe đẩy bệnh viện, nay nó vừa vặn dưới đệm và cung cấp năng lượng cho theo dõi giấc ngủ AI cho hàng triệu người.',
      },
    },
  },
  {
    slug: 'realtime-vital-alerts-balance',
    category: 'sleep_tech_ai',
    date: '2026-03-18',
    read_minutes: 9,
    feature_image: '/generated/news-realtime-vital-alerts-balance.png',
    i18n: {
      en: {
        title: 'The Art of the Alert: Balancing Sensitivity and Calm in Real-Time Vital Monitoring',
        excerpt:
          'Too many alerts cause anxiety; too few miss critical events. How SleepTech\'s adaptive threshold engine learns your personal baseline to notify caregivers at precisely the right moment.',
      },
      ja: {
        title: 'アラートの技術：リアルタイムバイタルモニタリングにおける感度と平穏のバランス',
        excerpt:
          'アラートが多すぎれば不安を招き、少なすぎれば重大なイベントを見落とす。SleepTechの適応型閾値エンジンがあなたの個人的なベースラインを学習し、最適なタイミングで介護者に通知する仕組みを解説。',
      },
      th: {
        title: 'ศิลปะของการแจ้งเตือน: สมดุลระหว่างความไวและความสงบในการตรวจสอบสัญญาณชีพแบบเรียลไทม์',
        excerpt:
          'การแจ้งเตือนมากเกินไปก่อให้เกิดความวิตกกังวล น้อยเกินไปก็พลาดเหตุการณ์สำคัญ เครื่องยนต์ threshold แบบปรับตัวของ SleepTech เรียนรู้เส้นฐานส่วนบุคคลของคุณเพื่อแจ้งผู้ดูแลในช่วงเวลาที่เหมาะสม',
      },
      vi: {
        title: 'Nghệ Thuật Cảnh Báo: Cân Bằng Độ Nhạy Và Sự Bình Tĩnh Trong Theo Dõi Sinh Hiệu Thời Gian Thực',
        excerpt:
          'Quá nhiều cảnh báo gây lo lắng; quá ít bỏ lỡ các sự kiện quan trọng. Cách công cụ ngưỡng thích ứng của SleepTech học đường cơ sở cá nhân của bạn để thông báo cho người chăm sóc vào đúng thời điểm.',
      },
    },
  },
  {
    slug: 'sleep-apnea-detection-at-home',
    category: 'sleep_tech_ai',
    date: '2026-04-01',
    read_minutes: 10,
    feature_image: '/generated/news-sleep-apnea-detection-at-home.png',
    i18n: {
      en: {
        title: 'Detecting Sleep Apnea at Home: What AI Can — and Cannot — Do',
        excerpt:
          'Over a billion people may have undiagnosed sleep apnea. Non-contact sensors and AI pattern recognition are pushing early detection into every bedroom, but knowing the limits is as important as knowing the capabilities.',
      },
      ja: {
        title: '自宅での睡眠時無呼吸検出：AIにできること・できないこと',
        excerpt:
          '世界で10億人以上が未診断の睡眠時無呼吸を抱えている可能性がある。非接触センサーとAIパターン認識が早期発見をすべての寝室に届けようとしているが、限界を知ることも能力を知ることと同様に重要だ。',
      },
      th: {
        title: 'การตรวจจับภาวะหยุดหายใจขณะนอนที่บ้าน: สิ่งที่ AI ทำได้ — และทำไม่ได้',
        excerpt:
          'คนมากกว่าหนึ่งพันล้านคนอาจมีภาวะหยุดหายใจขณะนอนที่ยังไม่ได้รับการวินิจฉัย เซ็นเซอร์ไร้สัมผัสและการรู้จำรูปแบบ AI กำลังผลักดันการตรวจจับแต่เนิ่นๆ เข้าสู่ห้องนอนทุกห้อง แต่การรู้ขีดจำกัดก็สำคัญพอๆ กับการรู้ความสามารถ',
      },
      vi: {
        title: 'Phát Hiện Ngưng Thở Khi Ngủ Tại Nhà: AI Có Thể — Và Không Thể — Làm Gì',
        excerpt:
          'Hơn một tỷ người có thể mắc chứng ngưng thở khi ngủ chưa được chẩn đoán. Cảm biến không tiếp xúc và nhận dạng mẫu AI đang đưa phát hiện sớm vào mọi phòng ngủ, nhưng biết giới hạn cũng quan trọng như biết khả năng.',
      },
    },
  },

  // ── Sleep Care (7) ──
  {
    slug: 'sustainable-sleep-routine-with-data',
    category: 'sleep_care',
    date: '2026-01-15',
    read_minutes: 8,
    feature_image: '/generated/news-sustainable-sleep-routine-with-data.png',
    i18n: {
      en: {
        title: 'Building a Sustainable Sleep Routine Backed by Real Data',
        excerpt:
          'Habits formed without feedback rarely stick. Using your own nightly biometrics to understand which routines genuinely improve your sleep creates lasting behavioral change — not temporary willpower.',
      },
      ja: {
        title: '実データに裏打ちされた持続可能な睡眠ルーティンを作る',
        excerpt:
          'フィードバックなしに形成された習慣はめったに定着しない。自分自身の夜間バイオメトリクスを使って本当に睡眠を改善するルーティンを理解することが、一時的な意志力ではなく永続的な行動変容を生む。',
      },
      th: {
        title: 'สร้างกิจวัตรการนอนที่ยั่งยืนด้วยข้อมูลจริง',
        excerpt:
          'นิสัยที่เกิดขึ้นโดยไม่มีข้อเสนอแนะมักไม่ยั่งยืน การใช้ข้อมูลชีวภาพกลางคืนของคุณเองเพื่อทำความเข้าใจว่ากิจวัตรใดปรับปรุงการนอนได้จริง สร้างการเปลี่ยนแปลงพฤติกรรมที่ยั่งยืน ไม่ใช่ความมุ่งมั่นชั่วคราว',
      },
      vi: {
        title: 'Xây Dựng Thói Quen Ngủ Bền Vững Được Hỗ Trợ Bởi Dữ Liệu Thực',
        excerpt:
          'Những thói quen hình thành không có phản hồi hiếm khi bền lâu. Sử dụng dữ liệu sinh trắc học đêm của chính bạn để hiểu thói quen nào thực sự cải thiện giấc ngủ tạo ra sự thay đổi hành vi lâu dài — không phải ý chí tạm thời.',
      },
    },
  },
  {
    slug: 'hrv-and-sleep-quality',
    category: 'sleep_care',
    date: '2026-01-29',
    read_minutes: 10,
    feature_image: '/generated/news-hrv-and-sleep-quality.png',
    i18n: {
      en: {
        title: 'HRV and Sleep Quality: The Bidirectional Relationship Your Doctor Doesn\'t Talk About',
        excerpt:
          'Poor sleep suppresses heart rate variability, and low HRV predicts worse subsequent sleep. Breaking this cycle requires understanding both sides of the feedback loop — and which interventions work.',
      },
      ja: {
        title: 'HRVと睡眠の質：医師がまだ語らない双方向の関係',
        excerpt:
          '睡眠不足はHRVを低下させ、低HRVは翌日の睡眠悪化を予測する。このサイクルを断ち切るにはフィードバックループの両側を理解し、どの介入が効果的かを知る必要がある。',
      },
      th: {
        title: 'HRV กับคุณภาพการนอน: ความสัมพันธ์สองทิศทางที่หมอยังไม่พูดถึง',
        excerpt:
          'การนอนหลับไม่ดีกดการแปรปรวนของอัตราการเต้นของหัวใจ และ HRV ต่ำทำนายการนอนหลับที่แย่ลงในวันถัดไป การทำลายวงจรนี้ต้องเข้าใจทั้งสองด้านของวงป้อนกลับ และว่าการแทรกแซงใดที่ได้ผล',
      },
      vi: {
        title: 'HRV Và Chất Lượng Giấc Ngủ: Mối Quan Hệ Hai Chiều Mà Bác Sĩ Chưa Nói',
        excerpt:
          'Ngủ kém làm giảm biến thiên nhịp tim, và HRV thấp dự đoán giấc ngủ tệ hơn sau đó. Phá vỡ vòng lặp này đòi hỏi hiểu cả hai phía của vòng phản hồi — và can thiệp nào hoạt động.',
      },
    },
  },
  {
    slug: 'bedroom-climate-and-sleep-stages',
    category: 'sleep_care',
    date: '2026-02-12',
    read_minutes: 9,
    feature_image: '/generated/news-bedroom-climate-and-sleep-stages.png',
    i18n: {
      en: {
        title: 'Bedroom Climate and Sleep Stages: Temperature Is Not Just About Comfort',
        excerpt:
          'Core body temperature drop of 1–2°C is a biological prerequisite for deep sleep onset. Smart climate control that works in sync with your sleep sensor can increase slow-wave sleep by measurable margins.',
      },
      ja: {
        title: '寝室の環境と睡眠段階：温度は快適さだけの問題ではない',
        excerpt:
          '深部体温が1〜2°C下がることは、深い睡眠に入るための生物学的前提条件だ。睡眠センサーと連携したスマート空調は、徐波睡眠を測定可能な水準で増加させることができる。',
      },
      th: {
        title: 'สภาพอากาศในห้องนอนและระยะการนอน: อุณหภูมิไม่ได้เกี่ยวกับความสะดวกสบายเท่านั้น',
        excerpt:
          'อุณหภูมิร่างกายแกนกลางที่ลดลง 1-2°C เป็นข้อกำหนดทางชีววิทยาสำหรับการเริ่มต้นการนอนหลับลึก การควบคุมอุณหภูมิอัจฉริยะที่ทำงานร่วมกับเซ็นเซอร์การนอนสามารถเพิ่มการนอนหลับแบบคลื่นช้าได้',
      },
      vi: {
        title: 'Khí Hậu Phòng Ngủ Và Các Giai Đoạn Giấc Ngủ: Nhiệt Độ Không Chỉ Là Vấn Đề Tiện Nghi',
        excerpt:
          'Nhiệt độ cơ thể lõi giảm 1-2°C là điều kiện sinh học tiên quyết cho sự khởi đầu của giấc ngủ sâu. Kiểm soát khí hậu thông minh đồng bộ với cảm biến giấc ngủ có thể tăng giấc ngủ sóng chậm theo biên độ đo lường được.',
      },
    },
  },
  {
    slug: 'snoring-detection-with-ai',
    category: 'sleep_care',
    date: '2026-02-26',
    read_minutes: 8,
    feature_image: '/generated/news-snoring-detection-with-ai.png',
    i18n: {
      en: {
        title: 'Snoring Detection with AI: From Annoyance Metric to Clinical Indicator',
        excerpt:
          'Snoring intensity, frequency, and acoustic signature can indicate anything from mild positional obstruction to severe apnea. AI trained on thousands of sleep sessions is changing how we interpret nighttime sound.',
      },
      ja: {
        title: 'AIによるいびき検知：迷惑指標から臨床指標へ',
        excerpt:
          'いびきの強度・頻度・音響シグネチャは、軽度の体位性閉塞から重篤な無呼吸まで様々な状態を示し得る。数千の睡眠セッションで訓練されたAIが夜間の音の解釈を変えている。',
      },
      th: {
        title: 'การตรวจจับการกรนด้วย AI: จากตัวชี้วัดความรำคาญสู่ตัวบ่งชี้ทางคลินิก',
        excerpt:
          'ความเข้มข้น ความถี่ และลายเสียงของการกรนสามารถบ่งชี้ได้ตั้งแต่การอุดตันตามท่าทางเล็กน้อยจนถึงภาวะหยุดหายใจรุนแรง AI ที่ฝึกด้วยเซสชันการนอนหลายพันครั้งกำลังเปลี่ยนวิธีที่เราตีความเสียงกลางคืน',
      },
      vi: {
        title: 'Phát Hiện Ngáy Bằng AI: Từ Chỉ Số Phiền Toái Đến Chỉ Số Lâm Sàng',
        excerpt:
          'Cường độ, tần suất và chữ ký âm thanh của tiếng ngáy có thể chỉ ra từ tắc nghẽn tư thế nhẹ đến ngưng thở nghiêm trọng. AI được đào tạo trên hàng nghìn phiên ngủ đang thay đổi cách chúng ta giải thích âm thanh ban đêm.',
      },
    },
  },
  {
    slug: 'mindful-pre-sleep-routines-with-data',
    category: 'sleep_care',
    date: '2026-03-11',
    read_minutes: 7,
    feature_image: '/generated/news-mindful-pre-sleep-routines-with-data.png',
    i18n: {
      en: {
        title: 'Mindful Pre-Sleep Routines, Measured: What the Data Says About Wind-Down Rituals',
        excerpt:
          'Journaling, warm baths, blue-light reduction, and breathing exercises all claim sleep-improvement benefits. We look at what sleep sensor data actually shows when users adopt each habit.',
      },
      ja: {
        title: 'データで見るマインドフルな就寝前ルーティン：就寝準備儀式についてデータが語ること',
        excerpt:
          'ジャーナリング、温浴、ブルーライット遮断、呼吸法はいずれも睡眠改善効果を謳っている。ユーザーが各習慣を取り入れたとき、睡眠センサーデータが実際に何を示すかを検証する。',
      },
      th: {
        title: 'กิจวัตรก่อนนอนแบบมีสติ ที่วัดได้: สิ่งที่ข้อมูลบอกเกี่ยวกับพิธีกรรมผ่อนคลาย',
        excerpt:
          'การเขียนบันทึก การอาบน้ำอุ่น การลดแสงสีน้ำเงิน และการออกกำลังกายหายใจต่างอ้างว่าให้ประโยชน์ในการปรับปรุงการนอน เราดูว่าข้อมูลเซ็นเซอร์การนอนแสดงอะไรจริงๆ เมื่อผู้ใช้นำแต่ละนิสัยมาใช้',
      },
      vi: {
        title: 'Thói Quen Trước Khi Ngủ Có Chánh Niệm, Được Đo Lường: Dữ Liệu Nói Gì Về Nghi Lễ Thư Giãn',
        excerpt:
          'Viết nhật ký, tắm nước ấm, giảm ánh sáng xanh và bài tập thở đều tuyên bố có lợi ích cải thiện giấc ngủ. Chúng ta xem dữ liệu cảm biến giấc ngủ thực sự cho thấy gì khi người dùng áp dụng từng thói quen.',
      },
    },
  },
  {
    slug: 'tracking-elderly-sleep-patterns',
    category: 'sleep_care',
    date: '2026-03-25',
    read_minutes: 10,
    feature_image: '/generated/news-tracking-elderly-sleep-patterns.png',
    i18n: {
      en: {
        title: 'Tracking Elderly Sleep Patterns: What Changes After 65 and Why It Matters',
        excerpt:
          'Aging rewires sleep architecture — earlier bedtimes, lighter stages, more fragmentation. Understanding these normal shifts helps caregivers distinguish healthy aging from early pathology.',
      },
      ja: {
        title: '高齢者の睡眠パターンを追跡する：65歳以降に何が変わり、なぜ重要か',
        excerpt:
          '老化は睡眠構造を書き換える — 早寝、浅い段階、より多い断片化。これらの正常な変化を理解することで、介護者は健康的な老化と早期病変を区別できる。',
      },
      th: {
        title: 'การติดตามรูปแบบการนอนของผู้สูงอายุ: สิ่งที่เปลี่ยนแปลงหลังอายุ 65 ปีและทำไมจึงสำคัญ',
        excerpt:
          'การแก่ชราเขียนใหม่สถาปัตยกรรมการนอน — เวลานอนเร็วขึ้น ระยะนอนตื้นขึ้น แตกกระจายมากขึ้น การเข้าใจการเปลี่ยนแปลงปกติเหล่านี้ช่วยให้ผู้ดูแลแยกแยะการแก่ชราที่ปกติจากพยาธิสภาพในระยะแรก',
      },
      vi: {
        title: 'Theo Dõi Mẫu Giấc Ngủ Của Người Cao Tuổi: Điều Gì Thay Đổi Sau 65 Tuổi Và Tại Sao Quan Trọng',
        excerpt:
          'Lão hóa viết lại kiến trúc giấc ngủ — giờ ngủ sớm hơn, giai đoạn ngủ nông hơn, phân mảnh hơn. Hiểu những thay đổi bình thường này giúp người chăm sóc phân biệt lão hóa lành mạnh với bệnh lý sớm.',
      },
    },
  },
  {
    slug: 'shift-workers-sleep-strategies',
    category: 'sleep_care',
    date: '2026-04-08',
    read_minutes: 9,
    feature_image: '/generated/news-shift-workers-sleep-strategies.png',
    i18n: {
      en: {
        title: 'Shift Workers and Sleep: Data-Backed Strategies for Rotating Schedule Survival',
        excerpt:
          'Shift work disrupts circadian rhythms in ways that accumulate into long-term health risk. Biometric feedback from sleep sensors offers a personalized map for minimizing damage and maximizing recovery.',
      },
      ja: {
        title: 'シフトワーカーと睡眠：シフト制生存のためのデータに基づいた戦略',
        excerpt:
          'シフト勤務は概日リズムを乱し、長期的な健康リスクとして蓄積する。睡眠センサーからの生体フィードバックは、ダメージを最小化しリカバリーを最大化するための個別化されたマップを提供する。',
      },
      th: {
        title: 'คนทำงานกะและการนอน: กลยุทธ์ที่ได้รับการสนับสนุนจากข้อมูลเพื่อการอยู่รอดของตารางหมุนเวียน',
        excerpt:
          'การทำงานกะรบกวนจังหวะชีวิตในแบบที่สะสมเป็นความเสี่ยงต่อสุขภาพระยะยาว ข้อเสนอแนะจากข้อมูลชีวภาพของเซ็นเซอร์การนอนให้แผนที่ส่วนตัวสำหรับการลดความเสียหายและเพิ่มการฟื้นตัวให้สูงสุด',
      },
      vi: {
        title: 'Người Làm Ca Và Giấc Ngủ: Chiến Lược Được Hỗ Trợ Bởi Dữ Liệu Để Tồn Tại Với Lịch Xoay Ca',
        excerpt:
          'Làm ca làm rối loạn nhịp sinh học theo những cách tích lũy thành rủi ro sức khỏe lâu dài. Phản hồi sinh trắc học từ cảm biến giấc ngủ cung cấp bản đồ cá nhân hóa để giảm thiểu tổn hại và tối đa hóa phục hồi.',
      },
    },
  },

  // ── Elderly Care (6) ──
  {
    slug: 'caring-from-afar-night-monitoring',
    category: 'elderly_care',
    date: '2026-01-20',
    read_minutes: 8,
    feature_image: '/generated/news-caring-from-afar-night-monitoring.png',
    i18n: {
      en: {
        title: 'Caring from Afar: How Night Monitoring Bridges the Distance Between Families',
        excerpt:
          'For adult children living hours away from aging parents, the 3 a.m. worry is real. Remote sleep monitoring transforms that anxiety into information — and restores sleep for everyone.',
      },
      ja: {
        title: '遠く離れたケア：夜間モニタリングが家族の距離を橋渡しする方法',
        excerpt:
          '高齢の親から何時間も離れて暮らす子供たちにとって、深夜3時の心配は現実だ。遠隔睡眠モニタリングはその不安を情報に変え、すべての人の睡眠を取り戻す。',
      },
      th: {
        title: 'การดูแลจากระยะไกล: การตรวจสอบกลางคืนเชื่อมระยะห่างระหว่างครอบครัวอย่างไร',
        excerpt:
          'สำหรับลูกผู้ใหญ่ที่อาศัยอยู่ห่างจากพ่อแม่ที่อายุมากหลายชั่วโมง ความกังวลตี 3 นั้นเป็นเรื่องจริง การติดตามการนอนระยะไกลเปลี่ยนความวิตกนั้นเป็นข้อมูล และฟื้นคืนการนอนให้ทุกคน',
      },
      vi: {
        title: 'Chăm Sóc Từ Xa: Theo Dõi Ban Đêm Kết Nối Khoảng Cách Giữa Các Gia Đình Như Thế Nào',
        excerpt:
          'Đối với con cái trưởng thành sống cách cha mẹ già hàng giờ đồng hồ, lo lắng lúc 3 giờ sáng là thực sự. Theo dõi giấc ngủ từ xa biến lo lắng đó thành thông tin — và phục hồi giấc ngủ cho mọi người.',
      },
    },
  },
  {
    slug: 'bed-presence-detection-fall-prevention',
    category: 'elderly_care',
    date: '2026-02-03',
    read_minutes: 9,
    feature_image: '/generated/news-bed-presence-detection-fall-prevention.png',
    i18n: {
      en: {
        title: 'Bed Presence Detection: The Invisible Guardian That Prevents Elderly Falls',
        excerpt:
          'A significant portion of serious elderly falls occur in the transition from bed to bathroom in the dark. Bed-presence sensors that alert caregivers to unexpected exits are proving to be effective fall-prevention tools.',
      },
      ja: {
        title: '在床検知：高齢者の転倒を防ぐ目に見えない守護者',
        excerpt:
          '深刻な高齢者転倒の多くは、暗闇の中でのベッドからトイレへの移動中に起きる。予期しない離床を介護者に通知する在床センサーは、効果的な転倒防止ツールとして実証されつつある。',
      },
      th: {
        title: 'การตรวจจับการอยู่บนเตียง: ผู้พิทักษ์ที่มองไม่เห็นที่ป้องกันการหกล้มของผู้สูงอายุ',
        excerpt:
          'การหกล้มรุนแรงของผู้สูงอายุจำนวนมากเกิดขึ้นในการเปลี่ยนจากเตียงไปห้องน้ำในความมืด เซ็นเซอร์ตรวจจับการอยู่บนเตียงที่แจ้งเตือนผู้ดูแลเมื่อมีการออกจากเตียงโดยไม่คาดคิดกำลังพิสูจน์ว่าเป็นเครื่องมือป้องกันการหกล้มที่มีประสิทธิภาพ',
      },
      vi: {
        title: 'Phát Hiện Sự Hiện Diện Trên Giường: Người Bảo Vệ Vô Hình Ngăn Ngã Cho Người Cao Tuổi',
        excerpt:
          'Một phần đáng kể các vụ ngã nghiêm trọng của người cao tuổi xảy ra trong khi chuyển từ giường vào phòng tắm trong bóng tối. Các cảm biến hiện diện trên giường cảnh báo người chăm sóc về việc rời khỏi bất ngờ đang được chứng minh là công cụ phòng ngừa ngã hiệu quả.',
      },
    },
  },
  {
    slug: 'caring-elders-japan-tradition-meets-ai',
    category: 'elderly_care',
    date: '2026-02-17',
    read_minutes: 11,
    feature_image: '/generated/news-caring-elders-japan-tradition-meets-ai.png',
    i18n: {
      en: {
        title: 'Caring for Elders: Where Japanese Tradition Meets AI',
        excerpt:
          'Japan\'s concept of oyakoko — filial devotion — has shaped elder care practices for centuries. We explore how AI sleep technology is becoming the digital expression of that ancient duty of care.',
      },
      ja: {
        title: '高齢者ケア：日本の伝統とAIが出会う場所',
        excerpt:
          '「親孝行」という日本の概念は何世紀にもわたって高齢者ケアを形作ってきた。AI睡眠テクノロジーがその古来の介護義務のデジタル表現となりつつある過程を探る。',
      },
      th: {
        title: 'การดูแลผู้สูงอายุ: ที่ที่ประเพณีญี่ปุ่นพบ AI',
        excerpt:
          'แนวคิด oyakoko ของญี่ปุ่น — ความกตัญญู — ได้กำหนดรูปแบบการดูแลผู้สูงอายุมาหลายศตวรรษ เราสำรวจว่าเทคโนโลยีการนอน AI กำลังกลายเป็นการแสดงออกทางดิจิทัลของหน้าที่ดูแลโบราณนั้นอย่างไร',
      },
      vi: {
        title: 'Chăm Sóc Người Cao Tuổi: Nơi Truyền Thống Nhật Bản Gặp AI',
        excerpt:
          'Khái niệm oyakoko của Nhật Bản — lòng hiếu thảo — đã định hình các thực hành chăm sóc người cao tuổi trong nhiều thế kỷ. Chúng ta khám phá cách công nghệ giấc ngủ AI đang trở thành biểu hiện kỹ thuật số của nghĩa vụ chăm sóc cổ xưa đó.',
      },
    },
  },
  {
    slug: 'yumepad-first-night-setup-elderly-parent',
    category: 'elderly_care',
    date: '2026-03-03',
    read_minutes: 7,
    feature_image: '/generated/news-yumepad-first-night-setup-elderly-parent.png',
    i18n: {
      en: {
        title: 'YumePad First Night: A Setup Guide for Monitoring an Elderly Parent',
        excerpt:
          'Setting up sleep monitoring for a parent can feel invasive if not done with sensitivity. This guide walks through the conversation to have first, the physical setup, and what data to look at in the first week.',
      },
      ja: {
        title: 'YumePad初夜：高齢の親を見守るためのセットアップガイド',
        excerpt:
          '親のための睡眠モニタリング設置は、配慮なく行えば侵入的に感じさせてしまう。まず交わすべき会話、物理的なセットアップ、そして最初の一週間で見るべきデータを丁寧に解説する。',
      },
      th: {
        title: 'YumePad คืนแรก: คู่มือการตั้งค่าสำหรับการติดตามผู้ปกครองสูงอายุ',
        excerpt:
          'การตั้งค่าการติดตามการนอนสำหรับพ่อแม่อาจรู้สึกรุกล้ำหากไม่ทำด้วยความไวต่ออารมณ์ คู่มือนี้อธิบายขั้นตอนการสนทนาที่ต้องทำก่อน การตั้งค่าทางกายภาพ และข้อมูลที่ควรดูในสัปดาห์แรก',
      },
      vi: {
        title: 'YumePad Đêm Đầu Tiên: Hướng Dẫn Cài Đặt Để Theo Dõi Cha Mẹ Già',
        excerpt:
          'Cài đặt theo dõi giấc ngủ cho cha mẹ có thể cảm thấy xâm phạm nếu không được thực hiện với sự nhạy cảm. Hướng dẫn này hướng dẫn qua cuộc trò chuyện cần có trước, cài đặt vật lý và dữ liệu cần xem trong tuần đầu tiên.',
      },
    },
  },
  {
    slug: 'real-family-stories-peace-of-mind',
    category: 'elderly_care',
    date: '2026-04-02',
    read_minutes: 8,
    feature_image: '/generated/news-real-family-stories-peace-of-mind.png',
    i18n: {
      en: {
        title: 'Real Family Stories: The Peace of Mind That Sleep Monitoring Brought',
        excerpt:
          'Three families across Asia share how continuous sleep monitoring transformed their relationship with worry — and with each other — when caring for elderly parents at a distance.',
      },
      ja: {
        title: '家族の実話：睡眠モニタリングがもたらした安心感',
        excerpt:
          'アジア3家族が、高齢の親を遠くから介護するとき、継続的な睡眠モニタリングがどのように不安との関係を — そして互いの関係を — 変えたかを語る。',
      },
      th: {
        title: 'เรื่องราวครอบครัวจริง: ความสงบใจที่การติดตามการนอนนำมา',
        excerpt:
          'ครอบครัวสามครอบครัวทั่วเอเชียแบ่งปันวิธีที่การติดตามการนอนอย่างต่อเนื่องเปลี่ยนแปลงความสัมพันธ์ของพวกเขากับความกังวล — และกับกันและกัน — เมื่อดูแลพ่อแม่สูงอายุจากระยะไกล',
      },
      vi: {
        title: 'Câu Chuyện Gia Đình Thực: Sự An Tâm Mà Theo Dõi Giấc Ngủ Mang Lại',
        excerpt:
          'Ba gia đình khắp châu Á chia sẻ cách theo dõi giấc ngủ liên tục biến đổi mối quan hệ của họ với sự lo lắng — và với nhau — khi chăm sóc cha mẹ già từ xa.',
      },
    },
  },
  {
    slug: 'nighttime-caregiver-burden-tech-relief',
    category: 'elderly_care',
    date: '2026-04-22',
    read_minutes: 10,
    feature_image: '/generated/news-nighttime-caregiver-burden-tech-relief.png',
    i18n: {
      en: {
        title: 'The Nighttime Caregiver Burden: How Technology Is Providing Long-Overdue Relief',
        excerpt:
          'Caregiver burnout is a global health crisis, with nighttime vigilance being the most depleting factor. Smart monitoring tools are beginning to shift this weight, giving caregivers back their sleep.',
      },
      ja: {
        title: '夜間介護者の負担：テクノロジーが遅れを取り戻す支援をする方法',
        excerpt:
          '介護者の燃え尽き症候群は世界的な健康危機であり、夜間の見守りが最も消耗する要因だ。スマートモニタリングツールがこの重荷を分担し始め、介護者に自分の睡眠を取り戻させている。',
      },
      th: {
        title: 'ภาระผู้ดูแลกลางคืน: เทคโนโลยีให้ความช่วยเหลือที่รอคอยมานานอย่างไร',
        excerpt:
          'ความหมดไฟของผู้ดูแลเป็นวิกฤตสุขภาพระดับโลก โดยการเฝ้าระวังกลางคืนเป็นปัจจัยที่ทำให้หมดแรงมากที่สุด เครื่องมือติดตามอัจฉริยะกำลังเริ่มแบ่งเบาภาระนี้ คืนการนอนให้กับผู้ดูแล',
      },
      vi: {
        title: 'Gánh Nặng Người Chăm Sóc Ban Đêm: Công Nghệ Đang Cung Cấp Sự Giải Thoát Đã Lâu Chờ Đợi',
        excerpt:
          'Kiệt sức người chăm sóc là khủng hoảng sức khỏe toàn cầu, với việc cảnh giác ban đêm là yếu tố tiêu hao nhất. Các công cụ theo dõi thông minh đang bắt đầu chuyển gánh nặng này, trả lại giấc ngủ cho người chăm sóc.',
      },
    },
  },
];

// Inject body loaders into article i18n entries
for (const article of ARTICLES) {
  for (const lang of ['en', 'ja', 'th', 'vi'] as ArticleLang[]) {
    const loader = bodyLoader(article.slug, lang);
    if (loader) {
      article.i18n[lang].body_module = loader;
    }
  }
}

export function getArticle(slug: string): ArticleMeta | undefined {
  return ARTICLES.find((a) => a.slug === slug);
}

/** Returns articles sorted newest-first */
export function listArticles(): ArticleMeta[] {
  return [...ARTICLES].sort((a, b) => b.date.localeCompare(a.date));
}
