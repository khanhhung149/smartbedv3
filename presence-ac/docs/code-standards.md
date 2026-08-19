# Code Standards & Conventions

**Audience**: Contributors and maintainers. Enforce during code review.

## Principles

1. **YAGNI**: Don't add abstractions "just in case" — add them when real duplication appears
2. **KISS**: Prefer simple, obvious code over clever solutions
3. **No panics**: Backend never panics; firmware loops forever or returns 0
4. **Testable**: Write code that can be tested (dependency injection, pure functions where possible)
5. **Documented**: Comments explain **why**, not what (code already says what)

## Language-Specific Standards

### Go (Backend)

**File organization**:
- One concern per package (e.g., `statemachine` is separate from `api`)
- Package `main` only in `cmd/` directories
- Test files live alongside source (`machine.go` + `machine_test.go`)

**Naming**:
```go
// Functions & variables: camelCase
func (m *Machine) OnPresence(present bool) *string

// Interfaces: -er suffix
type StateProvider interface {
    Snapshot() Snapshot
}

// Constants: SCREAMING_SNAKE_CASE
const DefaultEnterWindow = 15 * time.Second

// Packages: lowercase, single word if possible
package statemachine  // good
package state_machine // bad
```

**Error handling**:
```go
// Always check errors, never ignore
if err != nil {
    log.Printf("context: %v", err)
    // Return early, don't nest
    return
}

// Use error wrapping (Go 1.13+)
if err != nil {
    return fmt.Errorf("operation: %w", err)
}

// No panics in backend (except init)
// if condition { panic("...") }  // ❌ NEVER

// Backend exceptions: use 500, 503, etc.
http.Error(w, "service unavailable", http.StatusServiceUnavailable)
```

**Concurrency**:
```go
// Protect shared state with sync.RWMutex
type Machine struct {
    mu sync.RWMutex
    // ...
}

func (m *Machine) Snapshot() Snapshot {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return Snapshot{...}
}

// Channels for goroutine coordination (not locks)
// Goroutines should not modify mutable state directly
```

**Testing**:
```go
// Table-driven tests for multiple cases
var tests = []struct {
    name     string
    input    int
    expected string
}{
    {"case 1", 5, "ok"},
    {"case 2", -1, "error"},
}

for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        got := Function(tt.input)
        if got != tt.expected {
            t.Errorf("got %q, want %q", got, tt.expected)
        }
    })
}
```

### Dart (Flutter App)

**Naming**:
```dart
// Classes: PascalCase
class HomeScreen extends ConsumerStatefulWidget

// Functions/methods: camelCase
void updateState()

// Variables: camelCase
final int screenWidth = 400;
final _private = "not exported";

// Files: snake_case.dart
home_screen.dart
api_client.dart
```

**Riverpod providers**:
```dart
// Type providers for testability
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

// State providers for mutable state
final userNameProvider = StateProvider<String>((ref) => "");

// FutureProviders for async operations
final stateSnapshotProvider = FutureProvider<Snapshot>((ref) async {
    final client = ref.watch(apiClientProvider);
    return await client.fetchState();
});

// Invalidate on manual refresh
ref.refresh(stateSnapshotProvider);
```

**Error handling**:
```dart
// Use try/catch, never let exceptions propagate silently
try {
    final data = await fetchData();
} on SocketException catch (e) {
    log("network error: $e");
    // Show UI toast or fallback state
} catch (e) {
    log("unexpected error: $e");
}

// Never use bare `catch (e) { }`—always specify exception type
```

**Testing**:
```dart
// Golden tests for UI
testWidgets('HomeScreen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await expectLater(find.byType(MyApp), matchesGoldenFile('home.png'));
});
```

### C/C++ (Firmware)

**Naming**:
```cpp
// Macros: SCREAMING_SNAKE_CASE
#define MQTT_PORT 1883
#define CFG_I2S_SCK 5

// Functions: camelCase
void setupWiFi()
void handleMotion()

// Variables: camelCase (no Hungarian notation)
int motionPin = 25;
unsigned long lastMotionMs = 0;

// Global state: rare, but if needed, prefix with `g_`
static int g_acState = 0;  // file-scope static
```

**Memory & performance**:
```cpp
// No malloc/new in loop; use stack or static allocation
void processAudio(uint16_t* buffer, size_t len) {
    // OK: fixed-size array on stack
    uint8_t features[40];
    // Not OK: malloc in loop
    // uint8_t* features = malloc(40);
}

// Avoid String class in tight loops (high memory fragmentation)
// Use const char* or char arrays
void logEvent(const char* msg) { Serial.println(msg); }
```

**Error handling**:
```cpp
// No exceptions; use return codes or global state
int connectMQTT() {
    if (!mqttClient.connect(MQTT_HOST, MQTT_PORT)) {
        Serial.println("MQTT connect failed");
        return -1;
    }
    return 0;
}

// For critical failures, loop forever (watchdog will reboot if needed)
if (!LittleFS.begin()) {
    while (1) { Serial.println("FS failed"); delay(1000); }
}
```

**Timing**:
```cpp
// Use unsigned long for millis(), not int (overflow risk)
unsigned long start = millis();
if (millis() - start > 1000) { /* 1 second elapsed */ }

// No delay() in loops; use time-based state machine instead
unsigned long lastEventMs = 0;
const unsigned long DEBOUNCE_MS = 100;
if (digitalRead(pin) && (millis() - lastEventMs > DEBOUNCE_MS)) {
    handleEvent();
    lastEventMs = millis();
}
```

### Python (ASR Service)

**Naming**:
```python
# Functions: snake_case
def transcribe_audio(file_path: str) -> str:

# Classes: PascalCase
class WhisperClient:

# Constants: SCREAMING_SNAKE_CASE
MAX_FILE_SIZE_MB = 50
DEFAULT_TIMEOUT_SECONDS = 30

# Private functions/vars: leading underscore
def _preprocess_audio(data):
```

**Type hints**:
```python
# Always use type hints for public functions
def score_samples(folder: str, output: str) -> Dict[str, float]:

# Avoid `Any` if possible; be specific
from typing import List, Dict, Optional
def process(items: List[str], config: Optional[Dict[str, int]]) -> None:
```

**Testing**:
```python
# Unit tests with pytest
def test_transcribe_vietnamese():
    result = transcribe_audio("sample.wav")
    assert "bật" in result or "tắt" in result

# Fixtures for reusable setup
@pytest.fixture
def mock_model():
    return MagicMock()
```

## MQTT Payload Standards

**All payloads: JSON with `ts` field**:
```json
{
  "ts": 1700000000000,
  "<key>": "<value>"
}
```

**Timestamp format**: Unix epoch in **milliseconds** (not seconds)

**Topics**: lowercase kebab-case, max 4 segments
```
home/room/presence      ✅ good
home/room/ac-cmd        ❌ bad (use underscore: ac_cmd)
home/room/ac_cmd        ✅ good
home/room/ac/cmd        ❌ bad (too many segments)
```

**Publish contracts** (documented in `firmware/mqtt/README.md`):
- Verify all topic names match before merge
- If changing topic, update both firmware + docs + backend

## Testing Standards

### Go Backend

**Minimum coverage**:
- State machine transitions (all paths in evaluate())
- MQTT payload parsing (valid + invalid JSON)
- Voice command parsing (at least 20 test cases per language)
- Store operations (create, read, list, boundaries)

**Run before commit**:
```bash
go test ./...
go vet ./...
go fmt ./...
```

### Firmware (PlatformIO)

**Minimum checks**:
- Compile without warnings (all platforms)
- `pio check` (static analysis)
- Verify on hardware: serial monitor output, MQTT broker observation

**No unit tests on target** (embedded constraint); instead:
- Test logic in Go (cross-compile state machine validation if needed)
- Hardware validation via MQTT trace + serial logs

### Flutter App

**Minimum checks**:
- Golden tests for key screens (Home, Settings)
- Riverpod provider tests (mock API client)
- `flutter analyze` (no analyzer warnings)

**Run before commit**:
```bash
flutter test
flutter analyze
```

## Code Review Checklist

- [ ] Naming: does it follow language conventions?
- [ ] Testing: are edge cases covered?
- [ ] Errors: are all errors handled (no silent failures)?
- [ ] Secrets: no hardcoded API keys, passwords, tokens?
- [ ] Performance: any O(n²) loops or unbounded allocations?
- [ ] Concurrency: mutexes protecting shared state?
- [ ] Documentation: comments explain **why**, not what?
- [ ] Commits: are messages conventional (feat/fix/docs)?

## Commit Message Format

Use conventional commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: new feature
- `fix`: bug fix
- `docs`: documentation
- `style`: formatting (no logic change)
- `refactor`: code reorganization (no behavior change)
- `test`: add/update tests
- `ci`: CI/CD config
- `chore`: build, deps, tooling

**Scope** (optional): module name (api, statemachine, app)

**Subject**: imperative, present tense, lowercase, no period
```
✅ feat(voice): add Vietnamese wakeword detection
❌ feat(voice): Added wakeword feature
❌ feat(voice): Wakeword detection.
```

**Body** (if significant):
- Explain **why**, not what
- Reference issue numbers (#123)
- Mention breaking changes (BREAKING CHANGE:)

**Example**:
```
feat(statemachine): increase ExitTimeout from 30s to 60s

Radar shows false presence drops every 20-30s when door opens.
New 60s timeout allows 2-3 drops without toggling occupancy.

Fixes #42
```

## Documentation Standards

**Inline comments**:
```go
// ✅ Explains why
// Presence can false-trigger through walls (24GHz penetration).
// Require motion confirmation within 15s to avoid spurious AC toggles.
if m.present && !m.occupied {
    if now.Sub(m.lastMotionAt) <= m.cfg.EnterWindow {
        m.occupied = true
    }
}

// ❌ Restates code
// Set occupied to true if present and motion recent
```

**Function/method comments**:
```go
// OnPresence updates the presence state and evaluates AC decision.
// Returns a non-nil pointer to "on" or "off" if AC state should change.
func (m *Machine) OnPresence(present bool, ts int64, now time.Time) *string
```

**File headers**:
```go
// Package statemachine implements a tick-based state machine for
// occupancy detection. It fuses radar presence and motion data to
// decide AC on/off with hysteresis to prevent flapping.
package statemachine
```

---

**Last updated**: 2026-08-10
