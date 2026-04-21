# Sleep Pad Mobile App — UI Spec for Google Stitch

> Paste relevant sections into https://stitch.withgoogle.com to generate screens.
> Each "## Screen" block is self-contained; feed one at a time for best results.

---

## 1. App Overview (prepend to every Stitch prompt)

**Product**: Sleep Pad — an IoT mobile app that pairs with a sleep-monitoring mattress sensor (LSM-800-TP). Users monitor their (or a family member's) heart rate, respiration rate, sleep status, and respiratory disturbance events in real time and historically. Push notifications fire when vitals breach user-set thresholds.

**Primary persona**: Adult family member (30–55 y.o.) monitoring an elderly parent's sleep remotely. Secondary: younger user tracking own sleep wellness.

**Platform**: Flutter 3+. Target iOS + Android. Phone only (no tablet layout).

**Tone**: Calm, clinical-but-warm, trustworthy, premium. Think Apple Health meets Oura — data-forward, lots of breathing room, subtle use of color.

**Default theme**: Dark mode primary (most usage is late night). Provide light theme as secondary.

---

## 2. Design System (include this in prompts)

### Color palette
- **Background primary**:  `#0B0F14` (near-black midnight)
- **Background surface**:  `#121821` (elevated cards)
- **Background elevated**: `#1A222D` (modals, bottom sheets)
- **Text primary**:   `#E6EDF3`
- **Text secondary**: `#8B96A5`
- **Text disabled**:  `#4A5462`
- **Accent primary**: `#5EE7DF` (soft teal — heart rate, brand)
- **Accent secondary**: `#B490F5` (lavender — respiration)
- **Status: sleeping / good**: `#6BCB77` (muted green)
- **Status: warning**:        `#F5C26B` (amber)
- **Status: alert / critical**: `#F06262` (coral red, not harsh)
- **Dividers**: `#1F2833` (very subtle)

### Typography
- **Display**:  SF Pro Display / Inter, 34pt, weight 700, tight letter-spacing (-0.5)
- **Title**:    Inter 22pt, 600
- **Body**:     Inter 16pt, 400
- **Caption**:  Inter 13pt, 500, text secondary color
- **Metric (big-number cards)**: SF Pro Rounded / Inter, 56pt, 700, tabular numerals
- **Unit label (next to metric)**: Inter 14pt, 500, text secondary

### Spacing + shape
- Base unit: 4px. Gutters 16px. Section gaps 24px.
- Card corner radius: 20px.
- Button corner radius: 14px (primary), 12px (secondary).
- Inset elevation: no hard shadows. Use 1px inner border `rgba(255,255,255,0.04)` + subtle outer glow on active cards.

### Iconography
- Outlined, 2px stroke, rounded caps (Lucide or Phosphor duotone). 24px default.

### Motion
- Hero transitions on screen enter: 300ms ease-out
- Metric value changes: 600ms tween with spring
- WebSocket pulse: 1s opacity pulse on the card border when new data arrives

### Navigation
- 5-tab bottom nav bar (no labels on iOS, labels on Android per platform convention):
  1. Home (house icon)
  2. History (bar-chart icon)
  3. Alerts (bell icon)
  4. Devices (chip/hardware icon)
  5. Settings (gear icon)
- Bottom nav: translucent glass effect over `#0B0F14`, blur 20px, 1px top border in `#1F2833`.

---

## 3. Screens — detailed specs

### Screen: Onboarding / Welcome (first launch)

**Purpose**: Introduce the app in 3 slides before signup.

**Layout** (vertical, full-bleed):
- Top 60% of screen: large illustration (abstract wave/pulse representing sleep, in accent teal gradient over dark background)
- Below: headline + body + pagination dots + "Get started" primary button + "I already have an account" text button

**3 slides**:
1. **"Monitor sleep, without wearables"** — "A sensor under the mattress tracks heart rate, breathing, and sleep quality silently through the night."
2. **"Know if something's off"** — "Set personalized thresholds. Get a notification the moment vitals drift outside your safe range."
3. **"Share peace of mind"** — "Invite family members by email. They see the same realtime data and alerts you do."

**Components**: pagination dots (3, teal active, `#1F2833` inactive), primary button full-width bottom 24px margin.

---

### Screen: Login / Register

**Purpose**: Email + password auth.

**Layout**:
- App wordmark top-center ("Sleep Pad" in Inter 28pt 700, with tiny teal waveform glyph)
- Screen title: "Welcome back" (login) / "Create your account" (register)
- Email field (text input, dark surface, 52pt tall, teal focus ring)
- Password field (with eye-toggle icon on right)
- (Register only) Confirm password field
- Primary button full-width: "Sign in" / "Create account"
- Below: secondary text link — "New here? Sign up" / "Already have an account? Log in"
- Footer: "Forgot password?" tertiary link (login screen only)

**States**:
- Loading: primary button shows spinner, disabled
- Error: red inline helper text under field (`#F06262`), field border turns coral
- Empty: no error, helper text visible in secondary color

---

### Screen: BLE Device Scan

**Purpose**: Find and pick a SleepPad-XXXXXX device over Bluetooth.

**Layout**:
- App bar: "Add Device" title + close (X) icon left
- Below app bar: horizontal progress bar pulsing teal (scanning indicator)
- Body: vertical list of found devices, each row is a card (surface color, 72pt tall):
  - Left: small Bluetooth icon in teal circle
  - Middle: device name ("SleepPad-000001") bold + RSSI signal strength ("Strong signal" in secondary)
  - Right: chevron-right icon
- Below list: "Searching for nearby devices…" secondary text center-aligned with 3-dot animated ellipsis
- Empty state (nothing found after 15s): illustration of a tiny bluetooth icon with a dashed search ring, headline "No devices found", body "Make sure your Sleep Pad is plugged in and this is your first-time setup.", secondary button "Rescan"

**Permission-denied state**: full-screen banner with lock icon, "Bluetooth permission needed", primary button "Open Settings"

---

### Screen: BLE Provisioning (WiFi + pairing)

**Purpose**: User enters WiFi credentials that Flutter will push to the ESP32 over BLE, then waits for confirmation.

**Multi-step flow (shown as stepper progress indicator at top: 1 of 3 → 2 of 3 → 3 of 3)**

**Step 1 — "Connect to WiFi"**:
- App bar: "Setup Sleep Pad" + back arrow
- Illustration: WiFi icon with pulse (top, medium)
- Title: "Give your Sleep Pad WiFi"
- Body copy: "Your Sleep Pad will use this network to send data to the cloud."
- WiFi SSID input (with dropdown showing scanned networks if possible)
- Password input (with show/hide)
- Primary button "Continue"

**Step 2 — "Pairing"**:
- Hero: large circular progress ring (teal, sweeping), 200×200 px
- Title: "Pairing with your device…"
- Body: live status text below, updates as ESP32 sends BLE notifications:
  - "Saving WiFi credentials…"
  - "Connecting to WiFi…"
  - "Connecting to server…"
  - "Finalizing…"
- Each step has a small checkmark/spinner bullet above the hero ring
- Subtle subtext at bottom: "This usually takes 10–30 seconds"

**Step 2 fail state**: ring turns coral, title "Couldn't connect", body shows reason (WiFi failed / MQTT failed), two buttons: "Try again" secondary + "Change WiFi" primary.

**Step 3 — "You're all set"**:
- Hero: large green checkmark circle, `#6BCB77` with white check, 120×120
- Title: "Sleep Pad is ready"
- Body: "Device ID: CNU2000001 · Connected"
- Name input: "Give it a name" (placeholder: "Bedroom", "Grandma's room")
- Primary button "Save and go home"

---

### Screen: Home / Realtime Dashboard

**Purpose**: Primary glanceable view. Shows live vitals via WebSocket.

**Layout** (scrollable, dark bg):

1. **App bar** (semi-transparent, sticky):
   - Device selector chip on left (shows current device name with dropdown caret) — tapping opens bottom sheet with paired devices + shared devices
   - Right: bell icon (with small red dot if unread alerts), settings gear

2. **Status hero band** (full-width, 120pt tall):
   - Large animated icon representing current status (sleeping moon, sitting-up person, out-of-bed empty bed, etc.)
   - Status text in display font: "Sleeping" / "Out of bed" / "Sitting up" / "Movement detected" / "Weak breathing"
   - Color-coded background gradient (subtle): green for sleeping, amber for movement, coral for weak breathing / heavy object
   - Right side: "●" online/offline dot + "Last update 0.5s ago"

3. **Two big metric cards** (side by side, equal width):
   - **Heart Rate card**:
     - Card background `#121821`
     - Small label "HEART RATE" caption secondary, top-left
     - Huge number "68" in metric font, teal accent color
     - Unit "bpm" next to number, baseline-aligned, smaller
     - Tiny sparkline below: last 60 seconds of HR, teal stroke
     - Background: subtle teal glow pulse on value update
   - **Respiration Rate card**:
     - Same layout, lavender accent (`#B490F5`)
     - Number "14" + unit "brpm"
     - Sparkline in lavender

4. **Secondary metrics row** (horizontal scroll or 2×2 grid of smaller cards):
   - SDATA (proprietary signal quality) — caption + number
   - PDATA (proprietary pressure) — caption + number
   - Movement (from last minute) — number + icon
   - Snore events (last minute) — number + icon

5. **Quick actions row**:
   - Button "View history" (navigates to History tab, pre-selected to current device)
   - Button "Set alerts" (navigates to Alerts)

**Empty state** (no data yet / device offline):
- Ghost-card version of Home with metric placeholders showing "—"
- Top banner in amber: "Your Sleep Pad is offline. Last seen 2 hours ago."

**Loading state** (first WebSocket message pending):
- Shimmer animation on metric cards for <2s

**Disconnected state** (WS connection dropped):
- Tiny red dot in app bar + toast at bottom: "Reconnecting…"

---

### Screen: History

**Purpose**: Time-series charts per device over day / week / month.

**Layout**:

1. **App bar**: Device selector chip (same as Home) + right-side share icon

2. **Range tabs** (underline indicator, sticky below app bar): Day · Week · Month

3. **Summary strip** (above chart):
   - 3 mini-stats horizontally: "Avg HR 68 bpm", "Avg RR 14 brpm", "Disturbances 3"
   - Each with tiny trend arrow (up/down vs previous period) + percentage

4. **Chart card 1 — Heart Rate**:
   - Title "Heart rate" + right-side small legend dot in teal
   - Line chart, fl_chart style
   - X-axis: time labels contextual (Day = hours 00-24, Week = Mon-Sun, Month = week 1-4)
   - Y-axis: bpm, 40-120 range
   - Teal gradient fill below line
   - Scrubber dot on touch/drag with tooltip showing exact value + time

5. **Chart card 2 — Respiration Rate**:
   - Same layout, lavender
   - Y-axis 5-30 brpm

6. **Chart card 3 — Sleep events** (bar chart):
   - Stacked bars showing movement, snore, resp_disorder events per bucket
   - Small legend strip at bottom

**Empty state**: illustration of a blank chart grid, text "Not enough data yet. Check back after a full night."

---

### Screen: Alerts

**Purpose**: Set thresholds + review past alerts.

**Layout** (segmented control at top: Thresholds | History):

### Tab 1 — Thresholds

- Top note: "Alerts fire when vitals stay outside these ranges for over a minute. You'll get a push notification."
- Sections (grouped cards):

  **Heart Rate** (card with icon + label):
  - Range slider (dual-thumb, teal active track) showing min-max 30 — 250
  - Current values displayed above thumbs: "Low 40" / "High 120"

  **Respiration Rate** (same pattern):
  - Range slider 1 — 60
  - Low 5 / High 30

  **Sleep Disturbances per minute**:
  - Single slider 0 — 60
  - "Alert when more than 5 events in a minute"

- Sticky bottom: "Save changes" primary button (disabled until changes made, enabled teal when edited)

### Tab 2 — History

- List of past alert events, newest first
- Each item: card row with:
  - Left: color-coded dot (coral for high, amber for low, red for disturbance)
  - Middle: metric name + short description — "Heart Rate high · 131 bpm (limit 120)"
  - Right: relative time "2h ago"
  - Tap for detail sheet with timestamp, device, full context

- Empty state: checkmark illustration + "No alerts yet. That's good news."

---

### Screen: Devices

**Purpose**: Manage paired devices + devices shared with you.

**Layout**:

1. **App bar**: "Devices" title + "+" button top-right to start BLE scan

2. **Section: My Devices** (devices I own)
   - List of cards, each:
     - Device name + online/offline dot
     - Small detail line: "Paired Apr 10 · Last active 2 min ago"
     - Right side: chevron
   - Tapping → Device Detail screen

3. **Section: Shared with me**
   - Same card pattern but with small "👁 view only" chip
   - Extra line: "Shared by alice@example.com"

4. **Section: Pending invites** (only if any)
   - Card with invited device name + "Invite from alice@example.com"
   - Buttons: "Accept" primary compact + "Decline" secondary compact

**Empty state**: illustration of a sensor chip, "No devices yet. Add your first Sleep Pad.", primary button "+ Add device"

---

### Screen: Device Detail

**Purpose**: Rename, share, remove device.

**Layout**:
- Device name editable title (tap to edit inline)
- Device ID (monospace, read-only, with copy icon)
- Status card: online/offline + last seen timestamp
- Section "Alert thresholds" — inline preview of my thresholds for this device, with "Edit" link
- Section "Sharing" (only if I own the device):
  - List of people shared with (email + accepted/pending chip + "Revoke" text button)
  - Big button "Invite family member" opens invite sheet
- Section "Danger zone":
  - Button "Remove device" coral text, opens confirm dialog

---

### Screen: Invite Dialog / Bottom sheet

**Purpose**: Invite by email.

**Layout** (modal bottom sheet, 60% screen height):
- Drag handle at top
- Title "Invite family"
- Body: "They'll get an email invite. When they accept, they'll see the same realtime data and alerts."
- Email input field
- Primary button "Send invite" (full-width)
- Tertiary cancel

**Success state**: button morphs into checkmark for 1s, sheet slides down, toast "Invite sent to foo@example.com"

---

### Screen: Settings

**Purpose**: Account, preferences, logout.

**Layout** (grouped list, iOS settings-style):

1. **Account**
   - Avatar + email (non-editable) + "Change password" row
2. **Notifications**
   - Toggle: "Enable push notifications"
   - Toggle: "Quiet hours 10pm — 7am"
3. **Appearance**
   - Segment: System · Light · Dark (default Dark)
4. **Device / Server**
   - Row: "Server URL" (advanced, shows current, tap to edit — warn user)
5. **About**
   - App version, terms, privacy, feedback email
6. **Logout** (coral text row at bottom, standalone)

---

### Screen: Push notification tap → Alert detail

**Purpose**: When a push is tapped, deep-link into a detail screen.

**Layout**:
- Hero banner with alert status color (coral for critical)
- Big icon + alert title: "Heart Rate was high"
- Subtext: "Alice's Pad · 131 bpm for 1 minute, threshold 120"
- Timestamp + device info
- Section: "What happened" — line chart of the preceding 10 minutes of HR
- Button "View in History" primary
- Button "Adjust threshold" secondary

---

## 4. Ready-to-paste Stitch prompts

Each prompt below already includes the app context + design system + one screen. Paste **one at a time** into Stitch.

### Prompt: Home / Realtime Dashboard

```
Design a mobile home screen for "Sleep Pad", a wellness IoT app that shows
realtime sleep vitals from a mattress sensor. Dark-mode-first, premium,
calm clinical aesthetic — think Apple Health meets Oura.

Background primary #0B0F14, card surface #121821, text primary #E6EDF3,
text secondary #8B96A5. Accent teal #5EE7DF for heart rate, lavender #B490F5
for respiration. Corner radius 20px on cards. Typography: Inter, metric
values 56pt 700 tabular.

Layout top-to-bottom:
1. Translucent app bar with a device-name dropdown chip on the left
   ("Grandma's room ▾") and a bell icon (with red dot) + gear icon on right.
2. A status hero band with a sleeping-moon icon and large text "Sleeping",
   green gradient background, right-side "● online · 0.5s ago".
3. Two big metric cards side-by-side:
   - Heart Rate: label "HEART RATE", big number "68" in teal, unit "bpm",
     tiny 60s sparkline below.
   - Respiration: label "RESPIRATION", big number "14" in lavender, unit "brpm",
     tiny sparkline below.
4. A 2x2 grid of smaller secondary metric cards: SDATA, PDATA, Movement, Snores.
5. Bottom: 5-tab glass-effect bottom nav bar with icons for Home, History,
   Alerts, Devices, Settings. Home tab active with teal indicator.

Generous spacing, breathing room, subtle 1px inner borders on cards.
```

### Prompt: History

```
Design a history screen for "Sleep Pad" mobile app. Same dark theme as
before (#0B0F14 background, teal #5EE7DF + lavender #B490F5 accents,
Inter typography, 20px card radius).

Layout:
- App bar with device-selector chip "Grandma's room ▾" and share icon
- Segmented underline tabs: "Day · Week · Month", "Week" selected
- Summary strip: 3 mini-stats horizontally with trend arrows — "Avg HR 68
  bpm ↑2%", "Avg RR 14 brpm ↓1%", "Disturbances 3 ↓50%"
- Three stacked chart cards:
  1. "Heart rate" — smooth line chart in teal with gradient fill below,
     x-axis Mon-Sun, y-axis 40-120 bpm, scrubber dot visible at mid-chart
     with tooltip "68 bpm · Wed 3:00am"
  2. "Respiration rate" — same style in lavender, y-axis 5-30
  3. "Sleep disturbances" — stacked bar chart with three series (movement,
     snore, resp disorder) in green/amber/coral
- Bottom 5-tab glass nav, "History" tab active.
```

### Prompt: Alerts

```
Design an alerts settings screen for "Sleep Pad" mobile app. Same dark
theme (#0B0F14, Inter, teal accent, 20px radius).

Layout:
- App bar title "Alerts"
- Top segmented control: "Thresholds | History", Thresholds selected
- Explanatory caption: "Alerts fire when vitals stay outside these ranges
  for over a minute."
- Grouped cards:
  1. "Heart Rate" with heart icon — dual-thumb range slider (teal active),
     showing "Low 40 · High 120" above thumbs, min/max labels 30/250
  2. "Respiration Rate" with lungs icon — range slider "Low 5 · High 30"
  3. "Sleep Disturbances" with alert icon — single slider "Alert above 5/min"
- Sticky bottom primary button "Save changes" (disabled state shown as
  subtle gray)
- 5-tab glass nav, "Alerts" tab active with bell icon + tiny red dot badge.
```

### Prompt: BLE Provisioning Step 2

```
Design a device-pairing progress screen for "Sleep Pad" mobile app.
Dark theme (#0B0F14, Inter, teal accent #5EE7DF).

Layout (vertical, centered):
- App bar "Setup Sleep Pad" with back arrow and step indicator "2 of 3"
- Large circular progress ring in teal (200x200), sweep animation implied,
  subtle glow
- Below ring: display-weight title "Pairing with your device…"
- 4 vertical step bullets below, with checkmark / active-spinner / idle states:
  ✓ Saved WiFi credentials
  ◌ Connecting to WiFi           (active, teal spinner)
  ○ Connecting to server
  ○ Finalizing
- Bottom secondary text: "This usually takes 10–30 seconds"
- No bottom nav on this full-screen flow.
```

### Prompt: Sharing / Invite bottom sheet

```
Design a bottom-sheet modal for "Sleep Pad" mobile app inviting a family
member by email. Dark theme behind (#0B0F14), modal surface #1A222D,
radius 24px top corners only.

Layout:
- Drag handle at top center (small gray pill)
- Sheet title "Invite family" in 22pt 600
- Body copy 16pt: "They'll get an email invite. When they accept, they'll
  see the same realtime data and alerts you do."
- Email input field (dark, teal focus ring, 52pt tall) with placeholder
  "mom@example.com"
- Primary full-width button "Send invite" in teal
- Text button "Cancel" below in secondary color
- Modal takes ~55% of screen height, main screen visible above it dimmed.
```

---

## 5. Stitch tips for best results

- Feed **one screen per prompt**. Don't ask for whole apps.
- Always prepend the "App Overview" + "Design System" sections so Stitch keeps consistent colors/typography across screens.
- Ask for "mobile portrait, 390x844" to force phone aspect ratio.
- If Stitch's output drifts light, add to the prompt: "strictly dark mode, background #0B0F14, no white".
- For charts, Stitch may struggle — regenerate with the word "fl_chart-style line chart" and it usually gets closer.
- Iterate: start with 3 most-important screens (Home, History, Alerts), share the image back with "same style, now design [Devices screen]".

---

## 6. Screens NOT yet specified (add later if needed)

- Forgot password flow
- Onboarding tutorial (post-login, first-time tour of Home)
- Profile avatar upload
- Offline banner / no-connection full screen
- iPad/tablet layouts (not planned for MVP)
