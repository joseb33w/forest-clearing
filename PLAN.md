# Goal
A small, simple 3D exploration game for mobile web (Godot 4.7.1, Compatibility/WebGL2, nothreads):
one forest clearing with a wooden cabin, scattered trees and rocks, a small pond, and a treasure
chest hidden behind the cabin. Walk around, find the chest, win. No combat, no quests.

# Files to touch
- `main.gd` — world build (clearing, cabin, pond, chest, scatter), player avatar + animation,
  chest-found win flow, HUD (jump button, objective toast, win panel).
- `anim_rig.gd` — vetted KayKit Rig_Medium clip retarget helper (from the RPG template).
- `models/` — library assets (KayKit home, Quaternius nature, chest, campfire; CC0).
- `audio/` — clearing music + forest-birds ambient + campfire loop (CC0).
- `.gitignore`, `README.md`.

# Verification approach
- Static pre-import grep (Variant `:=`, shadowed Node members), headless `--import` + export.
- Headless in-engine test: animation clips resolve (no T-pose), chest trigger fires when the
  player reaches it (win state + collision mask check).
- Browser smoke verify (verify.mjs): boot, clean console, frames; W/S facing frames;
  portrait + landscape fill screenshots.
- QA + Game-Feel specialist passes before PR.

# Out of scope
- No backend (single-player, no persistence needed).
- No Meshy / AI-generated assets (free-tier build; library character used as the player —
  disclosed in the PR).
- No combat, quests, inventory, or multi-area streaming.
