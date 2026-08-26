// Smartbed sensor stream processor - C++17 implementation
//
// Reads smartbed-sensor-stream.csv and produces:
// - state timeline: EMPTY, LYING_STILL, MOVING, LEAVING
// - respiratory-rate estimates from chest displacement while lying still
// - apnea alerts when breathing amplitude is near zero for >10 seconds
// - HR dropout handling, where hr_bpm=0 is treated as invalid data
//
// The implementation is dependency-free C++17 so it can run on edge Linux boards
// such as Orange Pi / Jetson without Python, pandas, or NumPy.

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <deque>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace smartbed {

constexpr double NaN = std::numeric_limits<double>::quiet_NaN();

struct Thresholds {
    double load_enter_kg = 18.0;
    double load_exit_kg = 8.0;
    double motion_moving = 0.25;
    double motion_leaving = 0.35;
    double load_slope_leaving_kg_s = -8.0;
    double min_state_hold_s = 1.0;
    double apnea_seconds = 10.0;
    double apnea_abs_amp = 0.003;
    double apnea_fraction_of_baseline = 0.20;
    // SpO2 is a corroborating signal for apnea/desaturation. It is not the
    // primary trigger because pulse oximetry can lag breathing changes and can
    // have dropouts, but it strengthens the event evidence when it drops.
    double spo2_low_pct = 94.0;
    double spo2_drop_pct = 3.0;
    double spo2_baseline_window_s = 60.0;
    double spo2_recent_window_s = 20.0;
    double rr_window_s = 30.0;
    double rr_update_s = 5.0;
    double min_peak_distance_s = 1.5;
    double max_peak_distance_s = 10.0;
    double still_motion_for_rr = 0.18;
};

struct SensorSample {
    double timestamp_s = 0.0;
    double loadcell_kg = 0.0;
    int presence = 0;
    double motion_intensity = 0.0;
    double chest_disp = 0.0;
    double hr_bpm = NaN;
    double spo2 = NaN;

    // Cleaned fields.
    double hr_valid = NaN;
    double hr_filled = NaN;
    double spo2_valid = NaN;
    double spo2_filled = NaN;

    // Output fields.
    std::string state = "EMPTY";
    double resp_rate_bpm = NaN;
    std::string resp_quality = "skipped";
    double breath_amp = NaN;
    double apnea_amp_threshold = NaN;
    double spo2_apnea_baseline = NaN;
    double spo2_apnea_recent_min = NaN;
    double spo2_apnea_drop = NaN;
    int spo2_supports_apnea = 0;
};

struct Event {
    double timestamp_s = 0.0;
    std::string kind;
    std::string message;

    std::string toLogLine() const {
        std::ostringstream oss;
        oss << std::fixed << std::setw(8) << std::setprecision(2) << timestamp_s
            << "s | " << std::left << std::setw(12) << kind << " | " << message;
        return oss.str();
    }
};

struct RespirationEstimate {
    double timestamp_s = 0.0;
    double rr_bpm = NaN;
    std::string quality;
    double amplitude = 0.0;
};

struct SpO2Evidence {
    double baseline = NaN;
    double recent_min = NaN;
    double drop_from_baseline = NaN;
    bool supports_apnea = false;
};

static bool isFinite(double x) {
    return std::isfinite(x);
}

static std::string trim(const std::string& s) {
    const auto begin = s.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) return "";
    const auto end = s.find_last_not_of(" \t\r\n");
    return s.substr(begin, end - begin + 1);
}

static std::vector<std::string> splitCsvLine(const std::string& line) {
    // Simple CSV splitter for the HR-provided file: numeric fields, no quoted commas.
    std::vector<std::string> cols;
    std::string cur;
    std::stringstream ss(line);
    while (std::getline(ss, cur, ',')) cols.push_back(trim(cur));
    if (!line.empty() && line.back() == ',') cols.emplace_back("");
    return cols;
}

static double parseDouble(const std::string& s, const std::string& col, std::size_t line_no) {
    const std::string t = trim(s);
    if (t.empty()) return NaN;
    char* end = nullptr;
    const double value = std::strtod(t.c_str(), &end);
    if (end == t.c_str()) {
        std::ostringstream oss;
        oss << "Invalid numeric value in column '" << col << "' at line " << line_no << ": '" << s << "'";
        throw std::runtime_error(oss.str());
    }
    return value;
}

static std::vector<SensorSample> readCsv(const std::string& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("Cannot open CSV: " + path);

    std::string line;
    if (!std::getline(in, line)) throw std::runtime_error("CSV is empty: " + path);
    const auto header = splitCsvLine(line);

    std::map<std::string, std::size_t> idx;
    for (std::size_t i = 0; i < header.size(); ++i) idx[header[i]] = i;

    const std::vector<std::string> required = {
        "timestamp_s", "loadcell_kg", "presence", "motion_intensity", "chest_disp", "hr_bpm", "spo2"
    };
    for (const auto& name : required) {
        if (idx.find(name) == idx.end()) throw std::runtime_error("Missing required column: " + name);
    }

    std::vector<SensorSample> samples;
    std::size_t line_no = 1;
    while (std::getline(in, line)) {
        ++line_no;
        if (trim(line).empty()) continue;
        const auto cols = splitCsvLine(line);
        auto get = [&](const std::string& name) -> std::string {
            const std::size_t pos = idx.at(name);
            return pos < cols.size() ? cols[pos] : "";
        };

        SensorSample s;
        s.timestamp_s = parseDouble(get("timestamp_s"), "timestamp_s", line_no);
        s.loadcell_kg = parseDouble(get("loadcell_kg"), "loadcell_kg", line_no);
        s.presence = parseDouble(get("presence"), "presence", line_no) >= 0.5 ? 1 : 0;
        s.motion_intensity = parseDouble(get("motion_intensity"), "motion_intensity", line_no);
        s.chest_disp = parseDouble(get("chest_disp"), "chest_disp", line_no);
        s.hr_bpm = parseDouble(get("hr_bpm"), "hr_bpm", line_no);
        s.spo2 = parseDouble(get("spo2"), "spo2", line_no);
        samples.push_back(s);
    }

    std::sort(samples.begin(), samples.end(), [](const auto& a, const auto& b) {
        return a.timestamp_s < b.timestamp_s;
    });
    samples.erase(std::unique(samples.begin(), samples.end(), [](const auto& a, const auto& b) {
        return a.timestamp_s == b.timestamp_s;
    }), samples.end());

    return samples;
}

static std::vector<double> interpolateShortGaps(const std::vector<double>& values, std::size_t max_gap_samples) {
    std::vector<double> out(values.size(), NaN);
    if (values.empty()) return out;

    std::vector<std::size_t> valid;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (isFinite(values[i])) valid.push_back(i);
    }
    if (valid.empty()) return out;

    // Copy valid samples.
    for (auto i : valid) out[i] = values[i];

    // Fill leading/trailing short gaps using nearest valid value.
    const std::size_t first = valid.front();
    if (first <= max_gap_samples) {
        for (std::size_t i = 0; i < first; ++i) out[i] = values[first];
    }
    const std::size_t last = valid.back();
    if (values.size() - 1 - last <= max_gap_samples) {
        for (std::size_t i = last + 1; i < values.size(); ++i) out[i] = values[last];
    }

    // Linear interpolation for internal short gaps.
    for (std::size_t k = 0; k + 1 < valid.size(); ++k) {
        const std::size_t a = valid[k];
        const std::size_t b = valid[k + 1];
        const std::size_t gap = b - a - 1;
        if (gap == 0 || gap > max_gap_samples) continue;
        for (std::size_t i = a + 1; i < b; ++i) {
            const double alpha = static_cast<double>(i - a) / static_cast<double>(b - a);
            out[i] = values[a] * (1.0 - alpha) + values[b] * alpha;
        }
    }
    return out;
}

static void cleanSamples(std::vector<SensorSample>& samples) {
    std::vector<double> hr_valid(samples.size(), NaN), spo2_valid(samples.size(), NaN);
    for (std::size_t i = 0; i < samples.size(); ++i) {
        samples[i].presence = samples[i].presence ? 1 : 0;
        if (isFinite(samples[i].hr_bpm) && samples[i].hr_bpm > 0.0) hr_valid[i] = samples[i].hr_bpm;
        if (isFinite(samples[i].spo2) && samples[i].spo2 > 0.0) spo2_valid[i] = samples[i].spo2;
        samples[i].hr_valid = hr_valid[i];
        samples[i].spo2_valid = spo2_valid[i];
    }

    const auto hr_filled = interpolateShortGaps(hr_valid, 50);
    const auto spo2_filled = interpolateShortGaps(spo2_valid, 50);
    for (std::size_t i = 0; i < samples.size(); ++i) {
        samples[i].hr_filled = hr_filled[i];
        samples[i].spo2_filled = spo2_filled[i];
    }
}

class StateClassifier {
public:
    explicit StateClassifier(const Thresholds& thresholds) : t_(thresholds) {}

    std::string classify(const SensorSample& row) {
        const double ts = row.timestamp_s;
        const double load = row.loadcell_kg;
        const int presence = row.presence;
        const double motion = row.motion_intensity;

        load_history_.push_back({ts, load});
        if (load_history_.size() > 30) load_history_.pop_front();

        double slope = 0.0;
        if (load_history_.size() >= 2) {
            const auto& old = load_history_.front();
            if (ts - old.first >= 1.5) slope = (load - old.second) / (ts - old.first);
        }

        if (occupied_) {
            if (presence == 0 && load < t_.load_exit_kg) occupied_ = false;
        } else {
            if ((presence == 1 && load >= t_.load_exit_kg) || load >= t_.load_enter_kg) occupied_ = true;
        }

        std::string candidate;
        if (!occupied_) {
            candidate = "EMPTY";
        } else {
            const bool load_falling_fast = slope <= t_.load_slope_leaving_kg_s;
            const bool near_empty = load < t_.load_enter_kg;
            const bool leaving_by_slope = near_empty && load_falling_fast && motion >= t_.motion_moving;
            const bool leaving_by_radar_loss = near_empty && presence == 0 && state_ != "EMPTY";
            if (leaving_by_slope || leaving_by_radar_loss) candidate = "LEAVING";
            else if (motion >= t_.motion_moving) candidate = "MOVING";
            else candidate = "LYING_STILL";
        }

        if (candidate != state_) {
            const bool enough_hold = (ts - last_state_change_) >= t_.min_state_hold_s;
            const bool urgent = (candidate == "EMPTY" || candidate == "LEAVING");
            if (enough_hold || urgent) {
                state_ = candidate;
                last_state_change_ = ts;
            }
        }
        return state_;
    }

private:
    Thresholds t_;
    std::string state_ = "EMPTY";
    bool occupied_ = false;
    double last_state_change_ = -std::numeric_limits<double>::infinity();
    std::deque<std::pair<double, double>> load_history_;
};

static double percentileFromSorted(const std::vector<double>& sorted_values, double p) {
    if (sorted_values.empty()) return NaN;
    if (sorted_values.size() == 1) return sorted_values.front();

    const double rank = (p / 100.0) * static_cast<double>(sorted_values.size() - 1);
    const std::size_t lo = static_cast<std::size_t>(std::floor(rank));
    const std::size_t hi = static_cast<std::size_t>(std::ceil(rank));
    const double frac = rank - static_cast<double>(lo);
    return sorted_values[lo] * (1.0 - frac) + sorted_values[hi] * frac;
}

static double percentile(std::vector<double> values, double p) {
    // The vector is intentionally passed by value because percentile calculation
    // reorders samples. For this 10-minute/10 Hz task the window sizes are small,
    // but filtering once and sorting once keeps the implementation predictable.
    values.erase(std::remove_if(values.begin(), values.end(), [](double x) { return !isFinite(x); }), values.end());
    if (values.empty()) return NaN;
    std::sort(values.begin(), values.end());
    return percentileFromSorted(values, p);
}

static double windowAmplitude(const std::vector<double>& values) {
    // Robust peak-to-peak amplitude using q95-q05. Filter and sort once instead
    // of computing two separate percentiles with two vector copies/sorts.
    std::vector<double> finite;
    finite.reserve(values.size());
    for (double x : values) {
        if (isFinite(x)) finite.push_back(x);
    }
    if (finite.empty()) return 0.0;
    std::sort(finite.begin(), finite.end());
    const double q95 = percentileFromSorted(finite, 95.0);
    const double q05 = percentileFromSorted(finite, 5.0);
    if (!isFinite(q95) || !isFinite(q05)) return 0.0;
    return std::max(0.0, q95 - q05);
}

static std::vector<double> movingAverage(const std::vector<double>& values, int n) {
    if (n <= 1 || values.empty()) return values;

    // Edge-aware moving average. At the first/last samples, average only real
    // samples inside the truncated window instead of zero/repeated padding.
    // This avoids artificially reducing breathing amplitude near window edges.
    std::vector<double> prefix(values.size() + 1, 0.0);
    for (std::size_t i = 0; i < values.size(); ++i) {
        prefix[i + 1] = prefix[i] + values[i];
    }

    std::vector<double> out(values.size(), 0.0);
    const int left = n / 2;
    const int right = n - 1 - left;
    for (std::size_t i = 0; i < values.size(); ++i) {
        const long begin_long = std::max<long>(0, static_cast<long>(i) - left);
        const long end_long = std::min<long>(static_cast<long>(values.size()) - 1,
                                             static_cast<long>(i) + right);
        const std::size_t begin = static_cast<std::size_t>(begin_long);
        const std::size_t end_exclusive = static_cast<std::size_t>(end_long + 1);
        const double count = static_cast<double>(end_exclusive - begin);
        out[i] = (prefix[end_exclusive] - prefix[begin]) / count;
    }
    return out;
}

static std::vector<double> interpolateFinite(const std::vector<double>& ts, const std::vector<double>& raw) {
    std::vector<double> out = raw;
    std::vector<std::size_t> valid;
    for (std::size_t i = 0; i < raw.size(); ++i) if (isFinite(raw[i])) valid.push_back(i);
    if (valid.empty()) return out;

    for (std::size_t i = 0; i < valid.front(); ++i) out[i] = raw[valid.front()];
    for (std::size_t i = valid.back() + 1; i < raw.size(); ++i) out[i] = raw[valid.back()];
    for (std::size_t k = 0; k + 1 < valid.size(); ++k) {
        const std::size_t a = valid[k], b = valid[k + 1];
        for (std::size_t i = a + 1; i < b; ++i) {
            const double alpha = (ts[i] - ts[a]) / (ts[b] - ts[a]);
            out[i] = raw[a] * (1.0 - alpha) + raw[b] * alpha;
        }
    }
    return out;
}

class RespiratoryRateEstimator {
public:
    explicit RespiratoryRateEstimator(const Thresholds& thresholds) : t_(thresholds) {}

    RespirationEstimate estimate(const std::vector<SensorSample>& samples,
                                 std::size_t start_idx,
                                 std::size_t end_idx,
                                 double current_ts,
                                 bool force = false) {
        if (!force && (current_ts - last_update_ts_) < t_.rr_update_s) {
            return {current_ts, NaN, "not_due", 0.0};
        }
        last_update_ts_ = current_ts;

        if (end_idx < start_idx || (end_idx - start_idx + 1) < 5) {
            return {current_ts, NaN, "not_enough_data", 0.0};
        }

        std::vector<double> ts;
        std::vector<double> raw;
        ts.reserve(end_idx - start_idx + 1);
        raw.reserve(end_idx - start_idx + 1);
        for (std::size_t i = start_idx; i <= end_idx; ++i) {
            ts.push_back(samples[i].timestamp_s);
            raw.push_back(samples[i].chest_disp);
        }

        const std::size_t finite_count = static_cast<std::size_t>(std::count_if(raw.begin(), raw.end(), isFinite));
        if (finite_count < 5) return {current_ts, NaN, "bad_signal", 0.0};
        raw = interpolateFinite(ts, raw);

        const double duration = ts.back() - ts.front();
        if (duration < 12.0) return {current_ts, NaN, "window_too_short", windowAmplitude(raw)};

        std::vector<double> diffs;
        diffs.reserve(ts.size() - 1);
        for (std::size_t i = 1; i < ts.size(); ++i) diffs.push_back(ts[i] - ts[i - 1]);
        const double dt = percentile(diffs, 50.0);
        const double fs = dt > 0.0 ? 1.0 / dt : 10.0;
        const int smooth_n = std::max(1, static_cast<int>(std::llround(0.5 * fs)));

        const auto smoothed = movingAverage(raw, smooth_n);
        const auto trend = movingAverage(smoothed, std::max(smooth_n * 8, 3));
        std::vector<double> detrended(smoothed.size(), 0.0);
        for (std::size_t i = 0; i < smoothed.size(); ++i) detrended[i] = smoothed[i] - trend[i];

        const double amplitude = windowAmplitude(detrended);
        if (amplitude < t_.apnea_abs_amp) return {current_ts, NaN, "low_amplitude", amplitude};

        const int min_dist = std::max(1, static_cast<int>(std::llround(t_.min_peak_distance_s * fs)));
        const double peak_threshold = std::max(0.10 * amplitude, 1e-9);

        std::vector<int> peaks;
        int last_peak = -1000000000;
        for (int i = 1; i + 1 < static_cast<int>(detrended.size()); ++i) {
            const bool is_peak = detrended[i] > detrended[i - 1] && detrended[i] >= detrended[i + 1];
            if (!is_peak || detrended[i] < peak_threshold) continue;
            if (i - last_peak < min_dist) {
                if (!peaks.empty() && detrended[i] > detrended[static_cast<std::size_t>(peaks.back())]) {
                    peaks.back() = i;
                    last_peak = i;
                }
                continue;
            }
            peaks.push_back(i);
            last_peak = i;
        }

        if (peaks.size() < 3) return {current_ts, NaN, "few_peaks", amplitude};

        std::vector<double> intervals;
        for (std::size_t i = 1; i < peaks.size(); ++i) {
            const double interval = ts[static_cast<std::size_t>(peaks[i])] - ts[static_cast<std::size_t>(peaks[i - 1])];
            if (interval >= t_.min_peak_distance_s && interval <= t_.max_peak_distance_s) intervals.push_back(interval);
        }
        if (intervals.size() < 2) return {current_ts, NaN, "bad_intervals", amplitude};

        const double median_period = percentile(intervals, 50.0);
        const double rr = median_period > 0.0 ? 60.0 / median_period : NaN;
        if (!isFinite(rr) || rr < 6.0 || rr > 40.0) return {current_ts, NaN, "out_of_range", amplitude};

        baseline_amplitudes_.push_back(amplitude);
        if (baseline_amplitudes_.size() > 60) baseline_amplitudes_.erase(baseline_amplitudes_.begin());
        return {current_ts, rr, "ok", amplitude};
    }

    double apneaThreshold() const {
        if (baseline_amplitudes_.empty()) return t_.apnea_abs_amp;
        const std::size_t n = baseline_amplitudes_.size();
        const std::size_t start = n > 30 ? n - 30 : 0;
        std::vector<double> recent(baseline_amplitudes_.begin() + static_cast<long>(start), baseline_amplitudes_.end());
        const double baseline = percentile(recent, 50.0);
        return std::max(t_.apnea_abs_amp, t_.apnea_fraction_of_baseline * baseline);
    }

private:
    Thresholds t_;
    double last_update_ts_ = -std::numeric_limits<double>::infinity();
    std::vector<double> baseline_amplitudes_;
};

static std::size_t lowerBoundTimestamp(const std::vector<SensorSample>& samples, double timestamp_s, std::size_t hi_exclusive) {
    std::size_t lo = 0, hi = hi_exclusive;
    while (lo < hi) {
        const std::size_t mid = lo + (hi - lo) / 2;
        if (samples[mid].timestamp_s < timestamp_s) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

static double recentChestAmplitude(const std::vector<SensorSample>& samples, double start_ts, std::size_t end_idx) {
    const std::size_t start_idx = lowerBoundTimestamp(samples, start_ts, end_idx + 1);
    std::vector<double> values;
    values.reserve(end_idx - start_idx + 1);
    for (std::size_t i = start_idx; i <= end_idx; ++i) values.push_back(samples[i].chest_disp);
    return windowAmplitude(values);
}

static SpO2Evidence computeSpO2Evidence(const std::vector<SensorSample>& samples,
                                          double apnea_start_ts,
                                          double current_ts,
                                          std::size_t end_idx,
                                          const Thresholds& thresholds) {
    SpO2Evidence evidence;

    const double baseline_start_ts = apnea_start_ts - thresholds.spo2_baseline_window_s;
    const double baseline_end_ts = apnea_start_ts;
    const std::size_t baseline_start_idx = lowerBoundTimestamp(samples, baseline_start_ts, end_idx + 1);
    const std::size_t recent_start_idx = lowerBoundTimestamp(samples,
        std::max(apnea_start_ts, current_ts - thresholds.spo2_recent_window_s), end_idx + 1);

    std::vector<double> baseline_values;
    std::vector<double> recent_values;
    for (std::size_t k = baseline_start_idx; k <= end_idx; ++k) {
        const auto& sample = samples[k];
        if (!isFinite(sample.spo2_filled) || sample.spo2_filled <= 0.0) continue;
        if (sample.timestamp_s >= baseline_start_ts && sample.timestamp_s < baseline_end_ts) {
            baseline_values.push_back(sample.spo2_filled);
        }
        if (k >= recent_start_idx && sample.timestamp_s <= current_ts) {
            recent_values.push_back(sample.spo2_filled);
        }
    }

    if (!baseline_values.empty()) evidence.baseline = percentile(baseline_values, 50.0);
    if (!recent_values.empty()) evidence.recent_min = *std::min_element(recent_values.begin(), recent_values.end());
    if (isFinite(evidence.baseline) && isFinite(evidence.recent_min)) {
        evidence.drop_from_baseline = evidence.baseline - evidence.recent_min;
    }

    evidence.supports_apnea =
        (isFinite(evidence.recent_min) && evidence.recent_min <= thresholds.spo2_low_pct) ||
        (isFinite(evidence.drop_from_baseline) && evidence.drop_from_baseline >= thresholds.spo2_drop_pct);

    return evidence;
}

static std::vector<Event> processStream(std::vector<SensorSample>& samples, const Thresholds& thresholds) {
    cleanSamples(samples);
    StateClassifier classifier(thresholds);
    RespiratoryRateEstimator rr_estimator(thresholds);

    std::vector<Event> events;
    std::optional<std::string> last_state;
    std::optional<double> apnea_active_since;
    bool apnea_reported = false;
    double rr_suppressed_until = -std::numeric_limits<double>::infinity();
    bool hr_dropout_active = false;
    double hr_dropout_start = 0.0;

    for (std::size_t i = 0; i < samples.size(); ++i) {
        auto& row = samples[i];
        const double ts = row.timestamp_s;
        const std::string state = classifier.classify(row);
        row.state = state;

        if (!last_state.has_value() || state != *last_state) {
            events.push_back({ts, "STATE", (last_state.has_value() ? *last_state : "START") + " -> " + state});
            last_state = state;
        }

        const bool occupied_for_hr = (state == "LYING_STILL" || state == "MOVING" || state == "LEAVING");
        const bool bad_hr = (!isFinite(row.hr_bpm) || row.hr_bpm <= 0.0);
        if (occupied_for_hr && bad_hr) {
            if (!hr_dropout_active) {
                hr_dropout_active = true;
                hr_dropout_start = ts;
            }
        } else if (hr_dropout_active) {
            const double duration = ts - hr_dropout_start;
            if (duration >= 2.0) {
                std::ostringstream msg;
                msg << "hr_bpm=0/invalid for " << std::fixed << std::setprecision(1)
                    << duration << "s while occupied; ignored/interpolated";
                events.push_back({hr_dropout_start, "HR_DROPOUT", msg.str()});
            }
            hr_dropout_active = false;
        }

        double apnea_thr = rr_estimator.apneaThreshold();
        row.resp_rate_bpm = NaN;
        row.resp_quality = "skipped";
        row.breath_amp = NaN;
        row.spo2_apnea_baseline = NaN;
        row.spo2_apnea_recent_min = NaN;
        row.spo2_apnea_drop = NaN;
        row.spo2_supports_apnea = 0;

        const bool still = (state == "LYING_STILL" && row.motion_intensity <= thresholds.still_motion_for_rr);
        if (still) {
            // Detect apnea using a short recent-amplitude window before estimating RR.
            // A 30 s RR window can still contain normal pre-apnea breaths and may
            // produce a mathematically valid rate while the current breathing signal
            // is already flat. Suppressing RR during possible/active apnea keeps the
            // clinical timeline consistent.
            const double recent_amp = recentChestAmplitude(samples, ts - 5.0, i);
            apnea_thr = rr_estimator.apneaThreshold();
            row.breath_amp = recent_amp;

            bool apnea_suspected_now = false;
            if (recent_amp <= apnea_thr) {
                apnea_suspected_now = true;
                if (!apnea_active_since.has_value()) {
                    apnea_active_since = ts;
                    apnea_reported = false;
                } else if (!apnea_reported && ts - *apnea_active_since >= thresholds.apnea_seconds) {
                    const auto spo2_evidence = computeSpO2Evidence(samples, *apnea_active_since, ts, i, thresholds);
                    row.spo2_apnea_baseline = spo2_evidence.baseline;
                    row.spo2_apnea_recent_min = spo2_evidence.recent_min;
                    row.spo2_apnea_drop = spo2_evidence.drop_from_baseline;
                    row.spo2_supports_apnea = spo2_evidence.supports_apnea ? 1 : 0;

                    std::ostringstream msg;
                    msg << "breathing amplitude low for >" << std::fixed << std::setprecision(0)
                        << thresholds.apnea_seconds << "s while occupied/still; since="
                        << std::setprecision(2) << *apnea_active_since << "s, threshold="
                        << std::setprecision(5) << apnea_thr
                        << "; spo2_support=" << (spo2_evidence.supports_apnea ? "yes" : "no");
                    if (isFinite(spo2_evidence.baseline) && isFinite(spo2_evidence.recent_min)) {
                        msg << ", spo2_baseline=" << std::setprecision(1) << spo2_evidence.baseline
                            << "%, spo2_recent_min=" << spo2_evidence.recent_min
                            << "%, drop=" << spo2_evidence.drop_from_baseline << "%";
                    }
                    // Use detection time, not apnea start time, so events.log is naturally chronological.
                    events.push_back({ts, "APNEA_ALERT", msg.str()});
                    apnea_reported = true;
                }
            } else {
                if (apnea_active_since.has_value() && apnea_reported) {
                    events.push_back({ts, "APNEA_END", "breathing amplitude recovered"});
                    rr_suppressed_until = ts + thresholds.rr_update_s;
                }
                apnea_active_since.reset();
                apnea_reported = false;
            }

            if (apnea_suspected_now) {
                row.resp_quality = apnea_reported ? "apnea_active" : "possible_apnea";
            } else if (ts < rr_suppressed_until) {
                row.resp_quality = "post_apnea_recovery";
                row.breath_amp = recent_amp;
            } else {
                const double start_ts = ts - thresholds.rr_window_s;
                const std::size_t start_idx = lowerBoundTimestamp(samples, start_ts, i + 1);

                std::size_t low_motion_count = 0;
                const std::size_t window_count = i >= start_idx ? (i - start_idx + 1) : 0;
                for (std::size_t k = start_idx; k <= i; ++k) {
                    if (samples[k].motion_intensity <= thresholds.still_motion_for_rr) ++low_motion_count;
                }
                const double low_motion_ratio = window_count > 0
                    ? static_cast<double>(low_motion_count) / static_cast<double>(window_count)
                    : 0.0;

                if (low_motion_ratio >= 0.70) {
                    const auto est = rr_estimator.estimate(samples, start_idx, i, ts);
                    row.resp_rate_bpm = est.rr_bpm;
                    row.resp_quality = est.quality;
                    row.breath_amp = est.amplitude;
                    if (isFinite(est.rr_bpm) && est.quality == "ok") {
                        std::ostringstream msg;
                        msg << "RR=" << std::fixed << std::setprecision(1) << est.rr_bpm
                            << " bpm, amp=" << std::setprecision(5) << est.amplitude;
                        events.push_back({ts, "RESP_RATE", msg.str()});
                    }
                } else {
                    row.resp_quality = "motion_in_window";
                    row.breath_amp = recent_amp;
                }
            }
        } else {
            if (apnea_active_since.has_value() && apnea_reported) {
                events.push_back({ts, "APNEA_END", "monitoring stopped due to state change"});
            }
            apnea_active_since.reset();
            apnea_reported = false;
            apnea_thr = rr_estimator.apneaThreshold();
        }
        row.apnea_amp_threshold = apnea_thr;
    }

    if (hr_dropout_active && !samples.empty()) {
        const double duration = samples.back().timestamp_s - hr_dropout_start;
        if (duration >= 2.0) {
            std::ostringstream msg;
            msg << "hr_bpm=0/invalid until end for " << std::fixed << std::setprecision(1) << duration << "s";
            events.push_back({hr_dropout_start, "HR_DROPOUT", msg.str()});
        }
    }

    std::stable_sort(events.begin(), events.end(), [](const Event& a, const Event& b) {
        return a.timestamp_s < b.timestamp_s;
    });
    return events;
}

static std::string csvValue(double x, int precision = 5) {
    if (!isFinite(x)) return "";
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(precision) << x;
    return oss.str();
}

static void ensureDir(const std::string& dir) {
#ifdef _WIN32
    const std::string cmd = "if not exist \"" + dir + "\" mkdir \"" + dir + "\"";
#else
    const std::string cmd = "mkdir -p \"" + dir + "\"";
#endif
    if (std::system(cmd.c_str()) != 0) throw std::runtime_error("Cannot create output directory: " + dir);
}

static void writeProcessedTimeline(const std::vector<SensorSample>& samples, const std::string& outdir) {
    std::ofstream out(outdir + "/processed_timeline.csv");
    if (!out) throw std::runtime_error("Cannot write processed_timeline.csv");
    out << "timestamp_s,loadcell_kg,presence,motion_intensity,chest_disp,hr_bpm,spo2,"
        << "hr_valid,hr_filled,spo2_valid,spo2_filled,state,resp_rate_bpm,resp_quality,breath_amp,apnea_amp_threshold,"
        << "spo2_apnea_baseline,spo2_apnea_recent_min,spo2_apnea_drop,spo2_supports_apnea\n";
    for (const auto& s : samples) {
        out << csvValue(s.timestamp_s, 3) << ','
            << csvValue(s.loadcell_kg, 3) << ','
            << s.presence << ','
            << csvValue(s.motion_intensity, 5) << ','
            << csvValue(s.chest_disp, 5) << ','
            << csvValue(s.hr_bpm, 3) << ','
            << csvValue(s.spo2, 3) << ','
            << csvValue(s.hr_valid, 3) << ','
            << csvValue(s.hr_filled, 3) << ','
            << csvValue(s.spo2_valid, 3) << ','
            << csvValue(s.spo2_filled, 3) << ','
            << s.state << ','
            << csvValue(s.resp_rate_bpm, 3) << ','
            << s.resp_quality << ','
            << csvValue(s.breath_amp, 5) << ','
            << csvValue(s.apnea_amp_threshold, 5) << ','
            << csvValue(s.spo2_apnea_baseline, 3) << ','
            << csvValue(s.spo2_apnea_recent_min, 3) << ','
            << csvValue(s.spo2_apnea_drop, 3) << ','
            << s.spo2_supports_apnea << '\n';
    }
}

static void writeEvents(const std::vector<Event>& events, const std::string& outdir) {
    std::ofstream out(outdir + "/events.log");
    if (!out) throw std::runtime_error("Cannot write events.log");
    for (const auto& e : events) out << e.toLogLine() << '\n';
}

static void writeStateSegments(const std::vector<SensorSample>& samples, const std::string& outdir) {
    std::ofstream out(outdir + "/state_segments.csv");
    if (!out) throw std::runtime_error("Cannot write state_segments.csv");
    out << "start_s,end_s,state\n";
    if (samples.empty()) return;

    double start_ts = samples.front().timestamp_s;
    std::string last_state = samples.front().state;
    double prev_ts = start_ts;
    for (std::size_t i = 1; i < samples.size(); ++i) {
        if (samples[i].state != last_state) {
            out << csvValue(start_ts, 3) << ',' << csvValue(prev_ts, 3) << ',' << last_state << '\n';
            start_ts = samples[i].timestamp_s;
            last_state = samples[i].state;
        }
        prev_ts = samples[i].timestamp_s;
    }
    out << csvValue(start_ts, 3) << ',' << csvValue(prev_ts, 3) << ',' << last_state << '\n';
}


static std::string svgEscape(const std::string& text) {
    std::string out;
    for (char c : text) {
        if (c == '&') out += "&amp;";
        else if (c == '<') out += "&lt;";
        else if (c == '>') out += "&gt;";
        else out += c;
    }
    return out;
}

static double clamp01(double x) {
    return std::max(0.0, std::min(1.0, x));
}

static void writeSvgHeader(std::ofstream& out, int w, int h, const std::string& title) {
    out << "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" << w << "\" height=\"" << h
        << "\" viewBox=\"0 0 " << w << ' ' << h << "\">\n";
    out << "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n";
    out << "<text x=\"" << (w / 2) << "\" y=\"24\" text-anchor=\"middle\" "
        << "font-family=\"Arial, sans-serif\" font-size=\"16\">" << svgEscape(title) << "</text>\n";
}

static double stateToNumber(const std::string& state) {
    if (state == "EMPTY") return 0.0;
    if (state == "LYING_STILL") return 1.0;
    if (state == "MOVING") return 2.0;
    if (state == "LEAVING") return 3.0;
    return 0.0;
}

static void writeStateTimelineSvg(const std::vector<SensorSample>& samples, const std::string& outdir) {
    if (samples.empty()) return;
    std::ofstream out(outdir + "/state_timeline.svg");
    if (!out) throw std::runtime_error("Cannot write state_timeline.svg");

    const int w = 1000, h = 280;
    const int left = 100, right = 30, top = 45, bottom = 45;
    const double t0 = samples.front().timestamp_s;
    const double t1 = samples.back().timestamp_s;
    auto xOf = [&](double t) { return left + (w - left - right) * clamp01((t - t0) / std::max(1e-9, t1 - t0)); };
    auto yOf = [&](double v) { return top + (h - top - bottom) * (1.0 - v / 3.0); };

    writeSvgHeader(out, w, h, "Smartbed state timeline");
    out << "<line x1=\"" << left << "\" y1=\"" << (h - bottom) << "\" x2=\"" << (w - right)
        << "\" y2=\"" << (h - bottom) << "\" stroke=\"#333\"/>\n";
    out << "<line x1=\"" << left << "\" y1=\"" << top << "\" x2=\"" << left
        << "\" y2=\"" << (h - bottom) << "\" stroke=\"#333\"/>\n";

    const std::vector<std::string> labels = {"EMPTY", "LYING_STILL", "MOVING", "LEAVING"};
    for (std::size_t i = 0; i < labels.size(); ++i) {
        const double y = yOf(static_cast<double>(i));
        out << "<line x1=\"" << left << "\" y1=\"" << y << "\" x2=\"" << (w - right)
            << "\" y2=\"" << y << "\" stroke=\"#ddd\"/>\n";
        out << "<text x=\"" << (left - 8) << "\" y=\"" << (y + 4) << "\" text-anchor=\"end\" "
            << "font-family=\"Arial, sans-serif\" font-size=\"11\">" << labels[i] << "</text>\n";
    }

    out << "<polyline fill=\"none\" stroke=\"#111\" stroke-width=\"2\" points=\"";
    double prev_x = xOf(samples.front().timestamp_s);
    double prev_y = yOf(stateToNumber(samples.front().state));
    out << prev_x << ',' << prev_y << ' ';
    for (std::size_t i = 1; i < samples.size(); ++i) {
        const double x = xOf(samples[i].timestamp_s);
        const double y = yOf(stateToNumber(samples[i].state));
        if (std::abs(y - prev_y) > 1e-9) out << x << ',' << prev_y << ' ';
        out << x << ',' << y << ' ';
        prev_x = x;
        prev_y = y;
    }
    (void)prev_x;
    out << "\"/>\n</svg>\n";
}

static void writeChestDispSvg(const std::vector<SensorSample>& samples, const std::string& outdir) {
    if (samples.empty()) return;
    std::ofstream out(outdir + "/chest_disp.svg");
    if (!out) throw std::runtime_error("Cannot write chest_disp.svg");

    const int w = 1000, h = 300;
    const int left = 70, right = 30, top = 45, bottom = 45;
    const double t0 = samples.front().timestamp_s;
    const double t1 = samples.back().timestamp_s;
    double ymin = std::numeric_limits<double>::infinity();
    double ymax = -std::numeric_limits<double>::infinity();
    for (const auto& s : samples) {
        if (isFinite(s.chest_disp)) {
            ymin = std::min(ymin, s.chest_disp);
            ymax = std::max(ymax, s.chest_disp);
        }
    }
    if (!isFinite(ymin) || !isFinite(ymax) || std::abs(ymax - ymin) < 1e-9) { ymin = -1.0; ymax = 1.0; }
    const double pad = 0.05 * (ymax - ymin);
    ymin -= pad; ymax += pad;

    auto xOf = [&](double t) { return left + (w - left - right) * clamp01((t - t0) / std::max(1e-9, t1 - t0)); };
    auto yOf = [&](double v) { return top + (h - top - bottom) * (1.0 - (v - ymin) / std::max(1e-9, ymax - ymin)); };

    writeSvgHeader(out, w, h, "Chest displacement signal");
    out << "<line x1=\"" << left << "\" y1=\"" << (h - bottom) << "\" x2=\"" << (w - right)
        << "\" y2=\"" << (h - bottom) << "\" stroke=\"#333\"/>\n";
    out << "<line x1=\"" << left << "\" y1=\"" << top << "\" x2=\"" << left
        << "\" y2=\"" << (h - bottom) << "\" stroke=\"#333\"/>\n";
    out << "<polyline fill=\"none\" stroke=\"#111\" stroke-width=\"1.2\" points=\"";
    for (const auto& s : samples) if (isFinite(s.chest_disp)) out << xOf(s.timestamp_s) << ',' << yOf(s.chest_disp) << ' ';
    out << "\"/>\n";
    out << "<text x=\"" << left << "\" y=\"" << (h - 12) << "\" font-family=\"Arial, sans-serif\" font-size=\"11\">time (s)</text>\n";
    out << "</svg>\n";
}

static void writeRespRateSvg(const std::vector<SensorSample>& samples, const std::string& outdir) {
    if (samples.empty()) return;
    std::ofstream out(outdir + "/resp_rate.svg");
    if (!out) throw std::runtime_error("Cannot write resp_rate.svg");

    const int w = 1000, h = 300;
    const int left = 70, right = 30, top = 45, bottom = 45;
    const double t0 = samples.front().timestamp_s;
    const double t1 = samples.back().timestamp_s;
    double ymin = 6.0, ymax = 24.0;
    auto xOf = [&](double t) { return left + (w - left - right) * clamp01((t - t0) / std::max(1e-9, t1 - t0)); };
    auto yOf = [&](double v) { return top + (h - top - bottom) * (1.0 - (v - ymin) / std::max(1e-9, ymax - ymin)); };

    writeSvgHeader(out, w, h, "Respiratory-rate estimates while lying still");
    out << "<line x1=\"" << left << "\" y1=\"" << (h - bottom) << "\" x2=\"" << (w - right)
        << "\" y2=\"" << (h - bottom) << "\" stroke=\"#333\"/>\n";
    out << "<line x1=\"" << left << "\" y1=\"" << top << "\" x2=\"" << left
        << "\" y2=\"" << (h - bottom) << "\" stroke=\"#333\"/>\n";
    for (const auto& s : samples) {
        if (isFinite(s.resp_rate_bpm)) {
            out << "<circle cx=\"" << xOf(s.timestamp_s) << "\" cy=\"" << yOf(s.resp_rate_bpm)
                << "\" r=\"2\" fill=\"#111\"/>\n";
        }
    }
    out << "<text x=\"" << left << "\" y=\"" << (h - 12) << "\" font-family=\"Arial, sans-serif\" font-size=\"11\">time (s)</text>\n";
    out << "</svg>\n";
}

static void writeSvgPlots(const std::vector<SensorSample>& samples, const std::string& outdir) {
    writeStateTimelineSvg(samples, outdir);
    writeChestDispSvg(samples, outdir);
    writeRespRateSvg(samples, outdir);
}

struct Args {
    std::string csv_path;
    std::string outdir = "output";
    Thresholds thresholds;
};

static void printUsage(const char* prog) {
    std::cerr << "Usage: " << prog << " <smartbed-sensor-stream.csv> [options]\n\n"
              << "Options:\n"
              << "  --outdir <dir>          Output directory, default: output\n"
              << "  --rr-window-s <sec>     Respiratory-rate window, default: 30\n"
              << "  --apnea-seconds <sec>   Low-breathing duration before alert, default: 10\n"
              << "  --load-enter-kg <kg>    Occupied hysteresis enter threshold, default: 18\n"
              << "  --load-exit-kg <kg>     Empty hysteresis exit threshold, default: 8\n";
}

static Args parseArgs(int argc, char** argv) {
    if (argc < 2) {
        printUsage(argv[0]);
        throw std::runtime_error("Missing CSV path");
    }

    Args args;
    args.csv_path = argv[1];
    for (int i = 2; i < argc; ++i) {
        const std::string key = argv[i];
        auto needValue = [&](const std::string& option) -> std::string {
            if (i + 1 >= argc) throw std::runtime_error("Missing value for " + option);
            return argv[++i];
        };
        if (key == "--outdir") args.outdir = needValue(key);
        else if (key == "--rr-window-s") args.thresholds.rr_window_s = std::stod(needValue(key));
        else if (key == "--apnea-seconds") args.thresholds.apnea_seconds = std::stod(needValue(key));
        else if (key == "--load-enter-kg") args.thresholds.load_enter_kg = std::stod(needValue(key));
        else if (key == "--load-exit-kg") args.thresholds.load_exit_kg = std::stod(needValue(key));
        else if (key == "--help" || key == "-h") {
            printUsage(argv[0]);
            std::exit(0);
        } else {
            throw std::runtime_error("Unknown option: " + key);
        }
    }
    return args;
}

}  // namespace smartbed

int main(int argc, char** argv) {
    try {
        auto args = smartbed::parseArgs(argc, argv);
        auto samples = smartbed::readCsv(args.csv_path);
        auto events = smartbed::processStream(samples, args.thresholds);

        smartbed::ensureDir(args.outdir);
        smartbed::writeProcessedTimeline(samples, args.outdir);
        smartbed::writeStateSegments(samples, args.outdir);
        smartbed::writeEvents(events, args.outdir);
        smartbed::writeSvgPlots(samples, args.outdir);

        std::cout << "Processed " << samples.size() << " samples\n";
        std::cout << "Wrote: " << args.outdir << "/processed_timeline.csv\n";
        std::cout << "Wrote: " << args.outdir << "/state_segments.csv\n";
        std::cout << "Wrote: " << args.outdir << "/events.log\n";
        std::cout << "Wrote: " << args.outdir << "/state_timeline.svg, chest_disp.svg, resp_rate.svg\n\n";
        std::cout << "Key events:\n";
        const std::size_t n = std::min<std::size_t>(30, events.size());
        for (std::size_t i = 0; i < n; ++i) std::cout << events[i].toLogLine() << '\n';
        if (events.size() > n) std::cout << "... " << (events.size() - n) << " more events in events.log\n";
        return 0;
    } catch (const std::exception& ex) {
        std::cerr << "Error: " << ex.what() << '\n';
        return 1;
    }
}
