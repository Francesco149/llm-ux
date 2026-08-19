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
   - **Headless input drive (`lp.drive.*` + `--drive script.lua`)**: frame-accurate input injection with NO window focus, NO xdotool, NO synthetic OS events. C++ virtual-input override; Lua tape schedules clicks/drags/keys per frame; `drive_step()` before render + `drive_frame()` after. Every template MUST prefer this over window-focus tooling.

## Repository Map
- `skills/` -> Master LLM skill packs:
  - `skills/native-ui-ux/` -> Master UI/UX & Interaction Physics Doctrine.
  - `skills/scaffold-native-app/` -> Turnkey project generator blueprint.
  - `skills/imgui-recipes/` -> Production-tested C++ & Lua UI recipes.
- `templates/` -> Ready-to-use starter repositories (ONE raylib template — 2D is a subset of 3D, per the evaluation verdict):
  - `templates/raylib/` -> The template: Raylib 6.0 + rlImGui + Lua. 3D (models/textures/RLSL shaders/lighting, Godot-editor camera) AND 2D (tex canvas, MMB-pan viewport, 2D↔3D texture bridge, mode 5 texture paint) in one codebase. Headless `--test`/`--shot`/`--drive`, Windows cross (`make win`/`package`), modern dark theme, CJK+Cyrillic fonts.
- `tools/` -> Scaffolding and automation scripts:
  - `tools/scaffold.py` -> Instant repo generator CLI.
  - `tools/drive.lua` -> Frame-accurate headless input & tape driver (reference for template `editor/lua/drive.lua`).
  - `tools/embed.py` -> Font & asset C header embedder.
- `docs/` -> Deep research & technical references:
  - `docs/DIRECT_MANIPULATION_AND_FEEL.md` -> HCI principles, Fitts's law, spring physics.
  - `docs/WINDOWS_COMPAT_AND_WIN7.md` -> Cross-compilation, SDL_Renderer vs WGL, static runtimes.
  - `docs/ZERO_DATA_LOSS_AND_UNDO.md` -> Undo coalescing, state journaling, crash resilience.
  - `docs/STACK_EVALUATION_PLAN.md` -> A-vs-B stack evaluation plan + template findings.
  - `docs/CUBEFORGE_SPEC.md` -> The CubeForge evaluation test-app spec.
  - `docs/IMGUI_WRAPPER_DESIGN.md` -> Scoped ImGui wrapper + balance-tracker design.

## Test Gate Architecture
The `make test` gate runs four test suites in order. All must pass:
1. **`test_lua54_compat`** — Scans `editor/lua/*.lua` for removed Lua 5.4 APIs (`math.pow`, `unpack`, `loadstring`, etc.). Catches the entire class of "works in 5.1, crashes in 5.4" bugs at build time.
2. **`test_binding_parity`** — Verifies every expected `ig.*` function and `ig.key.*` constant is registered and callable. Catches the "C++ function exists but missing from REG() table" class.
3. **`test_mesh`** / domain tests — State mutation invariants (extrude adds faces, undo restores count, etc.).
4. **`test_ui_smoke`** — Exercises key constants > 500, `reset_mouse_drag_delta`, modal action state transitions, raycast intersection.

## Multi-Model Delegation Strategy

### Current Model Routing
- **Primary builder**: Gemini 3.7 Flash (via `google-antigravity` OAuth, free with AI Pro subscription). Handles scaffolding, feature implementation, and iterative refinement. Cheap enough for long multi-turn sessions.
- **Adversarial reviewer**: Claude Opus 4.6 or DeepSeek V4 Flash via `omp --model`. Used for one-shot adversarial code review of completed work.
- **Vision**: Qwen 3.7 Flash (OpenRouter, ~$0.03/1M input tokens) for screenshot inspection of `--shot` output.

### When to Offload to Opus or DeepSeek V4
Gemini Flash is sufficient for ~80% of the work (Lua feature code, panel layout, theme tuning, basic 3D math). Offload to a stronger model when:

| Trigger | Target Model | Mechanism |
|---|---|---|
| **Adversarial review** of completed template/app | Opus 4.6 or DeepSeek V4 | `omp --model google-antigravity/claude-opus-4-6` (or `deepseek/deepseek-v4-flash`) in a new session, pointed at the repo |
| **C++ binding layer changes** (ig.cpp, lua.cpp) | Opus 4.6 | C++ template metaprogramming, ABI reasoning, UB detection |
| **Cross-platform debugging** (Windows/Wine failures) | DeepSeek V4 | Cheap enough for iterative debugging; strong systems knowledge |
| **Architecture decisions** (new template design, skill restructuring) | Opus 4.6 | Better at multi-file reasoning and taste |
| **3D math / projection bugs** | Either | Matrix algebra, winding order, projection correctness |

### Can Gemini Spawn Opus/DeepSeek Autonomously?
**Yes — `omp -p` (non-interactive) mode works (verified 2026-08-19)**:
```sh
omp -p --model google-antigravity/gemini-3.7-flash --cwd /opt/src/foo @/tmp/task.md
```
Run in background, collect output, act on it. Used for the CubeForge stack
evaluation. `--mode json` exposes model identity + usage for verification.

### Cost Analysis
- Gemini 3.7 Flash (AI Pro): **Free** for typical usage within subscription quota
- DeepSeek V4 Flash: ~$0.20/M input, ~$0.80/M output → a 50-turn scaffolding session ≈ $1-3
- Opus 4.6 (AI Pro): **Free** within subscription quota (same `google-antigravity` OAuth)
- Qwen 3.7 Flash vision: ~$0.03/M → screenshot inspection ≈ $0.001/shot

**Recommendation**: Use Gemini Flash as the primary builder (free). Run Opus adversarial reviews after each major milestone (also free via AI Pro). Reserve DeepSeek V4 for parallel independent debugging sessions where the $1-3 cost is justified by time savings. The current setup of "build with Flash, review with Opus" is near-optimal for cost.

## Current Project Status & Pending Work

### Verified Status (2026-08-19)
- **ONE template, raylib-only**: `templates/raylib/` is the single starter (renamed from 3d-raylib). 3D AND 2D in one codebase — 2D canvas (lp.tex.*, lp.cam2d.*, MMB-pan viewport) is a subset of the 3D template, with a 2D↔3D texture bridge (paint a texture, apply to the 3D mesh). All SDL templates (2d-canvas, 3d-viewport, 3d-opengl) deleted — the evaluation showed raylib wins outright.
- **Stack evaluation verdict implemented**: Raylib + rlImGui + Lua, complex 3D Lua-only (models/textures/RLSL shaders), headless `--test`/`--shot`/`--drive`, Windows cross (`make win`/`package`), modern dark theme (deep slate + amber), CJK+Cyrillic fonts (Inter + IPA Gothic merged).
- **Scoped ImGui Wrappers**: 16 scoped Begin/End wrappers (`ig.window`, `ig.child`, …) + frame-end balance checker (`ig_balance_check()`). Eliminates the "Missing EndChild()" crash class. 112 bindings verified.
- **Camera doctrine (skills/native-ui-ux)**: 3D = Godot editor language (MMB tilt, RMB FPS fly + WASD/QE, Shift+MMB pan, wheel dolly); 2D = MMB pan, wheel cursor-anchored zoom.
- **Evaluation Apps** (reference, SDL-era):
  - `texturewrangler` (`/opt/src/texturewrangler`): 355/355 tests green, golden composite verified.
  - `godot-blockout` (`/opt/src/godot-blockout`): 35/35 tests green, 1-click `.tscn` export verified.
  - `lowpoly-painter` (`/opt/src/lowpoly-painter`): 30/30 tests green, auto-UV unwrapping & baking verified.

### Known Limitations & Active Investigation
1. **Stack Evaluation — COMPLETE (2026-08-19)**: ImGui is a hard requirement; Odin/Zig rejected (no first-class ImGui). Two stacks built and evaluated head-to-head with the same CubeForge spec on Gemini 3.7 Flash (`omp -p` non-interactive sessions, pinned model). Results: `docs/EVALUATION_RESULTS.md`.
   - **Stack A (OpenGL 3.3)**: all gates passed but **+368 C++ lines** for 5 GPU features; deleted.
   - **Stack B (Raylib)**: all gates passed with **+89 C++ lines** of thin wrappers; became the template.
   - **VERDICT: Raylib wins (4.9 vs 4.4 weighted)** — 4× less C++ work for identical 3D features, 30% faster completion. Gemini stays in Lua.
2. **Triple Backend Support & Continuous Resize (2026-08-19)**:
   - **Linux (OpenGL 3.3)**: Packaged as primary Nix derivation (`nix build`) and standalone portable directory (`make package-linux` / `make zip-linux`).
   - **Windows (OpenGL 3.3)**: Packaged via MinGW cross (`make win` / `make package` / `make zip-win`), Win7+ compatible.
   - **Windows (Direct3D 11 DXGI Flip Model)**: Dedicated D3D11 backend (`make win-d3d11` / `make package-d3d11` / `make zip-d3d11`), 100% continuous live redraw during sizing loops with zero stretching.
   - All 3 builds share common C++ wrappers (`app_paths.cpp`, `editor_theme.h`, `ig.cpp`, `fa6/`) and identical Lua codebase.
3. **Embedded FontAwesome 6 Icon System & UI Polish (2026-08-19)**:
   - Binary compressed FontAwesome 6 Solid TTF atlas embedded in binary with zero runtime font dependencies (`src/fa6/`).
   - Exposes `ig.icon.*` constants table to Lua across toolbars, selection mode pills, and sidebar actions.
4. **Multi-Tier Asset & User Storage System (`src/app_paths.h`)**:
   - 6-tier asset resolution (environment variables, executable dir, cwd, FHS relative, user data dir, system `/usr/share/`).
   - Cross-platform user config, project saving, and persistent storage APIs (`lp.app.get_config_dir`, `get_data_dir`, `get_documents_dir`, `get_projects_dir`, `save_user_file`, `load_user_file`).
### Pending Work & Next Session Roadmap
1. **Harder-spec re-eval** (textured materials, custom shaders, GPU picking) to confirm the raylib advantage widens with complexity.
2. **Sync skills to deployed harness**: push updated skill .md files to Nix home-manager and active harness.
3. **High-DPI / Fractional Scaling Pass**: dynamic font size recalculation and UI scaling factor.
4. **CJK font swap note**: IPA Gothic (TrueType, works with ImGui's stb loader) is the default CJK fallback; swap to a full SC TTF (e.g. WenQuanYi) via `FONT_CJK` for complete simplified-Chinese coverage.
