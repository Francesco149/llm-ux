# CubeForge — Evaluation Test App Spec

## What It Is
A minimal low-poly 3D block editor for building game-ready CSG-style geometry.
Think: Blockbench meets Blender's edit mode. Target: indie game devs making
blocky 3D assets.

## Required Features

### 1. 3D Viewport (Center)
- Perspective camera with orbit (right-drag), pan (shift+right-drag / middle-drag / space+left-drag), dolly (scroll wheel)
- Smooth inertial camera with exponential lerp: `cam = cam + (target - cam) * (1 - exp(-dt * 22))`
- **Proper depth-tested rendering** — no painter's algorithm, no z-sorting in Lua
- Ground grid with near-plane clipping
- Background: deep slate (#18181c)

### 2. Primitive Spawning
- Buttons in toolbar: "+ Box", "+ Cylinder"
- Spawns at world origin
- Auto-generates UVs

### 3. Face Selection
- Left-click in viewport selects a face
- Raycast-based picking (Möller–Trumbore or GPU color-ID)
- Front-face only (backface culling for picks)
- Selected face highlighted with accent color
- Selection mode hotkeys: 1=Vertex, 2=Edge, 3=Face

### 4. Extrude (E key)
- Modal state machine: E → mouse drag along face normal → LClick/Enter confirms, RClick/Esc cancels
- Live preview during drag
- Floating HUD badge: "EXTRUDE: +0.85m | LClick: Confirm · RClick: Cancel"
- Pushes undo state on confirm only

### 5. Move (G key)
- Modal: G → mouse drag in screen-aligned plane → confirm/cancel
- Works for face, vertex, or edge selection mode

### 6. Vertex Painting
- Mode 4 or B key
- Left-drag in viewport paints vertex colors
- Brush radius and color configurable in side panel

### 7. Side Panel (Right, ImGui)
- Selection mode pills (Vertex/Edge/Face/Paint)
- Brush settings: radius slider, hardness slider, color picker
- Hotkey reference
- Using scoped wrappers: `ig.child("panel", w, h, function() ... end)`

### 8. Undo/Redo
- Ctrl+Z / Ctrl+Y
- Coalescing: continuous drags = single undo entry
- Snapshot-based

### 9. OBJ Export
- Ctrl+E or button
- Writes .obj + .mtl to build/

## Architecture Rules
- C++ is a slim core: windowing, 3D rendering, ImGui, Lua VM, compute kernels
- ALL UI logic, document model, tool state, undo are Lua 5.4
- Use scoped ImGui wrappers: `ig.window()`, `ig.child()`, `ig.popup()` etc.
- Never use raw `begin_child`/`end_child` in panel code
- Use `ig.key.*` named constants, never raw integers
- Lua 5.4: no `math.pow`, no `unpack`, use `^` operator

## Non-Goals
- No animation
- No multi-object scenes (single mesh only)
- No texture mapping (vertex colors only for evaluation)
- No import (export only)

## Verification
```bash
make -C editor linux    # builds
make -C editor test     # all tests pass
make -C editor shot     # offscreen screenshot
```
