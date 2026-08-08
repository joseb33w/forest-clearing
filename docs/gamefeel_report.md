# Game-Feel / Mobile-UX Report — "Forest Clearing"

**VERDICT: PASS** — 0 P0. Core touch loop works end-to-end on a phone-shaped viewport.
**But 5 ❗P1 must-fix items** (landscape UI scale, JUMP/look conflict, title-gate camera, boundary camera slam, canopy clip) + 1 ❗P1 pipeline defect (gogi telemetry hooks dead).

**How verified:** drove the live preview (`https://preview.myapping.com/cloud-3gdwudpqqbytnnuszh7p/index.html`) in touch-enabled Chromium (SwiftShader) at portrait 390×844 and landscape 844×390, using real CDP touch events for joystick / look / JUMP / two-finger tests, plus keyboard driving for navigation-heavy runs. All claims below are backed by rendered frames I inspected (`/tmp/feel-*.png`). Note: `window.gogiGetPlayer()` is broken in this build (see P1-6), so verification was screenshot-based. SwiftShader runs ~2–3 fps here; game-time dilation artifacts (e.g. slow toast fade) were identified as container artifacts, not bugs.

---

## ❗ P1 — must fix

### P1-1. Landscape phone UI is near-unusable (tiny JUMP, illegible text)
- **Symptom (verified at 844×390, `feel-landscape-hud.png`):** the JUMP button renders ~33×33 dp (min touch target is 44–48 dp) and its label is ~8 px; the objective toast and title-gate control hints render ~7 px — illegible. Look sensitivity is also ~1.8× hotter per physical swipe in landscape than portrait (same root cause). Everything still *functions* (a precise tap on the tiny JUMP did fire — `feel-landscape-jump.png`), but one-handed play in landscape is not realistic.
- **Root cause:** `project.godot` → base viewport 720×1280 (portrait) with `stretch/mode=canvas_items`, `aspect=expand`. In landscape the scale factor becomes `min(844/720, 390/1280) = 0.30`, shrinking ALL UI to 30%.
- **Fix direction:** swap the content-scale base per orientation at runtime — e.g. in `main.gd _ready()` (and on `get_window().size_changed`): `get_window().content_scale_size = Vector2i(720,1280) if size.x < size.y else Vector2i(1280,720)`. Alternatively lock the game to portrait via the export page, but the runtime swap is small and keeps both orientations.

### P1-2. A drag starting on the JUMP button rotates the camera; sloppy jump taps get eaten
- **Symptom (verified):** dragging 150 px starting ON the JUMP button rotated the view ~80° (`feel-look-90.png` → `feel-conflict.png`). Because the Button fires on **release** (BaseButton default) and a drag that slides off the button cancels the press, a sloppy jump tap = camera yank + no jump.
- **Root cause:** `main.gd _input()` claims any right-half `InputEventScreenTouch` as `_look_index` — it runs before GUI input and never excludes the button's rect; plus `jbtn.pressed` default `ACTION_MODE_BUTTON_RELEASE`.
- **Fix direction:** in `_input()`, skip look-claiming when the touch-down lands inside the JUMP button's global rect (`jbtn.get_global_rect().has_point(event.position)`); and set `jbtn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS` so jump fires on touch-down (snappier feel).

### P1-3. Title gate (first frame of the game, every boot AND every Play Again) shows the camera inside the player's head
- **Symptom (verified on 3 boots + after Play Again, `feel-portrait-title.png`, `feel-landscape-title2.png`, `feel-play-again-result.png`):** behind the "Forest Clearing / Tap to start" panel is a giant dark-brown mesh-interior blob (the hero's head/hair at point-blank) instead of an establishing shot. It's the player's literal first impression, and the 0.85-alpha dim doesn't hide it.
- **Root cause:** `_show_tap_to_start()` sets `get_tree().paused = true` in `_ready()` before the SpringArm3D ever processes a physics frame, so the Camera3D stays at the arm's origin (inside the head at `position.y=1.55`), never extended to 7.5 m.
- **Fix direction:** manually place the camera at its resting pose at build time (set `camera.position.z = CAM_DIST` — the spawn area is clear, no occluders), or defer the pause by two physics frames (`await get_tree().physics_frame` ×2) before pausing so the arm extends once.

### P1-4. Walking to the clearing edge slams the camera into an INVISIBLE wall → full-frame character close-up
- **Symptom (verified, `feel-boundary-cam.png`):** backing toward the treeline pins the camera against the invisible boundary wall; the character's face fills ~65% of the screen at point-blank, "popup"-style, with no visible obstacle to explain it. Recovers on walking away, but the perimeter is reachable in seconds of normal play.
- **Root cause:** `_build_boundary()` walls are `collision_layer = 1`; `cam_spring.collision_mask = 1` — the SpringArm collides with the movement-blocking walls.
- **Fix direction:** put boundary walls on a dedicated layer (e.g. 8), keep player `collision_mask = 1|8`, leave `cam_spring.collision_mask = 1` (or a camera-specific mask) so the camera may pass over the invisible wall; treeline trees behind it have no colliders so no pull-in follows. Optionally also cap wall height below the camera ray (~4.6 m at default pitch).

### P1-5. Orbiting near trees buries the camera inside canopies — view walled by solid foliage
- **Symptom (verified, `feel-look-90.png`; also edge of `feel-landscape-hud.png`):** a ~90° orbit at spawn put the camera inside the birch/pine canopy — a flat dark-green mesh walls ~60% of the frame. With 8 solid trees in the clearing plus the treeline ring, a phone player orbiting (the primary right-thumb verb) hits this within the first minute. Positional and recoverable, hence P1 not P0.
- **Root cause:** deliberate trunk-only colliders (`"collider": "trunk"`, radius ≤ 0.5) — good for movement, but `cam_spring` then ignores foliage entirely.
- **Fix direction:** give in-clearing trees a camera-only canopy shape (sphere/cylinder on e.g. layer 16, `cam_spring.collision_mask |= 16`, movement mask unchanged) so the arm clamps just before entering leaves; accept the mild pull-in, it reads far better than a full-green screen. (Treeline MultiMesh ring can stay collider-less once P1-4 keeps play away from it.)

### P1-6 (pipeline, not player-facing). `window.gogiGetPlayer()` / `window.gogiSolids()` always return `null`
- **Symptom (verified):** `__gogiGetPlayerRaw()` returns `undefined`→`null` before AND after start; only `gogiGetTime` (eval-mirrored) works. The verification contract the coordinator/QA rely on is dead in this build — I had to verify everything visually.
- **Root cause:** `JavaScriptBridge.create_callback` callbacks do not propagate GDScript return values back to the JS caller in this Godot 4 web build.
- **Fix direction:** mirror state INTO JS the same way `__gogiTime` is done — e.g. a 5 Hz timer running `JavaScriptBridge.eval("window.__gogiPlayer=%s" % JSON.stringify(state))` and `gogiGetPlayer` reading `window.__gogiPlayer`.

---

## ⚠️ Polish (nice-to-have)

1. **No visual joystick indicator** — left-half drag works well, but nothing on screen shows stick origin/deflection. A faint base+knob that appears at touch origin and fades on release would help first-run discoverability (the title hint is the only teaching).
2. **Play Again touch target** ≈ 130×41 css px in portrait (76 vp px × 0.54) — just under the 44–48 dp minimum height. Bump `custom_minimum_size` to ~(240, 90).
3. **Speed snap at joystick mag 0.6** — velocity = |v| × (6.0 if |v|>0.6 else 3.2), so speed jumps 1.92→3.66 m/s mid-deflection. Blend instead (`lerp(WALK, RUN, smoothstep(...))`).
4. **Pond is non-interactive** — no collider/effect: the player strides through the water disc ankle-deep with no ripple/splash/slowdown. Fine for scope; a small splash particle + walk-speed clamp inside `POND_R` would sell it.
5. **Step-up assist climbs the campfire** — `STEP_MAX 1.2` exceeds the fire's height, so you can stand in the flames with zero feedback (code-level observation).
6. **Win panel pop animation pivots from top-left** — `box.pivot_offset = box.size * 0.5` runs before layout (size = 0). Set the pivot deferred/after `await get_tree().process_frame`.
7. **Exported page `<title>` is "Godot 3D Mobile Starter"** — template name in the browser tab; set the project name / export title to "Forest Clearing".
8. **Viewport meta lacks `viewport-fit=cover` / safe-area handling** — JUMP sits 12–22 css px from the bottom-right edge depending on orientation; on notched/home-indicator phones it may crowd the gesture bar (couldn't verify on real hardware — see below).

---

## ✅ Passes (evidence-backed)

- **Touch joystick moves the player** via the drag-from-origin scheme; analog magnitude works; deadzone-free scheme is fine because speed scales with |v| from the touch origin.
- **Look drag** rotates the view with comfortable portrait sensitivity (~53° per 100 px thumb swipe); pitch is clamped in code [-1.25, 0.6] — no floor/sky lock possible, and no gimbal misbehavior seen.
- **JUMP fires via touch** in both orientations (mid-air frames captured: sky band rises).
- **Two-finger move+look simultaneously** works — touch index routing is correct (`feel-twofinger.png`: moved AND rotated).
- **Toast is transient** — objective toast visible at start, gone in all later frames of the same session (tween interval 4.5 s + fade + `queue_free`). The lingering toast seen in slow-motion runs is a 2-fps SwiftShader time-dilation artifact, not a bug.
- **Only the JUMP button persists on the HUD**; no debug/developer text on screen in any captured frame (GOGI prints go to console only).
- **Win flow end-to-end on touch-shaped input:** chest trigger → movement locks → gold burst/shake → win panel appears ~1 s later, centered, fully legible at portrait 390×844, no overflow (`feel-cabin-pointblank2.png`); **Play Again works** — reloads to the title gate (`feel-play-again-result.png`).
- **Camera never rendered inside the cabin** — spring arm clamps against the cabin's box collider (point-blank orbit test at the cabin face produced legal framing, no interior/backface frames in ~20 captures).
- **Default framing is good:** character ~22% of frame height in portrait, cabin landmark clearly composed from spawn; no "speck" or "half-screen body" at rest.
- **Non-modal feedback:** no modal interruptions during play; the only panel is the terminal win screen, which is appropriate. (No combat/damage in scope.)
- **First-run discoverability:** toast states the goal; cabin is in clear sight of spawn (~16 m, ~4 s at run speed); the chest reads clearly once behind the cabin (`feel-win-portrait2.png`). Time-to-fun is appropriate for the scope.

## Could not verify (sandbox limits)
- Real-device notch / home-indicator overlap with the JUMP button and toast (no notch emulation worth trusting here); `viewport-fit=cover` behavior on iOS Safari.
- True frame-rate feel, look-drag latency, and multi-touch ergonomics at 60 fps — this container renders at 2–3 fps under SwiftShader; all timing-sensitive judgments (e.g. jump-on-release latency) are code-derived, not felt.
- Mid-session orientation rotation (portrait↔landscape) behavior.

## Evidence index (frames on disk, /tmp)
`feel-portrait-title.png` (P1-3), `feel-portrait-game.png` (baseline HUD/toast), `feel-jump-air.png` (touch jump), `feel-look-90.png` (look works + P1-5), `feel-conflict.png` (P1-2), `feel-twofinger.png` (multi-touch), `feel-boundary-cam.png` (P1-4), `feel-cabin-front.png`/`feel-cabin-pointblank2.png` (cabin cam OK + win panel legibility), `feel-win-portrait2.png` (chest readable), `feel-landscape-title2.png`/`feel-landscape-hud.png`/`feel-landscape-jump.png` (P1-1), `feel-win-small.png`/`feel-play-again-result.png` (win + Play Again).
