# Forest Clearing

A small, cozy 3D exploration game. You wake in a sunlit forest clearing — a wooden cabin,
scattered trees and rocks, a little pond with cattails, and a campfire. Somewhere in the
clearing a treasure chest is hidden. Walk around and find it.

No combat, no quests — just exploration.

## Controls

- **Phone:** left half of the screen = move joystick, right half = drag to look, JUMP button.
- **Desktop:** WASD / arrow keys to move, hold left mouse and drag to look, Space to jump.

## Tech

- Godot 4.7.1, Compatibility renderer (WebGL2), single-threaded (`nothreads`) web export —
  runs in Safari, Chrome and Firefox on mobile and desktop.
- CC0/CC-BY low-poly assets: KayKit (cabin, character, animation clips), Quaternius
  (trees, rocks, chest), Kenney (campfire, cattails, SFX). No AI-generated assets.
- Music/ambient: CC0 chiptune "clearing" theme + forest-bird ambience.

## Build

Open in Godot 4.7.1 and export with the **Web** preset (nothreads), or run:

```
godot --headless --path . --import
godot --headless --path . --export-release "Web" out/index.html
```
