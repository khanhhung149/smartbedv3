# Phase 08 Review — Flutter Alerts + Sharing + Devices + Settings + FCM

Scope: 17 new files, routing, FCM stub. Verified: flutter analyze clean, web build passes.

---

## CRITICAL

### C1 — ShareOut JSON field mismatch (backend contract break)
`lib/features/sharing/models/share_out.dart:19-23` expects `share_id`, `email`. Backend `app/sharing/models.py:14-21` returns `id`, `invited_email`. `ShareOut.fromJson` will throw `TypeError: null is not a subtype of String` on **every** sharing call:
- `POST /share/invite` response → `InviteFamilySheet` crashes after successful invite.
- `GET /share/device/{id}` response → `_SharingSection` error state, list never renders.

Also missing: `accepted_at` field (backend returns it). Fix: change to `id` → `shareId`, `invited_email` → `email`, add `acceptedAt`.

### C2 — ThresholdOut `resp_disorder_count` type mismatch (silent data corruption risk)
`lib/features/alerts/models/threshold_out.dart:26` casts `resp_disorder_count` to `double`. Backend `alerts/models.py:14` declares `int`. Read path works (num → double), but `toJson()` at line 34 sends a float back; `ThresholdUpdate` in backend (`alerts/models.py:23`) types this as `int | None`. Pydantic v2 in default mode coerces float→int lossily (3.7 becomes 3), but strict mode rejects. Also `hr_high/hr_low` backend = `int`; Flutter sends float. **Currently works due to pydantic coerce but is fragile**. Fix: parse/send these as int, or switch backend schema to float.

---

## HIGH

### H1 — `/share/accept/:shareId` deep link does not accept
`app.dart:127-134` redirects straight to `/devices` and never calls `SharingRepository.acceptInvite(shareId)`. Comment admits this ("Production: call …"). The invitee clicking the email link sees a devices list with nothing new. Additionally the redirect is unauthenticated — if the user is logged out, they'll hit `/devices` and get a 401 storm. Fix: wrap redirect in an auth check; on authenticated, perform POST then navigate; on unauth, bounce to `/login` preserving the shareId.

### H2 — Device rename is pure UI theater
`device_detail_screen.dart:118-126`: closes sheet, invalidates provider, shows "Device renamed" toast — but **no backend call**. `DevicePairOut.name` from `GET /devices` will repaint with the unchanged server value. User sees "Device renamed" snackbar, screen flashes, old name returns. No backend endpoint exists in the Phase 04 contract for rename. Fix options: (a) add `PATCH /devices/{id}` backend route, (b) hide the edit pencil until implemented, or (c) store rename locally in secure storage as per-user alias. Current behavior is worse than disabling because it lies to the user.

### H3 — Device remove is also theater
`device_detail_screen.dart:160-176`: dialog confirmed → invalidates provider → navigates to `/devices`. Device reappears because no DELETE call was issued. Hide the danger zone until backend supports it, or add a TODO banner in the dialog.

### H4 — Settings server URL edit discarded silently
`settings_screen.dart:157-176`: validates URL, calls `setState(_serverUrl = result)`. But `ApiClient` in `core/api_client.dart` reads `AppConstants.apiBaseUrl` at construction and Riverpod providers are long-lived singletons. Dio instance is never rebuilt. User enters a new URL → snackbar is silent → next API call still hits the old host. Either wire the setter into `ApiClient.updateBaseUrl()` + persist to secure storage, or make the field read-only for POC. Current "partial" implementation is a usability trap.

### H5 — FCM `_initialized` is permanently `false`
`fcm_service.dart:22` declares `static bool _initialized = false`. No code path ever sets it true (the production block is commented out). `uploadToken()` at line 67 early-returns, `clearToken()` at line 87 early-returns. That's fine for POC. BUT the ignore-comment `// ignore: prefer_final_fields — set to true when Firebase is wired` is wrong direction: in its current shape the lint should be `prefer_final_fields` auto-fix to `final` — which would then break when production code tries to set it. Suggest removing the ignore, making it `final`, and flipping via `const bool kFcmEnabled = false` compile-time flag. Low severity but the stub's safety posture is correct; just document the flip cleanly.

### H6 — `_ServerUrlDialog` TextField controller leaked
`settings_screen.dart:158`: `TextEditingController(text: _serverUrl)` allocated each dialog call, never disposed. Same leak in `device_detail_screen.dart:111` rename sheet. Minor but measurable.

---

## SUGGESTIONS

### S1 — Pending invites section absent from devices_screen
Task spec says "Does the screen render an empty placeholder, hide the section, or render garbage?" Answer: the section is **omitted entirely** (lines 50-93 only render MY DEVICES + SHARED WITH ME). Acceptable — backend has no "pending invites for me" endpoint. Matches YAGNI. Just confirm this is intentional for Phase 08.

### S2 — Invite sheet error mapping
Task asked about 409 and non-existent-email cases. `sharing_repository.dart:95` maps 409 → "Already shared with this email." Backend `service.py` raises 409 for existing invite (good). Non-existent email = backend creates pending invite regardless (valid per spec) — sheet shows success, correct. Invite flow contract is OK **modulo C1**.

### S3 — File size (colocated widgets, not monolithic)
`settings_screen.dart` 682 lines, `device_detail_screen.dart` 735 lines, `alerts_screen.dart` 468 lines, `threshold_form.dart` 367 lines. Exceeds the 200-line soft cap in development-rules.md but all are private `_Foo` widgets colocated for single-screen cohesion — matches precedent in Phase 06/07 (`home_screen.dart`). Accept as-is. If you later touch these, consider extracting `_ServerUrlDialog`, `_RenameSheet`, `_RemoveConfirmDialog` to `shared/widgets/`.

### S4 — `clearToken` sends empty string
`fcm_service.dart:90` sends `{'fcm_token': ''}`. Backend should treat `''` as unregister; if backend expects `null` or DELETE, this is a silent no-op. Confirm Phase 04 `PATCH /auth/fcm-token` schema accepts `''`.

### S5 — Threshold form no-snap on `onChangeEnd`
`threshold_form.dart:71-82` calls `setState` + `_notify` on every slider frame. Fine for UX but floods parent rebuild. Consider `onChangeEnd` for `_notify`, `onChanged` for local state only. YAGNI for POC.

### S6 — Pixel-fidelity spot check
- **alerts_settings**: teal HR / lavender RR colors via `AppColors.primaryContainer` + `AppColors.rrAccent` — matches Stitch. Dual-slider stacked (not overlapping) — documented deviation, accepted.
- **device_detail**: monospace font for device ID missing (inter only) — documented, accepted. Clipboard copy on tap (`device_detail_screen.dart:308`) is a nice addition not in HTML.

---

## Positive Observations
- `alerts_repository.dart` error mapping (401/404/network) clean and consistent.
- `AlertsScreen` correctly uses `ValueKey(device.deviceId)` to reset body state when selected device changes — avoids dirty-state leakage across devices.
- `_saving` LoadingOverlay + dirty-state save button gating is correct.
- FCM stub gracefully no-ops; `initialize()` wrapped in try/catch (never throws).
- Routing is declarative; no auth-guard regression vs Phase 02/03.

---

## Recommended Actions (priority order)
1. **Fix C1** — regenerate `ShareOut.fromJson` with correct field names. Without this, sharing is non-functional end-to-end.
2. **Fix C2** — align int/float types on thresholds, or document that backend coerces silently.
3. **Fix H1** — wire real `acceptInvite` in deep-link redirect, with auth check.
4. **Fix H2/H3** — either implement backend endpoints or hide rename/remove affordances. Do not ship UI that appears to work but does nothing.
5. **Fix H4** — lock server URL field read-only for POC, or wire ApiClient rebuild.
6. H5/H6 + suggestions can land later.

---

## Unresolved Questions
- Is backend rename endpoint (`PATCH /devices/{id}`) planned for a later phase, or is device-name intended to be alias-only (client-side)?
- Should `/share/accept/:shareId` land in Phase 08 or deferred? The route stub is user-facing (email link target).
- Does Phase 04 backend's `PATCH /auth/fcm-token` accept empty string for unregister?

---

**Status:** DONE_WITH_CONCERNS
**Summary:** Phase 08 lands clean analyze + build, but 2 critical contract bugs (ShareOut JSON field rename, threshold int/float skew) will silently break sharing and may corrupt thresholds. 4 high-priority issues where UI claims success but no backend work happens (rename/remove/server-url/deep-link-accept).
**Concerns/Blockers:** C1 blocks any sharing use. C2 is latent pydantic-coerce risk. H2/H3 are user-trust bugs — UI shouldn't lie.
