# lowpoly-painter — orientation

Specialized low-poly 3D modeler and handpainted texture painter with auto UVs and procedural bake effects
C++ is a slim core (SDL3/D3D11 window, imgui, Lua VM, GPU/math kernels); ALL UI, interaction logic,
and document state are embedded Lua 5.4.

## Environment & Build Rules
- Everything builds and runs via `nix develop`.
- `make -C editor`         -> Cross-compiles standalone Windows 64-bit PE (D3D11) via MinGW -> `build/lowpoly-painter.exe`.
- `make -C editor linux`   -> Compiles native Linux binary (SDL3/OpenGL) -> `build/lowpoly-painter`.
- `make -C editor test`    -> Runs headless test suite (assertions on state & kernels).
- `make -C editor shot`    -> Captures offscreen UI screenshot to `build/shot.png`.
- `make -C editor package` -> Assembles standalone release folder with all dependencies.

## Architecture & Code Map
- `editor/src/` -> C++ backend (window, GPU textures, Lua bindings, heavy computation).
  - `main.cpp` -> Args parsing, CLI modes (--shot, --test, --eval, --lua), main loop.
  - `app.cpp`  -> SDL3 platform/event loop, headless offscreen rendering, frame pacing.
  - `ig.cpp`   -> Dear ImGui 1.92 binding, modern dark theme, font atlas.
  - `lua.cpp`  -> Lua 5.4 VM host, error capture (pcall), module registration.
- `editor/lua/` -> Product implementation (UI panels, canvas/viewport, undo, autosave, tools).
  - `main.lua` -> Bootstrap, frame orchestration, global shortcuts, panel layout.
  - `doc.lua`  -> Document model, mutations, JSON serialization.
  - `undo.lua` -> Snapshot undo/redo journal + undo.jsonl cross-session persistence.
  - `autosave.lua` -> 300ms debounced autosave + backup rotation.
  - `theme.lua` -> Color constants and styling.
  - `ui.lua`   -> UI widgets, tooltips with hotkey badges, floating pill toolbar.
  - `preview.lua` -> Interactive viewport/canvas with smooth cursor-anchored navigation.
- `assets/fonts/` -> Embedded fonts (Inter, JetBrains Mono, vector glyphs).

## Interaction & Feel Invariants
- 60 FPS locked, zero-latency input polling.
- Cursor-anchored pan/zoom with smooth exponential lerp.
- Infinite multi-session undo (`undo.jsonl`), debounced 300ms autosave.
- All actions have keyboard shortcuts and clear tooltips.
