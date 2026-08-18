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
**Not yet, but feasible.** The mechanism would be:
1. Gemini runs `make test` and `make shot` after completing work
2. If tests pass, Gemini shells out: `omp --model google-antigravity/claude-opus-4-6 --oneshot "Review /opt/src/foo for the issues in REVIEW_DOSSIER.md, write findings to docs/review.md"`
3. Gemini reads the review output and applies fixes

**Blockers**: omp doesn't currently support `--oneshot` mode for non-interactive review. The workaround is manual: human switches model or opens a second session. This is a reasonable human-in-the-loop checkpoint — adversarial review is precisely where human judgment adds most value.

### Cost Analysis
- Gemini 3.7 Flash (AI Pro): **Free** for typical usage within subscription quota
- DeepSeek V4 Flash: ~$0.20/M input, ~$0.80/M output → a 50-turn scaffolding session ≈ $1-3
- Opus 4.6 (AI Pro): **Free** within subscription quota (same `google-antigravity` OAuth)
- Qwen 3.7 Flash vision: ~$0.03/M → screenshot inspection ≈ $0.001/shot

**Recommendation**: Use Gemini Flash as the primary builder (free). Run Opus adversarial reviews after each major milestone (also free via AI Pro). Reserve DeepSeek V4 for parallel independent debugging sessions where the $1-3 cost is justified by time savings. The current setup of "build with Flash, review with Opus" is near-optimal for cost.

## Current Project Status & Pending Work

### Verified Status (2026-08-18)
- **Templates**: `templates/2d-canvas/` and `templates/3d-viewport/` are fully hardened with SDL_Renderer/D3D11 backends, static runtime linking, Lua 5.4 compatibility assertions, C++-to-Lua binding parity gates, and headless interactive UI smoke tests.
- **Skills & Scaffolding**: `skills/native-ui-ux`, `skills/imgui-recipes`, and `skills/scaffold-native-app` are fully synced with Nix home-manager (`/opt/src/nix-lab/hosts/wslop/hm/skills/`) and active harness (`~/.omp/agent/skills/`).
- **Evaluation Apps**:
  - `texturewrangler` (`/opt/src/texturewrangler`): 350/350 tests green, golden composite verified.
  - `godot-blockout` (`/opt/src/godot-blockout`): 35/35 tests green, 1-click `.tscn` export verified.
  - `lowpoly-painter` (`/opt/src/lowpoly-painter`): 30/30 tests green, auto-UV unwrapping & baking verified.

### Pending Work & Next Session Roadmap
1. **Automated Multi-Model Adversarial Review Wrapper**: Implement a scripted orchestrator once non-interactive review execution lands in the harness.
2. **High-DPI / Fractional Scaling Pass**: Add dynamic font size recalculation and UI scaling factor to `theme.lua` across both templates.
3. **Tileset Variation Layer Pattern**: Add a 4x4 procedural tileset variation modifier to the 2D canvas template.
