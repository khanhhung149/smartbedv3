# Code Standards & Conventions

This document captures the observed patterns in the codebase. Adhere to these standards when contributing to the backend and firmware.

## Language Mix & Comment Conventions

**Policy**: Code identifiers are **English**; firmware comments and logs are **Vietnamese**.

**Rationale**: The project is developed by a Vietnamese-speaking engineer. Firmware comments document practical debugging and operational notes for local context. Backend code follows Go ecosystem conventions (English-language standard library, idiomatic Go docs). This mix is intentional and should be preserved.

**Application**:
- **Backend (Go)**: All identifiers, package names, function names, and doc comments in English
- **Firmware (C++)**: All identifiers, function names, variable names in English; inline comments and log messages in Vietnamese

---

## Backend (Go)

### Project Layout

Follow the [Go project layout](https://github.com/golang-standards/project-layout) convention:

```
backend/
├── cmd/
│   └── server/
│       └── main.go             # Single entry point per binary
├── internal/                   # Unexported packages (import outside this project = compile error)
│   ├── {feature}/              # One package per logical feature
│   ├── config/
│   ├── events/
│   ├── mqttclient/
│   ├── statemachine/
│   └── api/
└── Dockerfile, docker-compose.yml
```

**Rationale**: Organizes code by responsibility, prevents accidental external imports of internal details, aligns with Go community conventions.

### Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Package | lowercase, no underscore, 1-2 words | `config`, `mqttclient`, `statemachine` |
| Function | camelCase, exported = PascalCase | `func (c *Config) Load()` |
| Variable | camelCase, meaningful names | `enterWindow`, `exitTimeout` |
| Constant | SCREAMING_SNAKE_CASE for module-level constants | `DefaultExitTimeoutS = 60` |
| Error | Prefix with package, end with Err | `config.ErrMissingHost` |
| Interface | PascalCase, describe behavior (often `-er` suffix) | `StateProvider`, `Publisher` |
| Receiver | Short (1-2 letter abbreviation) | `func (c *Client) Connect()` instead of `func (client *Client)` |

### Interfaces at Point of Use

Define interfaces in the package that **uses** them, not in the package that implements them.

**Example**:
```go
// In internal/api/handler.go
type StateProvider interface {
    GetState() (*state.State, error)
}

// In internal/statemachine/machine.go (implements StateProvider but doesn't define it)
type Machine struct { ... }
func (m *Machine) GetState() (*state.State, error) { ... }
```

**Rationale**: Decouples concrete implementation from consumer logic, makes testing easier (inject test doubles), aligns with Go idiom.

### Error Handling

- Explicit error returns; never panic except in `main()` for setup failures
- Errors wrap context: `fmt.Errorf("mqtt: %w", err)` not bare `err`
- Sentinel errors at module level (unexported): `var errConnectionClosed = errors.New("connection closed")`
- Consumer logic checks specific errors: `if errors.Is(err, context.Canceled) { ... }`

### Testing

- **Location**: Test files in same package (e.g., `machine_test.go` in `internal/statemachine/`)
- **Naming**: Test functions are `TestXxx` and sub-tests use scenarios, not numeric IDs
- **Pattern**: Table-driven tests with scenario descriptions:
  ```go
  func TestMachine(t *testing.T) {
      tests := []struct {
          name string
          // fields
      }{
          {name: "enter occupancy on motion within window", ...},
          {name: "exit occupancy after timeout", ...},
      }
      for _, tt := range tests {
          t.Run(tt.name, func(t *testing.T) { ... })
      }
  }
  ```
- **Coverage**: Aim for test-level code coverage of core logic (state machine, config parsing); APIs tested via integration/E2E.

### Logging

Use Go's `log/slog` (1.21+) or similar structured logging:
- Never `fmt.Println` or bare `log.Printf`
- Log levels: DEBUG (verbose), INFO (normal flow), WARN (recoverable issues), ERROR (unrecoverable)
- Structured fields: `slog.String("topic", "home/room/ac_cmd")`

### Dependencies

- **Constraint**: Use only Go standard library + minimal, well-maintained third-party packages
- **Current approved**: `paho.mqtt.golang` (MQTT client), `chi` (HTTP router)
- **Before adding**: Evaluate maturity, maintenance, size, security track record
- **Vendoring**: Use Go modules; avoid vendoring into repo unless offline builds required

### Code Formatting & Lint

- **Format**: Run `gofmt` before commit (or configure IDE to auto-format on save)
- **Linting**: Run `golangci-lint` (if configured); fix all warnings
- **Comments**: Exported functions/types must have doc comments; format: "FunctionName does X."

---

## Firmware (C++ / Arduino / PlatformIO)

### Project Structure

Each node is a standalone PlatformIO project:

```
{node-name}/
├── src/
│   └── main.cpp              # Single file per node (MVP size permits)
├── include/
│   └── config.h.example      # Secrets template (checked in)
│   └── config.h              # Actual secrets (gitignored)
└── platformio.ini            # Board, framework, lib dependencies
```

**Rationale**: Each node has distinct sensors and firmware logic; no code sharing reduces complexity for ESP32-constrained environment.

### Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Function | camelCase | `void sendAC(const char* key)` |
| Variable | camelCase | `long lastMotionTime`, `bool isPresent` |
| Constant | SCREAMING_SNAKE_CASE | `#define PIR_PIN 7` |
| Macro | SCREAMING_SNAKE_CASE | `#define DEBOUNCE_MS 2000` |

### Code Organization

In `main.cpp`:
1. Includes + macros
2. Global variables (WiFi, MQTT, sensor state)
3. Helper function declarations
4. `setup()` — initialization
5. `loop()` — main tick loop
6. Helper function implementations
7. ISR handlers (interrupt service routines)

### Comments & Logging

- **Inline comments**: Vietnamese, explain non-obvious logic (e.g., why a delay is necessary)
- **Function blocks**: Brief Vietnamese header describing purpose
- **Serial debug output**: Vietnamese (e.g., `Serial.println("học IR thành công");`)
- **Critical operations**: Add timestamp/state prefix for troubleshooting (e.g., `[ts] Reconnecting MQTT`)

### Error Handling

- No exceptions (Arduino uses no standard exception support)
- Return `bool` for success/failure from functions
- Log errors to Serial before retrying
- Auto-reconnect loops for MQTT (don't block loop)

### Hard-coded Pins

Document all GPIO assignments in a header comment block at top of `main.cpp`:

```cpp
// ============================================
// ESP32-S2 (Wemos S2 Mini) Pin Assignment
// ============================================
// GPIO7  — PIR motion sensor (input, pull-up)
// GPIO16 — LD2410 radar digital out (input)
// GPIO5  — IR blaster control (output → transistor)
// GPIO15 — IR receiver (input, TSOP38238)
// UART   — GPIO33(TX), GPIO18(RX) for LD2410 UART (if used)
// ============================================
```

### MQTT & Networking

- **Client ID**: Unique per node, set in `config.h` (e.g., `MQTT_CLIENT_ID "home-door-node"`)
- **Payload format**: Hand-built JSON using `snprintf` (no JSON library to save space)
  ```cpp
  char payload[64];
  snprintf(payload, sizeof(payload), R"({"ts":%ld,"motion":true})", millis()/1000);
  mqttClient.publish("home/door/motion", payload, true, 1); // retain=true, QoS=1
  ```
- **Reconnect**: Exponential backoff or simple 5s retry in loop; log each attempt
- **Topics**: Hardcoded or in `config.h`; match backend contract in [`docs/system-architecture.md`](./system-architecture.md)

### Memory & Performance Constraints

- **ESP32-S2**: 320 KB SRAM, limited CPU; avoid large buffers or blocking operations
- **Loop timing**: Keep `loop()` iteration under 100ms; use timers/flags instead of delays
- **String handling**: Use `char[]` buffers with fixed size; avoid `String` objects if space-critical
- **Serial baud**: 115200 (standard for debugging)

### Configuration & Secrets

- **Template**: `config.h.example` checked in with dummy values:
  ```cpp
  #define WIFI_SSID "SSID_PLACEHOLDER"
  #define WIFI_PASS "PASS_PLACEHOLDER"
  #define MQTT_HOST "192.168.1.100"
  #define MQTT_PORT 1883
  #define MQTT_USER "user"
  #define MQTT_PASS "password"
  #define MQTT_CLIENT_ID "home-door-node"
  ```
- **Real file**: Copy template to `config.h`, edit with real values, add to `.gitignore`
- **Never commit** `config.h` or any file with credentials

### Libraries

- **MQTT**: 256dpi/MQTT@^2.5 (prefers QoS1 publish support over PubSubClient)
- **IR**: crankyoldgit/IRremoteESP8266@^2.8.6 (for raw IR capture/replay)
- **No JSON library**: Hand-build JSON to conserve space

### Testing Strategy (Deferred)

- Hardware integration testing via real MQTT broker (mosquitto_pub/sub)
- No unit test framework on embedded; instead, manual serial logging verification
- Future: Add hardware test harness once all nodes assembled

---

## Cross-Cutting Patterns

### Configuration Management

- **Backend**: Environment variables (12-factor app style); parsed in `internal/config`
- **Firmware**: Compile-time constants in `config.h` (no runtime env parsing on ESP32)
- **Broker**: Docker environment vars (docker-compose.yml)

### MQTT Message Contract

All payloads are JSON; all topics and QoS levels documented in [`docs/system-architecture.md`](./system-architecture.md).

### Graceful Shutdown & Cleanup

- **Backend**: Signal handler in main.go; cleanly closes MQTT client + HTTP server
- **Firmware**: N/A (no graceful shutdown on embedded; power-off is expected)

---

## Development Workflow

1. **Write code** following the standards above
2. **Lint & format**:
   - Go: `gofmt -w .` + `golangci-lint run`
   - Firmware: No automatic formatter; manual review
3. **Test**:
   - Go: `go test ./...` (all tests must pass)
   - Firmware: Manual compile check via PlatformIO (`platformio run`)
4. **Commit**: Concise message, reference GitHub issue if applicable
5. **Document**: Update `docs/` if behavior, API, or architecture changed

---

## Style Review Checklist

Before submitting code for review:

- [ ] Identifiers and functions follow naming conventions
- [ ] Error handling is explicit; no silent failures
- [ ] Comments explain "why," not obvious "what"
- [ ] No hardcoded credentials (use config files)
- [ ] Tests added/updated for new behavior
- [ ] Linting passes (Go)
- [ ] No debug print statements left in code
- [ ] Documentation updated (if public API changed)

