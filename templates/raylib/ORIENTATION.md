# CubeForge — the raylib template (2D + 3D)

CubeForge evaluation template: **2D is a first-class subset of the same project
as the 3D CubeForge.** One Raylib window, one Lua VM — a 2D texture-paint
canvas (`lp.tex.*` / `lp.cam2d.*` / world-space `lp.rl` 2D draw bindings) sits
alongside the 3D block editor, and the painted texture is applied straight onto
the 3D cube (`lp.tex.apply_to_model`). This proves seamless 2D+3D integration
in ONE codebase.

C++ is a slim core (Raylib window, rlImGui bridge, Lua VM, `lp.rl.*` / `lp.ig.*`
/ `lp.tex.*` / `lp.cam2d.*` bindings); ALL UI, interaction logic, camera, and
document state are embedded Lua 5.4.

## Architecture
- **3D Rendering**: Raylib 6.0 (hardware depth buffer, models, textures, RLSL shaders, lighting)
- **2D Rendering**: offscreen canvas (CPU `Image` + GPU `Texture2D`) drawn in a world-space 2D pass (`lp.rl.begin_mode2d` / `lp.cam2d`)
- **UI Panels**: Dear ImGui 1.92 via rlImGui bridge (scoped wrappers: `ig.window`, `ig.child`, etc.)
- **Logic**: Lua 5.4 — all tools, document model, cameras, undo
- **Frame structure**: `BeginDrawing` → `BeginMode3D` → `lp_draw3d()` → `EndMode3D` → `lp_draw2d()` (mode 5 only) → `rlImGuiBegin` → `lp_frame()` → `rlImGuiEnd` → `EndDrawing`
- **Complex 3D is Lua-only**: models, textures, and custom shaders are created/configured from Lua (`lp.rl.load_model_cube`, `load_texture_perlin`, `load_shader`, `set_material_*`, `set_shader_value_*`). New 3D features require ZERO C++ changes.
- **2D↔3D bridge**: the canvas texture is bound to a 3D model material (`lp.tex.apply_to_model`) — painting in 2D shows up on the cube in 3D. The demo cube starts with a perlin texture; entering mode 5 swaps it for the canvas.

## Modes (hotkeys 1-5)
- `1` Vertex / `2` Edge / `3` Face / `4` (or `B`) Vertex Paint — 3D editing modes
- `5` **Texture Paint (2D)** — the viewport becomes a 2D canvas view of the
  512×512 paint texture; left-drag stamps paint, and the canvas is applied to
  the active 3D mesh so the stroke appears on the cube.

## 2D controls doctrine
- **MMB pan** — content follows the drag (scaled by zoom)
- **Wheel zoom** — cursor-anchored: the world point under the cursor stays put
- **LMB** — paint a stroke (brush radius/color shared with the vertex-paint brush)
- **Ctrl+Z / Ctrl+Y** — canvas undo/redo (stroke coalescing: one undo per stroke)
- 3D controls are unchanged (Godot language): MMB tilt, Shift+MMB pan, RMB fly WASD/QE, wheel dolly.

## Build & Headless Verification (preferred over window-focus tools)
```sh
nix develop
make -C editor linux        # → build/cubeforge-raylib
make -C editor win          # → build/cubeforge-raylib.exe (mingw cross)
make -C editor package      # → build/cubeforge-raylib-win64/ standalone folder
make -C editor test         # headless boot + binding checks (no window)
make -C editor shot         # headless screenshot → build/shot.png (hidden window)
make -C editor shot-drive   # 3D orbit tape → build/shot_orbit.png (camera moved)
make -C editor shot-pan     # 2D pan tape → build/shot_pan.png (MMB pan moved cam2d)
make -C editor shot-paint   # 2D→3D paint tape → build/shot_paint3d.png (painted cube)
make -C editor run          # interactive
```

CLI modes:
```sh
build/cubeforge-raylib                            # interactive
build/cubeforge-raylib --test                     # boot VM + run tests/testmain.lua
build/cubeforge-raylib --shot out.png --frames N  # hidden-window capture, N frames
build/cubeforge-raylib --shot out.png --frames N --drive editor/tests/drive_pan.lua
```

## Windows (mingw cross)

Cross-compiles against `pkgsCross.mingwW64.raylib` 6.0. **The nixpkgs mingw
raylib links GLFW dynamically** — the package ships `libraylib.dll` +
`glfw3.dll` + `libmcfgthread-2.dll` + the exe + `lua/` + `tests/`. The exe is
layout-aware: `--test`/`--shot`/`--drive` and root resolution work from the
packaged folder (`lua/` directly next to the exe), not just the dev tree.

Smoke-test on the Windows host (WSLInterop):
1. `make package`, copy `build/cubeforge-raylib-win64/*` to `C:\cubeforge-raylib`.
2. `--test` via a .bat with stdout redirect → expect `All binding and logic checks passed`, exit 0.
3. Interactive: `Start-Process -PassThru` → `MainWindowHandle != 0` → screen-capture → vision-check.
4. Exports write into `build/` (created by `lp.file.mkdirs` / `lp.tex.export_png`).

Gotchas: `0xC0000135` = missing DLL — check `objdump -p <exe>.exe | grep 'DLL Name'` for the exe AND every shipped DLL (raylib pulls glfw3.dll transitively). Never launch a Windows exe from a WSL UNC cwd.

## Headless input drive (lp.drive.*)
The C++ `lp.drive.*` layer is a virtual-input override: when active, ALL
`lp.rl.*` input getters return injected state instead of real input. This
makes frame-accurate input tests possible with **no window focus, no xdotool,
no synthetic OS events** — the app just runs hidden and a Lua tape drives it.

Drive script pattern (`editor/tests/drive_pan.lua`):
```lua
local D = require("drive")
D.tap(2, D.Key.Five)                        -- enter 2D texture-paint mode
D.drag(4, 400, 400, 500, 400, 8, 2)         -- middle-drag = 2D pan
D.at(20, function() ... assert CF.cam2d.pan moved ... end)
```
Run with `--drive`. The C++ loop calls `drive_step()` before each frame's
render and `drive_frame()` after (the frame boundary advances the prev-pos
baseline so delta math is correct).

`lp.drive` API:
- `lp.drive.active(bool)` — enable/disable the override
- `lp.drive.mouse(x, y)` — set cursor pos
- `lp.drive.button(btn, down)` — 0=left 1=right 2=middle (pressed edge tracked)
- `lp.drive.wheel(dy)` — accumulate wheel for this frame
- `lp.drive.key(code, down)` — raylib keycodes; `lp.rl.key.*` constants
- `lp.drive.frame()` — frame boundary (advance prev-pos, clear wheel/pressed)

## Lua API — 3D
- `lp.rl.draw_cube(x,y,z, w,h,d, r,g,b,a)` — draw solid cube
- `lp.rl.draw_cube_wires(...)` — wireframe
- `lp.rl.draw_grid(slices, spacing)` — ground grid
- `lp.rl.draw_line_3d(x1,y1,z1, x2,y2,z2, r,g,b,a)` — 3D line
- `lp.rl.draw_sphere(x,y,z, radius, r,g,b,a)` — sphere
- `lp.rl.draw_sphere_wires(x,y,z, radius, rings, slices, r,g,b,a)` — brush reticle
- `lp.rl.set_camera(ex,ey,ez, tx,ty,tz, fov)` — update camera
- `lp.rl.get_camera()` — returns table with eye/target/fov
- `lp.rl.get_ray(mx, my)` — screen-to-world ray (6 returns: ox,oy,oz, dx,dy,dz)
- `lp.rl.load_model_cube(w,h,d) -> id` / `load_model_mesh(verts, indices) -> id` (12 floats/vertex: pos3+color4+normal3+uv2; flat-shaded rebuild for edited meshes — MUST be uploaded, matches GenMeshCube) / `draw_model(id, x,y,z, scale, r,g,b,a)` / `draw_model_wires(...)` / `unload_model(id)`
- `lp.rl.debug_material(id) -> "TEXTURE_BOUND"|"TEXTURE_EMPTY", tex_id` — material diagnostic
- `lp.rl.set_mouse_cursor(cursor)` — hover affordance; `rl.CURSOR_*` constants (DEFAULT/HAND/CROSSHAIR/RESIZE_EW/NS/NWSE/NESW)
- `lp.rl.load_texture_perlin(w,h,scale) -> id` / `unload_texture(id)`
- `lp.rl.load_shader(vs_or_nil, fs) -> id` (nil vs = embedded default) / `unload_shader(id)`
- `lp.rl.set_material_texture(model_id, map, tex_id)` / `set_material_shader(model_id, shader_id)` / `set_material_color(model_id, map, r,g,b,a)`
- `lp.rl.get_shader_location(shader_id, name) -> loc` / `set_shader_value_vec3(shader_id, loc, x,y,z)` / `set_shader_value_float(...)`
- `lp.rl.is_mouse_button_down(btn)` / `is_mouse_button_pressed(btn)` / `get_mouse_delta()` / `get_mouse_wheel()` / `get_mouse_pos()`
- `lp.rl.is_key_pressed(key)` / `is_key_down(key)` — use `lp.rl.key.*` constants
- `lp.ig.*` — full ImGui surface with scoped wrappers (see `ig.cpp`)

## Lua API — 2D surface

### `lp.tex.*` — offscreen canvas (Image + Texture2D pairs)
| Function | Description |
|---|---|
| `lp.tex.create(w, h) -> id` | New canvas, cleared white (0xFFFFFFFF). CPU Image only; GPU upload is deferred to the first `upload()`. |
| `lp.tex.stamp(id, x, y, radius, hardness, r,g,b,a)` | Circular brush into the Image (hardness 0=hard edge … 1=softest linear falloff), clamped to bounds, alpha-blended. |
| `lp.tex.get_pixel(id, x, y) -> col32` | Pixel as `0xRRGGBBAA`. |
| `lp.tex.set_pixel(id, x, y, col32)` | Write one pixel. |
| `lp.tex.clear(id, col32)` | Fill the whole canvas. |
| `lp.tex.upload(id)` | Image → Texture2D (creates on first call, `UpdateTexture` after). |
| `lp.tex.export_png(id, path) -> bool` | Write the Image to PNG (mkdirs the parent dir). |
| `lp.tex.push_undo(id)` / `pop_undo(id) -> bool` | Undo stack of Image copies (cap 50). `push_undo` clears redo; `pop_undo` restores and pushes the old state onto redo. |
| `lp.tex.push_redo(id)` / `pop_redo(id) -> bool` | Symmetric redo stack (`pop_redo` restores and pushes old state onto undo). |
| `lp.tex.can_undo(id)` / `can_redo(id) -> bool` | Stack non-empty checks (for button disabling). |
| `lp.tex.apply_to_model(tex_id, model_id)` | **The 2D→3D bridge**: bind the canvas texture to a model's albedo map. |
| `lp.tex.texture_id(id) -> gl_id` | GL texture handle as integer (rlImGui `ImTextureID` convention, for `ig.dl_add_image` previews). |

### `lp.cam2d.*` — 2D viewport camera
| Function | Description |
|---|---|
| `lp.cam2d.set(pan_x, pan_y, zoom)` | Set pan (world point at screen center) + zoom. |
| `lp.cam2d.get() -> px, py, zoom` | Read back the camera. |

### `lp.rl.*` 2D additions (world-space, call inside `begin_mode2d`/`end_mode2d`)
| Function | Description |
|---|---|
| `lp.rl.begin_mode2d()` / `end_mode2d()` | Enter/leave the 2D camera transform. **Must be called outside `BeginMode3D`** (see Gotchas). |
| `lp.rl.draw_texture(tex_id, x, y, w, h)` | Draw a canvas scaled to (w,h) at (x,y). |
| `lp.rl.draw_line_2d(x1,y1,x2,y2, thick, r,g,b,a)` | `DrawLineEx` |
| `lp.rl.draw_circle_lines_2d(x,y,r, thick, r,g,b,a)` | Ring outline (`DrawRing`) |
| `lp.rl.draw_rect_2d(x,y,w,h, r,g,b,a)` | Filled rect |
| `lp.rl.draw_text_2d(text, x, y, size, r,g,b,a)` | World-space text (raylib default font) |
| `lp.rl.screen_to_world(mx,my) -> wx,wy` | Screen → canvas world coords (uses the current cam2d). |
| `lp.rl.world_to_screen(wx,wy) -> mx,my` | 2D world → screen; with **3 args** it dispatches to the 3D `GetWorldToScreen`. |

## Image import (drag&drop / paste / file picker — ONE pipeline)

Drag&drop, Ctrl+V paste, and the "Load Texture…" button all route through the
same `import_image(path)` flow in main.lua: load into the 512×512 canvas
(`lp.tex.load_image_from_file` — resizes + converts to RGBA8, invalidates the
GPU texture), upload, and apply to the active mesh (`doc.canvas_apply_to`) so
the image becomes the cube's texture. **Graceful rejection**: unsupported or
unreadable paths return false and only set a status message — the existing
canvas is untouched.

- Drag&drop: `lp.rl.is_file_dropped()` / `take_dropped_file()` (raylib 6.0's
  `LoadDroppedFiles`/`UnloadDroppedFiles` wrapper — takes the FIRST dropped
  path). Drop events are OS-level, so this needs interactive verification on
  the host; the import CORE is covered headlessly by `shot-import` and the
  `testmain.lua` round-trip/rejection tests.
- Paste: `lp.rl.clipboard_file_path()` — Windows reads CF_HDROP directly
  (`src/winclip.c`; files copied in Explorer paste cleanly, and GLFW's
  "Failed to convert clipboard to string" error never fires); Linux reads
  clipboard text + strips `file://`. Falls back to text only when a text
  format is actually present.
- File picker: the in-app `filebrowser.lua` modal is the RELIABLE picker
  everywhere — "Load Texture…" opens it. A secondary "System…" button tries
  `lp.app.open_file_dialog()` (vendored tinyfiledialogs; native on Windows,
  zenity/kdialog on Linux, nil when unavailable — under WSLg it's always nil).
  The browser is backed by `lp.file.list_dir`/`lp.file.exists`.

## Interaction doctrine (baked into main.lua — keep it)

- **2D canvas zoom**: wheel up = zoom IN (`1.15 ^ wheel` — raylib wheel is
  positive on scroll-up; the sign was a footgun, it is now correct and
  cursor-anchored).
- **3D brush reticle = true brush radius**: the paint radius and the on-screen
  reticle MUST match (a `radius * 0.15` reticle vs full-radius paint was a
  6.7× mismatch footgun). Brush `hardness` (0..1) controls the feathered rim;
  the 2D stamp and 3D vertex paint share one brush.
- **Texture bindings survive edits**: `mesh.tex_binding` ("perlin"/"canvas")
  is preserved across `invalidate_model` (which only drops the GPU model for
  flat-shaded live-drag preview). `doc.rebuild_model()` re-creates the model
  from current geometry (`geom.mesh_to_gl` → `lp.rl.load_model_mesh`) and
  re-applies the binding on commit/cancel/undo. Perlin no longer vanishes on
  first edit; canvas paint persists on the cube.
- **Panel resize (Godot-inspector style)**: the right sidebar is resizable via
  an ImGui splitter INSIDE the window's left edge (a 6px `invisible_button` in
  a child + `ig.same_line()` content column) — NOT a screen-space manual
  hit-test. A real widget gets proper hover/click capture: no click-through,
  no highlight bleed, cursor resets on leave. The drag LATCHES on mouse-down
  (`CF.resize_active`) so the cursor may leave the thin handle mid-drag.
  Scrollable by default (never set `NoScrollbar` on the content column).
- **Color widgets return flat values**: `ig.color_edit3/4` and
  `ig.color_picker3/4` return `(changed, r, g, b[, a])` — NUMBERS, not a
  table. Treating the second return as a table silently fails (pcall swallows
  it → the picker appears to snap back to the default).
- **File import doctrine**: drag&drop, Ctrl+V paste, and the file picker all
  route through ONE `import_image(path)` pipeline. The picker is the in-app
  `filebrowser.lua` modal (native dialogs need zenity/kdialog on Linux and can
  silently fail on Windows) — "Load Texture…" opens the browser; "System…"
  tries tinyfiledialogs. Unsupported/unreadable inputs are REJECTED with a
  status message and never touch the existing canvas.
- **Ground grid z-fighting**: never draw a reference grid coplanar with mesh
  geometry (raylib's `DrawGrid` sits at y=0, the cube's bottom face) — the
  edges flicker. Draw it slightly below (`GRID_Y = -0.02`) with manual lines.
- **Resize handling**: cheap per-frame state (camera aspect, cam2d offset,
  viewport rect) MUST read the live window size every frame; heavy work on
  resize MUST be debounced (~120 ms, `resize_settled()` helper). The main loop
  calls `PollInputEvents()` BEFORE rendering so resize/input events apply to
  the current frame (raylib also polls at EndDrawing). Evidence from raylib
  6.0 source: `FramebufferSizeCallback` updates `CORE.Window.render` +
  `currentFbo` + `SetupViewport` live; the 3D projection aspect comes from
  `currentFbo` — so in-app rendering IS size-live. Any remaining stretch
  during the drag is the platform drag loop blocking present (Windows GDI
  modal resize / compositor), not an app-side size lag — do NOT try to force
  the viewport (`rlViewport` overrides made it worse; reverted 2026-08-19).
- **Hover affordances**: every draggable region shows a cursor change
  (`lp.rl.set_mouse_cursor`) + a visual highlight. ALWAYS reset the cursor
  (`CURSOR_DEFAULT`) when the pointer leaves the region — a stuck resize
  cursor is a bug (the sidebar strip had exactly this).

## Gotchas
- **raylib 6.0 `BeginMode2D` no longer installs an ortho projection** — it only
  loads the camera transform into the current modelview. Drawn inside
  `BeginMode3D`, the perspective projection clips every 2D quad at z=0 (nothing
  renders). The 2D pass must run AFTER `EndMode3D` (the app does this via the
  `lp_draw2d()` hook in the main loop).
- **raylib 6.0 removed `DEFAULT_VERTEX_SHADER`/`DEFAULT_FRAGMENT_SHADER` externs** — the default VS is embedded in `main.cpp` as a string.
- **raylib 6.0 removed `SetMaterialColor`/`SetMaterialShader`** — set `Material.maps[..].color` / `Material.shader` fields directly (done in the bindings).
- **raylib 6.0 renamed `ImageClear` → `ImageClearBackground`** — used by `lp.tex.clear`.
- `TakeScreenshot` also writes an auto-numbered `screenshot000.png` — the `--shot` path unlinks the duplicate.
- GPU resource creation must be deferred to the first frame (`setup_scene()` in main.lua), NOT module load — `--test` boots the VM with no GL context. `lp.tex.create` is deliberately GL-free until `upload()` so the canvas can be created in `--test`.
- `lp.tex.export_png` mkdirs only the *parent* dirs — the final path component is the file (unlike `lp.file.mkdirs`, which takes a directory path).
- The em-dash/arrow glyphs may not exist in the raylib default font (`draw_text_2d`) — prefer ASCII there; ImGui text uses Inter/CJK and is fine.
- `CF = { cam = cam, cam2d = cam2d, doc = doc }` is a global handle for drive assertions (`CF.cam2d.pan`, `CF.doc.mode`, …).

## Key difference from 3d-viewport template
No painter's algorithm, no Lua-side Z-sorting. Raylib handles all 3D rendering
with proper hardware depth buffer. Lua only calls high-level draw primitives —
2D and 3D alike.
