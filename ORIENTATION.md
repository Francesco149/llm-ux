# llm-ux — orientation

The definitive framework, harness configuration, and skill repository for getting LLMs (Gemini 3.7 Flash, DeepSeek, Claude Opus) to build high-performance, polished, native desktop creation tools (Dear ImGui 1.92+, C++, Lua 5.4) that feel incredible, never crash, and run flawlessly on Windows 7+ and Linux.

## Core Architectural Invariants
1. **Feel is Priority #1**:
   - 60 FPS / refresh rate locked with zero drawing latency.
   - **Cursor-Anchored Zoom**: Scroll wheel zooms anchored at the mouse pointer without resetting pan offsets.
   - **Smooth Navigation**: Middle-drag, Space+Left-drag pan with smooth inertial spring lerp ($1 - e^{-22\Delta t}$).
   - **Drag Deadzones**: 3-4px deadzone before initiating drags to prevent accidental 1px moves on clicks.
2. **Creator Ergonomics (Figma / tldraw / Godot Standard)**:
   - Single-key hotkeys without modifier clutter (`V` Select, `H` Pan, `B` Brush, `E` Eraser/Extrude, `F` Focus/Frame, `Z` Undo, `0` Fit, `1` 100%).
   - Tooltips with hotkey badges on **every** button.
   - Right-click context menus at cursor (`ImGui::OpenPopupOnItemClick`).
   - Group drill-down: click group selects group, click again drills to child, Escape pops back up.
3. **ImGui Modern Styling (Never Default Gray)**:
   - Deep slate palette (`#18181f`), rounded corners (`WindowRounding = 6.0`, `FrameRounding = 4.0`, `PopupRounding = 6.0`), subtle borders (`#292933`), and vibrant amber/cyan accents.
   - Embedded vector fonts (`InterVariable.ttf`, `JetBrainsMono-Regular.ttf`) with dynamic font atlas for crisp text at any zoom.
4. **State Safety & Zero Data Loss**:
   - **Undo Coalescing**: Continuous interactions (dragging sliders, painting strokes, scrubbing gizmos) coalesce into a single undo step on release (`IsItemDeactivatedAfterEdit()`).
   - **Cross-Session Undo**: Snapshot stream persisted to `undo.jsonl`.
   - **Debounced 300ms Autosave** + backup rotation (`backup.1.json`, `backup.2.json`).
5. **Windows 7+ Standalone Compatibility (Zero Footguns)**:
   - `-DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE`.
   - SDL3 + `SDL_Renderer` (D3D11 on Windows, Vulkan/OpenGL on Linux) to eliminate OpenGL/WGL initialization errors.
   - Static linking `-static -static-libgcc -static-libstdc++ -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic`.
   - Standalone `make package` copies exe, `SDL3.dll`, runtime DLLs, and `lua/` into a portable folder.
6. **Headless Verification & Smoke Test Gates**:
   - Offscreen screenshot capture (`--shot build/shot.png --frames 20`) for instant visual inspection via vision models.
   - Headless unit & invariant test suite (`--test`).

## Repository Map
- `skills/` -> Master LLM skill packs:
  - `skills/native-ui-ux/` -> Master UI/UX & Interaction Physics Doctrine.
  - `skills/scaffold-native-app/` -> Turnkey project generator blueprint.
  - `skills/imgui-recipes/` -> Production-tested C++ & Lua UI recipes.
- `templates/` -> Ready-to-use starter repositories:
  - `templates/2d-canvas/` -> 2D infinite canvas / image / texture creation tool.
  - `templates/3d-viewport/` -> 3D CSG blockout / low-poly modeling & painting tool.
- `tools/` -> Scaffolding and automation scripts:
  - `tools/scaffold.py` -> Instant repo generator CLI.
  - `tools/drive.lua` -> Frame-accurate headless input & tape driver.
  - `tools/embed.py` -> Font & asset C header embedder.
- `docs/` -> Deep research & technical references:
  - `docs/DIRECT_MANIPULATION_AND_FEEL.md` -> HCI principles, Fitts's law, spring physics.
  - `docs/WINDOWS_COMPAT_AND_WIN7.md` -> Cross-compilation, SDL_Renderer vs WGL, static runtimes.
  - `docs/ZERO_DATA_LOSS_AND_UNDO.md` -> Undo coalescing, state journaling, crash resilience.
