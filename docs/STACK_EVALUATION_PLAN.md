# Stack Evaluation Plan: Finding the Optimal LLM-Driven 3D Tool Stack

## Context

The current Lua+C++/ImGui stack works well for 2D tools (TextureWrangler: 350 tests, golden composite verified). For 3D tools, it has fundamental limitations:

1. **ImGui DrawList is 2D-only** — no depth buffer, no proper occlusion
2. **Painter's algorithm fails** — intersecting geometry, >1000 faces, concave meshes
3. **ImGui Begin/End pairing** — recurring LLM crash source (now mitigated with scoped wrappers)
4. **All 3D math in Lua** — slow, error-prone, duplicates work better done on GPU

## Test App: "CubeForge"

A minimal 3D block editor that exercises every failure mode:

### Required Features
1. **3D Viewport** — Perspective camera, orbit/pan/zoom, depth-correct rendering
2. **Primitive Spawning** — Add box, cylinder at origin
3. **Face Selection** — Click in viewport to select (raycast or GPU picking)
4. **Extrude** — Press E → modal extrude along face normal
5. **Move** — Press G → modal move in screen plane
6. **Vertex Painting** — Click to paint colors directly in 3D
7. **Side Panel** — Property panel with sliders, color picker
8. **Undo/Redo** — Ctrl+Z/Y with coalescing
9. **OBJ Export** — Save to .obj file

### Stress Tests
1. Extrude face, rotate 180°, extrude again → depth must be correct
2. Add 10 boxes → no slowdown
3. Click any button → must not assert "Missing EndChild"
4. Resize window during modal operation → no crash
5. Rapid undo/redo → no state corruption

### Scoring (1-5 each)
| Criterion | Weight | Description |
|-----------|--------|-------------|
| Crash-free | 30% | No asserts/segfaults on any interaction path |
| 3D correctness | 20% | Proper depth, no z-fighting, intersections work |
| UI quality | 15% | Panels don't glitch, theme looks good |
| Code quality | 15% | Clean, idiomatic, maintainable across sessions |
| Build simplicity | 10% | Single nix shell, one make command |
| Iteration speed | 10% | How fast Gemini adds features without breaking |

## Stacks to Evaluate

### Stack A: Lua + C++/OpenGL 3.3 + ImGui
**Architecture change**: Switch ImGui backend from `imgui_impl_sdlrenderer3` (D3D11/Vulkan via SDL_Renderer) to `imgui_impl_opengl3` + `imgui_impl_sdl3` (direct OpenGL 3.3). This gives direct GL access for 3D rendering within the same context.

```
┌─────────────────────────────────┐
│ Lua 5.4: UI, tools, doc model   │
│   ig.child("panel", fn)         │  ← scoped ImGui wrappers
│   render3d.draw_mesh(mesh_id)   │  ← C++ 3D module
├─────────────────────────────────┤
│ C++ Core                        │
│   ig.cpp     ImGui bindings     │
│   render.cpp OpenGL 3.3 + FBO   │  ← NEW: depth buffer, shaders
│   lua.cpp    Lua VM             │
│   mesh.cpp   geometry ops       │
├─────────────────────────────────┤
│ OpenGL 3.3 Context (SDL3)       │
│   ImGui renders here too        │
│   Works on Linux + Windows 7+   │
└─────────────────────────────────┘
```

**Key 3D API surface for Lua**:
```lua
-- Upload mesh to GPU (called on change, not per frame)
local mesh_id = render3d.upload(verts_flat, indices_flat)
render3d.update(mesh_id, verts_flat)  -- re-upload verts only
render3d.delete(mesh_id)

-- Render frame  
render3d.set_camera(eye, target, up, fov)
render3d.begin_frame(w, h, bg_color)
render3d.draw_mesh(mesh_id, highlight_face)
render3d.draw_grid(extent, step)
render3d.end_frame()  -- returns texture_id

-- Display in ImGui viewport
ig.dl_add_image(dl, texture_id, x, y, x+w, y+h)

-- GPU-accelerated picking
local face = render3d.pick(mouse_x, mouse_y)
```

**Pros**: Keeps ImGui for complex UI, real depth buffer, same Lua workflow
**Cons**: OpenGL shader management in C++, GL context vs D3D11
**Risk**: OpenGL 3.3 on older Windows hardware (mitigated: GL3.3 is universal on Win7+)

### Stack B: Lua + Raylib + ImGui (via rlImGui)
**Architecture**: Raylib handles windowing and 3D. rlImGui bridges ImGui panels into Raylib's GL context.

```
┌─────────────────────────────────┐
│ Lua 5.4: UI, tools, doc model   │
│   ig.child("panel", fn)         │
│   rl.draw_model(model)          │
├─────────────────────────────────┤
│ C++ Core                        │
│   ig.cpp     ImGui bindings     │
│   rl.cpp     Raylib bindings    │  ← Raylib 3D API
│   lua.cpp    Lua VM             │
├─────────────────────────────────┤
│ Raylib + rlImGui                │
│   3D + ImGui overlay            │
└─────────────────────────────────┘
```

**Pros**: Raylib has built-in 3D with depth, cameras, models, shaders
**Cons**: Two rendering systems, rlImGui maintenance, different structure
**Risk**: rlImGui bridge reliability

### Stack C: Odin — **REJECTED (2026-08-19)**
**Hard requirement: ImGui.** Odin's vendor directory has **no imgui** (verified against nixpkgs odin dev-2026-07a `$ODIN_ROOT/vendor/`: raylib, sdl2, sdl3, glfw, microui, nanovg — no imgui). ImGui would require a community cimgui binding with uncertain maintenance. Without first-class ImGui, the stack fails the UI requirement. Template built then deleted. Findings preserved below.

### Stack D: Zig — **REJECTED (2026-08-19)**
**Hard requirement: ImGui.** raylib.zig (ryupold) targets Zig master + raylib 5.1-dev (mismatch with zig 0.16.0/raylib 6.0); the viable `@cImport` path builds fine, but ImGui-in-Zig requires cimgui/zig-imgui community bindings with version-churn risk. Not worth testing against stacks with first-class ImGui. Template built then deleted. Findings preserved below.

## Evaluation Process

1. OUTCOME: Stack B (raylib) became the single template (templates/raylib/); Stack A (3d-opengl) deleted; 2D merged in as a subset. Both evaluated stacks had first-class ImGui + scoped wrappers.
2. Give Gemini Flash the same CubeForge spec for each.
3. Observe: crash count, 3D quality, iteration speed — especially on the "more complex than unshaded cube" features (lit/textured meshes, shaders, picking).
4. Score each stack on the rubric.
5. Pick winner for template investment.

## Timeline
- Stack A (OpenGL): enhances existing investment, but every new 3D feature (textures, shaders, lighting, picking) needs new C++ binding work.
- Stack B (Raylib): hypothesis — raylib's built-in 3D (models, textures, RLSL shaders, materials, lighting) means complex 3D features are Lua-only, so Gemini iterates without touching C++. Verify with the lit-textured-model demo before the eval.

## Template Build Findings (2026-08-19)

All four starter templates built and verified. Key discoveries that revised the plan:

**DECISION (2026-08-19): ImGui is a hard requirement → only Stacks A and B are evaluated. Odin and Zig templates deleted.**

### Stack A — 3d-opengl (built, evaluated, then deleted): BUILDABLE, depth-correct, Windows caveat
- Deferred-GL design (uploads/draws queue CPU-side, GPU work happens in `render3d_flush()`) keeps `--test` headless-safe.
- `#include <SDL3/SDL_opengl.h>` with `GL_GLEXT_PROTOTYPES` — no GLEW/GLAD needed (per constraint).
- Depth test verified pixel-exact: grid drawn after cube does not bleed through; zero back-face pixels.
- **Windows caveat**: mingw cross-COMPILES, but `opengl32.dll` exports only GL 1.1 — final link needs a runtime GL loader (`SDL_GL_GetProcAddress` extension point documented in ORIENTATION). This is the main gap vs the SDL_Renderer/D3D11 path.

### Stack B — 3d-raylib (became templates/raylib/): BUILDABLE, simplest, real caveat
- rlImGui (raylib-extras, MIT) is only 3 files: `rlImGui.cpp/h/rlImGuiColors.h`. Cloned, vendored, built clean.
- Raylib 6.0 from nixpkgs works out of the box; Lua bindings are a thin `lp.rl.*` surface (DrawCube, camera, ray, input).
- Frame structure: `BeginDrawing → BeginMode3D → lp_draw3d() → EndMode3D → rlImGuiBegin → lp_frame() → rlImGuiEnd → EndDrawing`.
- **No Windows cross target** in the flake (raylib mingw cross is a bigger lift).

### Stack C — 3d-odin: BUILDABLE, **vendor:imgui DOES NOT EXIST**
- Verified against nixpkgs odin (dev-2026-07a) `$ODIN_ROOT/vendor/`: raylib, sdl2, sdl3, glfw, microui, nanovg present — **no imgui**. The plan's `vendor:imgui` assumption was wrong.
- Resolution: raylib-native UI (rounded-rect panel, toggle buttons, custom slider in `src/ui.odin`). ImGui swap would need a community cimgui binding or `vendor:microui`.
- nixpkgs odin patches vendor:raylib to link system raylib 6.0 + raygui 4.0 (dynamic). raygui is required even when unused (raygui.odin/raymath.odin/easings.odin are all `package raylib`).
- Ran under WSLg, vision-verified: depth-correct cube, grid, panel, 60 FPS.

### Stack C — 3d-odin (built, then deleted): **vendor:imgui DOES NOT EXIST**
- Verified against nixpkgs odin (dev-2026-07a) `$ODIN_ROOT/vendor/`: raylib, sdl2, sdl3, glfw, microui, nanovg present — **no imgui**. The plan's `vendor:imgui` assumption was wrong.
- nixpkgs odin patches vendor:raylib to link system raylib 6.0 + raygui 4.0 (dynamic). raygui is required even when unused (raygui.odin/raymath.odin/easings.odin are all `package raylib`).
- Deleted because ImGui is a hard requirement (see DECISION above).

### Stack D — 3d-zig (built, then deleted): **ImGui-in-Zig is community-binding territory**
- raylib.zig (ryupold) targets Zig master + raylib 5.1-dev — mismatches our zig 0.16.0/raylib 6.0. `@cImport` of system raylib.h works cleanly (translate-c zero errors), but ImGui still needs cimgui/zig-imgui.
- Deleted because ImGui is a hard requirement (see DECISION above).

### Revised evaluation notes
- **The scoped-wrapper Begin/End fix is in both surviving templates** — the "Missing EndChild" class is structurally eliminated before the evaluation even starts.
- **Stack B's central hypothesis to test**: raylib's built-in 3D means complex 3D features (textures, lighting, RLSL shaders, model loading, GPU picking) are Lua-only — Gemini never touches C++. Stack A requires new C++ binding work per 3D feature. If B proves this, it wins on iteration speed for anything beyond unshaded cubes.
