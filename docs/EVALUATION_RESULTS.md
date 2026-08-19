# CubeForge Stack Evaluation — Results

Date: 2026-08-19
Model: google-antigravity/gemini-3.7-flash (pinned; verified via `--mode json`: api=google-gemini-cli, model=gemini-3.7-flash)
Method: `omp -p` non-interactive sessions, one per template, same CubeForge spec (`/tmp/cubeforge_prompt_{raylib,opengl}.md`). Headless drive tapes + screenshots for verification. All gates independently re-run after the sessions.

## Scores

| Criterion | Weight | Stack A (OpenGL) | Stack B (Raylib) | Notes |
|---|---|---|---|---|
| Crash-free | 30% | 5 | 5 | All gates exit 0; drive tapes exercised orbit/spawn/extrude/paint/undo; zero balance-checker warnings |
| 3D correctness | 20% | 5 | 5 | Depth verified (vision + topology assertions: A 6→10→14 faces; B 16-vert/14-face); no z-fighting |
| UI quality | 15% | 4 | 5 | Both scoped-wrappers-only; B richer (scene stats, status log); A minimalist but clean |
| Code quality | 15% | 4 | 5 | Both modular Lua (doc/undo/main); B 46 tests vs A 38; A's GPU plumbing is competent but higher-risk surface |
| Build simplicity | 10% | 4 | 4 | Both single flake + make, linux-only; A Windows cross-compiles but needs GL loader; B has no Windows target |
| Iteration speed | 10% | 3 | 5 | A: 9.2 min, 5 substantive C++ edits (368 lines); B: 6.5 min, 89 thin wrapper lines |
| **Weighted total** | | **4.4** | **4.9** | |

## Objective gates (independently re-verified post-eval)

| Gate | Stack A | Stack B |
|---|---|---|
| make linux (clean) | PASS (0 errors) | PASS (0 errors) |
| make test (exit 0) | PASS (38 checks) | PASS (46 checks) |
| shot-drive (assertion) | PASS (orbit 2.22 rad) | PASS (orbit + spawn + extrude assertions) |
| shot (PNG exists) | PASS (1280x800) | PASS |
| 10 boxes no slowdown | PASS (<1 ms) | PASS (60 faces) |
| extrude×2 after 180° rotate | PASS (topology 6→10→14) | PASS (16-vert/14-face, vision-verified) |
| rapid undo/redo during extrude | PASS (20 cycles) | PASS |
| C++ changes required | **368 lines / 5 functions** | **89 lines / 6 wrappers** |

## The decisive finding: C++ change depth

| | Stack A (OpenGL) | Stack B (Raylib) |
|---|---|---|
| Per-3D-feature C++ work | Real GPU plumbing: `render3d_update_mesh` (glBufferData), `render3d_unproject` (analytical 4×4 matrix inversion), `render3d_project`, extended draw_mesh highlight, dynamic line batching | Thin wrappers over raylib: `load_model_cylinder`, `draw_cylinder[_wires]`, `draw_triangle_3d`, `world_to_screen`, key constants |

Stack A's additions are new algorithms (matrix inversion, buffer management) — exactly the class of code where subtle bugs live (and which needs adversarial review). Stack B's additions are 3-line passthroughs to battle-tested raylib functions.

## Interaction stress (headless drive tapes)

- [x] orbit + click button — both
- [x] extrude modal confirm — both
- [x] extrude modal cancel (restore) — both
- [x] paint stroke — both (A: paint + OBJ export verified)
- [x] undo/redo during drag — both (A: 20 rapid cycles)

## Friction findings

### Stack A (OpenGL)
- `io.WantCaptureKeyboard` blocked hotkeys in headless mode → gated on `!io.want_text_input`.
- Offscreen driver yields sub-ms DeltaTime → camera damping needed `max(dt, 0.016)` clamp.
- `ig.child` flags are ints, not booleans (documented binding contract).

### Stack B (Raylib)
- rlImGui queries raw raylib input (not the lp.rl overrides) → drive mode must also sync `ImGui::GetIO()` in C++ after `rlImGuiBegin()`.
- Enum tables are namespaced (`ig.col.*`/`ig.var.*`/`ig.wflag.*`) — Gemini noted the flat `ig.Col_*` assumption.
- ImGui drive routing is the one place where the virtual-input override needs C++ cooperation beyond the getters.

## Verdict

**Stack B (Raylib + rlImGui + Lua) wins for Gemini-driven tools** (4.9 vs 4.4). The decisive factor is iteration speed: complex 3D features (extrude, picking, painting, multi-primitive scenes) required 4× less C++ work and finished 30% faster, because raylib already owns the GPU plumbing. For the stated goal — more complex 3D apps with Gemini as the builder — Stack B is the template base.

**Stack A (OpenGL) is retired**: its custom render passes / FBO compositing use cases can be reached through raylib's `RenderTexture` + RLSL shaders with far less C++ surface. The template was deleted (2026-08-19).

## Outcome (2026-08-19)

**The verdict became the template set.** Stack B (raylib) is now the ONLY
template (`templates/raylib/`): SDL templates (2d-canvas, 3d-viewport,
3d-opengl) were deleted. Per user direction, 2D is a subset of the 3D template
(2D canvas + `lp.tex`/`lp.cam2d` surfaces alongside 3D, with a 2D↔3D texture
bridge) so one codebase serves 2D-only, 3D-only, and mixed projects.

## Action items
1. **DONE — Windows target (2026-08-19)**: mingw cross via `pkgsCross.mingwW64.raylib`; `make win` + `make package`; ships exe + `libraylib.dll` + `glfw3.dll` (raylib links GLFW dynamically) + `libmcfgthread-2.dll` + lua/ + tests/. Layout-aware root resolution for packaged mode; `lp.file.mkdirs` for exports. Verified on the Windows host: 46/46 tests pass, headless shot works, live window renders (vision-verified). Recipe documented in `skills/scaffold-native-app` §5b.
2. **DONE — single raylib template**: `templates/raylib/` (renamed from 3d-raylib), 2D+3D in one codebase.
3. Re-run the same eval with a harder spec (textured materials, custom shader, GPU picking) to confirm the gap widens with complexity.
