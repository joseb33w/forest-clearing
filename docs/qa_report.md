# QA Report — "Forest Clearing" (Godot 4.7.1 web, mobile)

**VERDICT: PASS** — 0 P0, 0 P1. Ship it. Several small warns/polish notes below (one of them
is a broken *QA-hook* claim in the handoff, not a player-facing defect).

Evidence base: 2 full Chromium (SwiftShader) sessions against the actual export
(`/workspace/out`, engine files mirrored same-origin in `/tmp/qa_out` because the sandbox
proxy cert blocks the shared-engine URL inside headless Chromium — container artifact, not a
build issue); 3 headless-Godot runs driving the REAL `main.tscn` with real
`Input.parse_input_event` key/mouse events; 20+ screenshots eyeballed (in `/tmp/shots/` +
`/workspace/verify/frame0.png`). Verifier log: `/tmp/verify.log`.

## Results by dimension

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | Boot, canvas, console | ✅ | `verify.mjs`: "PASS engine booted / PASS canvas present". My two full browser runs: **0 real console/page errors** (portrait + landscape, full win loop). Only env noise was the shared-engine cert block, expected in-container. |
| 2 | Anim clips / no T-pose | ✅ | Headless: all 4 clips (`Idle_A/Walking_A/Running_A/PickUp`) resolve onto kk_Ranger via AnimRig (`ATTACH OK`, 4/4 aliases); walk clip rotates 14/23 bones between t=0→0.5s (skeleton really moves). PickUp pose visibly playing in the win moment (`s-c3.png`, hero crouched). `kk_rig_medium_combatmelee.glb` absent but unreferenced (quiet-skip by design — no combat clips used). |
| 3 | Movement + facing | ✅ | `v-toast.png`: W → hero's BACK + cape toward camera; `v-face.png`: S → hero's face. No moonwalk. Idle→walk→run transitions drive position (headless: 6 m/s run, legs all land where expected). |
| 4 | Input-binding sanity | ✅ | No fire verb exists. Left half = joystick, right half = drag-look, JUMP = separate button, look = left-mouse drag on desktop. The emulated-mouse-from-touch path is guarded (`_move_index == -1 and _look_index == -1`) so a joystick finger can't double-drive the camera. Nothing fires on look. |
| 5 | Win path end-to-end (BROWSER, real export) | ✅ | Steered the real game around the cabin: pinned at cabin front door (`s-w1.png` — cannot walk through), east side (`s-w3.png`), chest trigger fired → **"You found the treasure!" panel + Play Again** (`s-w5.png`), Play Again → title screen (`s-w6.png`) → tap → playable again from spawn with toast (`s-w7.png`). Reproduced the win a 2nd time (`s-c3.png`). |
| 6 | Win path (headless, numeric) | ✅ | Trigger fires at 2.39 m horizontal from chest (r=2.1 sphere @y0.8 + capsule); panel spawns with exactly 1 button + the 2 labels; movement frozen during win (`moved=0.0`); Play-Again handler reloads: `chest_found=false`, spawn `(0,0,10)`, `started=false`, paused title again. |
| 7 | Collisions | ✅ | Cabin: stopped at z=-2.44 driving W (face ≈ -2.84, capsule r 0.4) — never penetrates (headless + browser pin). 22 solids = exactly the expected set (cabin, chest, campfire, stump, log, 8 trunk cylinders, 5 rocks, 4 boundary walls). Player min_y over the whole run: **-0.07** (never falls through). |
| 8 | Boundary | ✅ | All 4 directions stop at **±18.6** (walls at ±19.5, face 19.0 − capsule 0.4). No void, no escape; the visual treeline ring (non-colliding MultiMesh) sits OUTSIDE the walls so it's unreachable — consistent design. |
| 9 | Trigger zone layer/mask | ✅ | Area3D layer 4 / mask 2 vs player layer 2 — fires in practice (3 separate wins observed). |
| 10 | Mobile fill portrait 390×844 | ✅ | `v-toast.png`: scene fills all 4 corners, no letterbox; toast inside top; JUMP inside bottom-right; no UI overlap. |
| 11 | Mobile fill landscape 860×400 | ✅ | `v-land-game.png`: full-bleed, pond/cabin/campfire composition reads great, toast + JUMP inside viewport. |
| 12 | Camera orbit / look | ✅ | Browser: right-half drag rotated the view ~90° (`v-prelook.png` → `v-look.png`). Headless: after drag-look, W-movement axis rotated from −z to ±x (dx=2.12, dz=0.0). Pitch clamped (−1.25..0.6) — can't stare through the floor. |
| 13 | Day/night (deterministic, via `gogiSetTime`) | ✅ | `GOGI_TIME night` / `GOGI_TIME day` console confirms the JS→Godot bridge; `v-night.png` is dark but READABLE (hero, grass, pond, cattails distinguishable); `v-day.png` restores sunny palette, no blow-out (no clipped-white walls in any frame). |
| 14 | Visual quality vs committed style | ✅ | Stylized low-poly, warm + sunny: textured red-roof cabin with door facing spawn, dense multi-species treeline, grass tufts + flowers, mossy logs, campfire with visible warm glow (`s-w2.png`), pond reads as water (shallow-teal rim → deep center, `v-day.png`/`v-land-game.png`). No gray untextured boxes anywhere. Ground has normal-mapped relief, not flat color. |
| 15 | Scale / seating sanity | ✅ | Headless dump: every placed prop bottom_y = 0.00 (nothing floats/sinks); trees 7–9 m, rocks 1–3.7 m, campfire 1 m, chest 1.15×0.56×0.95 m — no giants, no dwarfs. Hero's feet rest on the grass (`v-face.png`). |
| 16 | Chest asset in-context | ✅ | At (1.2, 0.02, −11.6), yaw 205°, seated at ground, all 4 surfaces textured (albedo_tex=true). Occlusion check from two angles confirms it is genuinely HIDDEN behind the cabin from the approach side — the "hidden treasure" design works. Sparkle emitter above it at +1.0 m. |
| 17 | Jump | ✅ | Headless: peak y = 1.66 m, lands back on floor; browser JUMP button wired to the same `_jump_queued`. (See warn W2.) |
| 18 | Audio presence | ✅ (infra) | AudioManager autoload + `default_bus_layout.tres`; music (`music_clearing.ogg`) + ambient (`forest_birds.ogg`) start on tap (after `unlock()`); `pickup` SFX on win, `ui` on jump/button; positional `fire.wav` loop on the campfire. Playback itself unverifiable in the muted container. |
| 19 | Winnability data (qgcheck) | n/a | No `world.json` — not a data-driven world; verifier correctly WARN-skipped. |
| 20 | Character sourcing | note | Hero is the KayKit Ranger (`kk_Ranger.glb`). Disclosed in the delegation (KayKit rig/clips named; explicitly a free-tier minimal build) and fully style-coherent with the low-poly commit — noting, not flagging. |

## Warns / polish (no ship impact)

- **W1 ⚠️ The handoff's QA hooks `window.gogiGetPlayer()` / `window.gogiSolids()` are dead in the
  real browser export — they ALWAYS return `null` / `[]`.** `JavaScriptBridge.create_callback`
  wrappers discard the GDScript return value (verified: `__gogiGetPlayerRaw()` returns JS `null`
  while the player demonstrably exists; `__gogiSolidsRaw()` also `null` though it can never
  legitimately return that string). Zero player impact, but the delegation's claim "returns
  {x,y,z,...}" is false and any future automated QA that trusts these will silently no-op.
  Fix direction (trivial, `main.gd:_setup_web_time_hooks`): push state to JS the way
  `__gogiTime` already does — e.g. update `window.__gogiPlayer` via `JavaScriptBridge.eval`
  once per N frames, or on demand from `_on_gogi_get_player`. `gogiSetTime`/`gogiGetTime`
  work (one-way + push pattern).
- **W2 ⚠️ Jump input can be eaten on a frame where `is_on_floor()` is momentarily false**
  (`_jump_queued` is cleared at the end of EVERY physics frame, no buffering) — observed once
  headless on the first frame after unpause (peak −0.01 vs 1.66 on retry). On flat ground it's
  a narrow window; a ~0.1 s jump buffer in `main.gd:_physics_process` would remove it entirely.
- **W3 ⚠️ Camera can sit inside tree canopies** when orbiting near in-clearing trees
  (`v-look.png` — foliage fills half the frame). Canopies deliberately have no colliders (good
  for walking); adding the canopy-free trunk-only choice to the SpringArm is why. Acceptable
  trade-off for the clearing's size; only worth touching if players complain.
- **W4 (obs)** The pond has no collider — the player wades through ankle-deep water (surface at
  y 0.07). Matches the "visual water" spec; fine for a cozy exploration game.
- **W5 (obs)** Verifier `FLAT-TINT` WARN is a false positive here — the only fresh
  `StandardMaterial3D`s are on particles and the no-model fallback capsule; the hero renders
  fully textured (all screenshots).
- **W6 (obs)** `verify.mjs`'s interactive/feel phase was cut by its own hard 120 s watchdog in
  this (slow, GPU-less) container after "PASS engine booted / PASS canvas present /
  3 frames" — the missing probes are all covered above by my own drivers. Not a build issue.

## Could not verify (sandbox limits)
Real audio playback (muted, no device), true-GPU visual fidelity / real frame rate
(SwiftShader only), touch feel on a physical phone, and the live preview URL from inside
headless Chromium (sandbox proxy cert). `/workspace` has no `.git`, so repo/branch state
(`joseb33w/forest-clearing@feat/forest-clearing-game`) was not inspectable here — verified the
local working tree + export only.

## Key screenshots
`/tmp/shots/`: `v-toast.png` (spawn/W, toast, JUMP), `v-face.png` (S-facing), `s-w1.png`
(cabin pin), `s-w5.png` (win panel), `s-w6.png` (Play Again → title), `s-w7.png` (restart
playable), `v-night.png`/`v-day.png` (time-of-day), `v-look.png` (orbit), `v-land-game.png`
(landscape fill).
