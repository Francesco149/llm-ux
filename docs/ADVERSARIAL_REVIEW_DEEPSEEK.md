# Adversarial Review: Compiler, Graphics Backend & Systems Critique of LLM-UX

**Reviewer**: DeepSeek V4 Flash (adversarial compiler / graphics-backend / systems review)
**Date**: 2026-08-17
**Scope**: `/opt/src/llm-ux` — both templates (`2d-canvas`, `3d-viewport`), `tools/` (`scaffold.py`, `drive.lua`, `embed.py`), `docs/WINDOWS_COMPAT_AND_WIN7.md`, and the forensic dossier in `REVIEW_DOSSIER.md`.

---

## Verdict

The 2d-canvas template (`texturewrangler`) is a genuinely battle-tested codebase: vsync is wired, screenshots are format-corrected, crash handlers and a log tee exist, ASan targets are built into the Makefile, cross-session undo and golden-image tests are real. It deserves to be the reference implementation.

The 3d-viewport template (`lowpoly-painter`) is a regression that violates the framework's own core invariants — no vsync, a no-op autosave, no cross-session undo, no embedded fonts (the generated header is never included), no crash forensics, and two verified interaction bugs (modal-action undo is a no-op; `E` double-fires a fixed extrude *and* enters modal extrude). Any LLM scaffolded from it inherits every violation.

`tools/scaffold.py` produces repositories that **cannot build**: it writes five text files and empty directories, ignores its own `--template`/`--app-type` flags, and its generated flake exposes the Lua source tarball as `LUA_SRC_DIR` while the template Makefiles require an extracted source directory plus `SDL3_CROSS_*`/`MCFG_DLL`/`STB_INC` env vars it never sets.

`tools/drive.lua` is dead code that contradicts the doctrine (legacy scancodes) and swallows assertion failures. Neither template's `test_ui_smoke.lua` pumps a single ImGui frame, so the crash classes the dossier claims are gated (hover keycode assertion, mid-drag nil call, `Missing EndChild()`) are gated by **nothing** in this repository today.

The dossier's forensic table is honest about history; the repository does not yet contain the systematic prevention it describes. Details follow.

---

## 1. Windows 7 Cross-Compilation, D3D11 / SDL_Renderer Integration, Static Runtime Linking

### 1.1 GUI app linked as console subsystem (`-mconsole`) — packaging bug

Both Makefiles and the Windows-compat doc link with `-mconsole`:

- `templates/3d-viewport/editor/Makefile`: `WIN_LDFLAGS := -static-libgcc -static-libstdc++ -mconsole`
- `templates/2d-canvas/editor/Makefile:50`: same
- `docs/WINDOWS_COMPAT_AND_WIN7.md` §3: same

A console-subsystem PE launched from Explorer gets a console window on Windows 7/10/11. For a "polished standalone" creator tool this is a visible defect, and it forces ANSI `argv` encoding through the CRT (`main(int, char**)` under `-mconsole` uses the ANSI codepage — see 1.5). The correct subsystem for a GUI app is `-mwindows`; MinGW-w64's CRT still dispatches to `main()` when the entry is `WinMainCRTStartup`, so no code change is required — only the flag. This has shipped in three evaluation projects and nobody caught it, which tells you how little Windows-side validation actually happens (see 1.4).

### 1.2 `_WIN32_WINNT=0x0601` does not protect you from SDL3.dll

The doc's Win7 story rests on `-DWINVER=0x0601 -D_WIN32_WINNT=0x0601`, but those defines only constrain **your own** compiled code. The shipped binary is `mingwPkgs.sdl3` from `nixos-unstable` — a prebuilt DLL whose internal API usage (`CreateFile2`, `SetThreadDescription`, DXGI 1.2+, etc.) is governed by how *nixpkgs* built it, not by your `-D_WIN32_WINNT`. The `Entry Point Not Found` crash class the doc describes lives in that DLL, not in your headers. The claim "runs on Windows 7 SP1+" is **unverified by any CI**: every test and screenshot target builds and runs the *Linux* binary (`Makefile`: `shot: linux`, `test: linux`). The Windows PE is never executed anywhere in the pipeline. Fixes:

- Pin SDL3 to a specific rev+hash in the flake (as ImGui already is) and record the SDL version in the Makefile (`SDL_MAJOR/MINOR/MICRO` is already logged by the 2d app).
- Run the Windows PE in CI: `wine build/foo.exe --test` needs no window and exercises the real DLL chain (see 3.9).
- Verify on an actual Win7 SP1 VM at least once per SDL bump; a "Win7 checklist" doc is cheaper than a support fire.

### 1.3 D3D11 renderer + offscreen driver: the Windows `--shot` path is suspect and untested

`SDL_VIDEODRIVER=offscreen` is set before SDL init (`2d-canvas/editor/src/main.cpp:63-71`, `3d-viewport/editor/src/main.cpp:51-55`). The D3D11 renderer creates a swapchain against the window's native handle; offscreen-driver windows are handle-less. Whether `SDL_CreateRenderer` succeeds there depends on SDL3's internal fallbacks (and its version — see the dossier's own note that `SDL_RenderReadPixels` changed signature in 3.4.12). Because every `shot` target runs the Linux binary, the Windows screenshot path has **zero coverage**. If D3D11 fails on offscreen, the correct fix is to select the software renderer explicitly for Windows shots (`SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software")` or `SDL_PROP_RENDERER_CREATE_NAME_STRING`), not to ship a broken `--shot` on the primary target platform.

### 1.4 Static runtime linking: correct pattern, three divergences

`-static-libgcc -static-libstdc++ -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic` is the right modern MinGW-w64 pattern (mcfgthread provides `std::thread`/`std::mutex` without a runtime DLL). Issues:

1. **`-latomic` is present in 2d, absent in 3d** (`2d-canvas/editor/Makefile:57` vs 3d's `WIN_LIBS`). The 2d added it for a reason (mingw libstdc++ needs it for 64-bit atomics on x86 without `lock cmpxchg`-free paths); the 3d template is a latent link failure the moment anyone uses `std::atomic<long long>` or `std::shared_ptr` counters. Standardize.
2. The 2d Makefile comment claims `-Bstatic -lmcfgthread` means "the exe needs no libmcfgthread-2.dll on the target" — yet the `package` target still copies `libmcfgthread-2.dll`. Decide which claim is true; if mcfgthread is static, drop the DLL from the package (or keep it and fix the comment). Belt-and-suspenders here is harmless, but the contradiction is exactly the kind of stale assertion that misleads the next LLM.
3. The 3d `package` target copies `SDL3.dll` and `libmcfgthread-2.dll` but **no `lua/` runtime check and no `assets/`** — actually it does copy `editor/lua`, but not `assets/fonts` (which is fine because fonts are embedded — except in 3d they aren't, see 1.12). The 3d package omits nothing that exists; the issue is what doesn't exist.

### 1.5 Non-ASCII paths: `fopen`/`_mkdir`/ANSI `argv` break CJK and emoji paths on Windows

All file IO goes through `fopen` (`file_write_all`, `file_read_all`, `file_exists` in both `app.cpp` files) and `_mkdir`. On Windows these use the ANSI codepage (CP1252/CP932...), so `--project "C:\Users\山田\..."` or any emoji-containing path silently fails or writes mojibake. Combined with `-mconsole`'s ANSI argv (1.1), the standalone Windows build cannot open a project in a non-ASCII directory — a real user-visible defect on a platform where non-ASCII usernames are common (`C:\Users\Müller\...`). SDL3 already solves this: `SDL_IOFromFile()` takes UTF-8 and converts to UTF-16 internally on Windows, and `SDL_GetPrefPath`/`SDL_GetBasePath` return UTF-8. **Fix: replace `fopen` with `SDL_IOFromFile` in the file helper layer** — one place, both platforms, free Unicode support, no extra deps.

### 1.6 Memory: `g_dl` draw-list registry grows without bound in both templates

```cpp
static std::vector<ImDrawList*> g_dl;          // ig.cpp, both templates
static int push_dl(lua_State* L, ImDrawList* dl) {
  g_dl.push_back(dl);                          // ← never cleared anywhere
  ...
}
```

Grep confirms the only `g_dl` mutation sites are `push_back` in `push_dl` (e.g. `2d-canvas/editor/src/ig.cpp:457-462`). The comment says "registry cleared per frame" — it is not. `get_window_draw_list` + `get_foreground_draw_list` push ≥2 entries per frame; at 60 fps an hour-long session leaves ~432,000 entries (~3.5 MB) of dead pointers, and the leak compounds on every session. It is not a crash today because stale indices still resolve to the current draw lists (same pointers, monotonic indices) — it is a slow, guaranteed memory-growth bug plus a correctness trap: the moment anyone adds a per-frame draw list that is *recreated* (e.g. a render-texture draw list, which is the whole point of a handle registry), stale handles dereference freed ImGui state and `check_dl`'s bounds check passes because the index is in range.

**Fix**: `g_dl.clear()` at the start of `lua_frame()` (or right after `ImGui::NewFrame()`), plus an epoch: store `{ImDrawList*, uint32_t epoch}` and stamp handles with the epoch; `check_dl` fails on epoch mismatch. This is a 10-line change and it converts a latent UAF into a clean Lua error.

### 1.7 Screenshot pixel format: 3d writes raw surface, 2d converts — R/B swap risk

- 2d: `app_screenshot` explicitly converts (`SDL_ConvertSurface(surf, SDL_PIXELFORMAT_RGBA32)` — `2d-canvas/editor/src/app.cpp:174-177`) with a comment explaining the 3.4.12 signature change.
- 3d: `SDL_RenderReadPixels(g_renderer, nullptr)` is handed straight to `stbi_write_png(..., 4, surf->pixels, surf->pitch)` (`3d-viewport/editor/src/app.cpp`). D3D11's native surface format is typically `SDL_PIXELFORMAT_ARGB8888`; stbi interprets bytes as RGBA → **R and B swapped in every Windows screenshot** (and on any renderer whose native format isn't RGBA32). The two templates must share one implementation; the 2d version is correct.

### 1.8 `path_join`/`path_dirname` static-buffer aliasing — UB under composition

Both `app.cpp` files return `static char buf[2048]` from `path_dirname`/`path_join`/`path_basename`. Nested calls like `path_join(path_join(exe, ".."), "editor/lua")` perform `snprintf` with overlapping source/destination — undefined behavior that happens to work on glibc/mingw. The 2d `find_lua_dir` carries a comment ("snapshot into dir BEFORE path_join may clobber the ring slot c") — i.e. the codebase *knows* and works around it; the 3d `find_lua_dir` relies on the same aliasing silently (`3d-viewport/editor/src/main.cpp`). Any future caller that stores a returned pointer (e.g. in a struct, a Lua-pushed string, a second thread) gets silently clobbered. The Opus review says the same thing; the fix is identical and cheap: return `std::string` (this is C++17, and the callers already copy into `snprintf` buffers). The "zero-allocation" argument is moot — the Lua side allocates freely on every call anyway.

### 1.9 ABI hazards in the Lua↔C texture surface

`l_tex_alloc` returns a lightuserdata with no metatable (`3d-viewport/editor/src/lua.cpp`). Consequences:

- `l_tex_free` accepts any lightuserdata (or `lua_touserdata` of a full userdata, or nil → null deref in `tex_free`) with no validation; a double `tex_free` on the same `Image*` is a heap double-free crash.
- No ownership protocol: if Lua GC's the only reference, nothing happens (lightuserdata has no `__gc`) — which is *why* it doesn't crash today, but it also means the C++ side can never know when an image is dead.

Fix: register an `Image` metatable with a `__gc`-safe design — either full userdata with `__gc` calling `tex_free` exactly once, or keep lightuserdata but validate with a registry of live pointers. The 2d template's `tw.tex` binding should be checked for the same pattern and both standardized.

### 1.10 `long sz` file size on LLP64 — 2 GB ceiling

`file_read_all` uses `fseek/ftell` → `long`, which is **32-bit on Windows x64** (LLP64). Files ≥2 GB read as errors. Irrelevant for `project.json` today, but the helper is the shared primitive; `SDL_IOFromFile` + `SDL_GetFileSize` fixes it and 1.5 in one move.

### 1.11 Crash forensics absent in 3d

The 2d app installs `SIGSEGV`/`SIGABRT` handlers, a Win32 `SetUnhandledExceptionFilter`, a vectored exception handler, and tees `app_log` into `texturewrangler-debug.log` next to the exe (`2d-canvas/editor/src/app.cpp:400-416`). The 3d template has none of it. For a framework whose selling point is "never crash," the 3d's failure mode is: crash → nothing to attach to → another blind LLM debugging session. Also, the 2d's log tee comment documents a *real* double-free trap (SDL-owned `e.drop.data` must not be freed) — that comment is the kind of hard-won knowledge the 3d template is missing entirely.

### 1.12 3d runs on the default ProggyClean font — "embedded vector fonts" is false there

`fonts_embedded.h` is generated (`3d-viewport/editor/Makefile:10`, `embed.py` rule) and **never included by any translation unit**. Grep for `fonts_embedded|AddFontFromMemory|AddFont` across `templates/3d-viewport/` matches only the Makefile and `tools/embed.py`. The 3d `app.cpp` never touches `io.Fonts`. Result: the app renders ImGui's built-in 13px ProggyClean bitmap font — no Inter, no JetBrains Mono, no dynamic atlas — directly contradicting ORIENTATION invariant #3 and the "embedded vector fonts" README claim. (In the 3d `ig.cpp`, `l_push_font` indexes `io.Fonts->Fonts[i]`, which has size 0 → it silently no-ops, so `theme`/`ui` font pushes do nothing.) The 2d does this correctly (`2d-canvas/editor/src/app.cpp`: `AddFontFromMemoryTTF` with `FontDataOwnedByAtlas = false`).

### 1.13 3d writes `imgui.ini` into CWD

`io.IniFilename` is set to `nullptr` in 2d (`app.cpp:426`) and left default in 3d. A packaged 3d app in a read-only folder (Program Files) silently fails to write `imgui.ini` or, worse, writes it into the user's CWD, and its window layout state is meaningless anyway because the layout is Lua-owned. Disable it in both.

### 1.14 Atomicity of saves — the "zero data loss" invariant is not met by either template

`doc.save()` writes `project.json` **in place** via `tw.file.write_text` (`2d-canvas/editor/lua/doc.lua:328-345`): open, write, close. A crash or power loss mid-write truncates/corrupts the only project file — exactly the data-loss scenario ORIENTATION claims to prevent ("zero data loss," "backup rotation (`backup.1.json`, `backup.2.json`)"). Neither template implements temp-file + atomic rename, and **neither implements any backup rotation at all** — the `backup.*` claims exist only in docs and in `.gitignore`. The 3d autosave is worse: it doesn't even write (`autosave.tick()` only clears `doc.dirty` — see 2.2).

Fix: `write_text` → write `project.json.tmp`, `rename` over target (atomic on both NTFS and POSIX), keep `backup.1/2` rotation. That is ~15 lines in `doc.save` and it makes the invariant real instead of aspirational.

---

## 2. Lua-to-C++ Binding Overhead & 60 FPS Frame Pacing

### 2.1 The 3d template has no frame pacing at all

The 3d main loop (`3d-viewport/editor/src/app.cpp`) is poll → NewFrame → lua_frame → Render → Present with **no `SDL_SetRenderVSync` call**. The 2d loop calls `SDL_SetRenderVSync(g_renderer, 1)` explicitly with the comment "was running at ~3000 fps" and correctly skips it under `TW_SHOT` (`2d-canvas/editor/src/app.cpp:427-431`). So:

- The 3d app burns 100% of a CPU core and renders uncapped (tearing, GPU fan noise, laptop battery drain). "60 FPS locked" is a doctrine in the docs and a lie in the 3d template.
- The dossier's own fix history (vsync was the resolution of the WGL fiasco) makes this regression embarrassing: the definitive 3d template simply omits the fix.

Standardize on the 2d pattern, including the `TW_SHOT`-style env skip (the 3d `--shot` path would otherwise vsync-block the offscreen driver — or, more likely, fail to create a renderer as in 1.3).

### 2.2 Debounce is frame-counted where it must be wall-clock — and the 3d autosave is a stub

2d autosave uses `DEBOUNCE_FRAMES = 24 -- ~0.4s at 60fps` (`2d-canvas/editor/lua/autosave.lua:7-9`). Under vsync at 60 Hz that's 0.4 s — but the whole point of the framework is that it must also run on 240 Hz displays and uncapped offscreen modes, where 24 frames is 0.1 s or 4 s. The 3d template *tried* wall-clock (`os.clock()`) but the function is a stub:

```lua
function autosave.tick()
    if doc.dirty and (os.clock() - doc.dirty_time) >= 0.300 then
        doc.dirty = false          -- ← nothing is written. Ever.
    end
end
```

`3d-viewport/editor/lua/autosave.lua` clears the dirty flag and returns. No `doc.save`, no file write, no backup. Combined with 3d's `undo.lua` (in-memory `max_depth=100`, **no `undo.jsonl` journal** — the 2d has the real journal, `2d-canvas/editor/lua/undo.lua:26-32, 80-88`), the 3d template delivers **zero** of the persistence invariants: no cross-session undo, no autosave, no atomic save, no backup rotation. The framework's flagship 3d template is data-loss-prone by construction.

Fix: wall-clock debounce everywhere (`SDL_GetTicks()`-based via a binding, or `os.clock()`), and make autosave call the same atomic `doc.save()` path as manual save.

### 2.3 Binding hot path: matrix marshaling dominates, not the draw calls

The measurable cost is not `dl_add_line` (a handful of `luaL_checknumber`s) — it is **matrix round-tripping**:

- `lp.math3d.project(wx, wy, wz, view, proj, w, h)` calls `table_to_mat4` **twice per call**, each doing 16× (`lua_rawgeti` + `lua_tonumber`) — 32 table reads + 32 number conversions per projected point (`3d-viewport/editor/src/lua.cpp`, `l_math3d_project` + `table_to_mat4`).
- The 3d viewport calls `world_to_screen` per grid line (34 lines) and per mesh vertex per face (3–4 per face) — ~100+ `project` calls per frame → ~3,200 `rawgeti`/`tonumber` pairs and ~100 table allocations *per frame*, on the Lua↔C boundary, before a single pixel is drawn.

Three concrete fixes, in order of payoff:

1. **Precompute the combined view-projection matrix once per frame in C++** and hand Lua a single immutable handle (lightuserdata into a per-frame `Mat4`); add `lp.math3d.project_vp(x,y,z, vp, w, h)` that reads the matrix from C memory. Kills the 32-read marshaling entirely.
2. **Batch projection**: `lp.math3d.project_points(pts, vp, w, h)` → returns one table of `{x,y,z}`. Grid + mesh faces become 1–2 calls per frame instead of ~100.
3. **Cache `ig.get_io()` per frame**: `l_get_io` builds a fresh 14-field table on every call (`ig.cpp`), and `main.lua`/`panels.lua`/`preview.lua` call it 3–4× per frame. Return the same table for the duration of the frame (invalidate after `NewFrame`), or expose a `lp.frame_io()` C binding that fills a preallocated table. Minor, but free.

The grid renderer should also be revisited: 34 `world_to_screen` calls just to draw 34 lines is the textbook case for batching (2). At the current mesh sizes none of this drops below 60 fps — but the framework's entire premise is that cheap models will build *larger* scenes on this template, and the marshaling cost is O(vertices) per frame while everything else is O(1).

### 2.4 Do not reach for LuaJIT

The obvious "optimization" (LuaJIT) is the wrong call and should be stated in the skill files to prevent an LLM from "helpfully" swapping it in: LuaJIT is frozen at 5.1 semantics (no 5.4 `goto`/integer division semantics without compatibility shims, no 5.4 generational GC), x64 LuaJIT lacks the ARM64 backend, and mixing JIT-compiled code with 900 lines of hand-rolled `luaL_*` bindings invites FFI/GC traps. Stock Lua 5.4 with the batch/marshal fixes above is the boring, correct choice — and "boring" is the standard this framework sets for itself.

### 2.5 Frame-pacing correctness: clamp `io.DeltaTime`

`ImGui_ImplSDL3` computes `io.DeltaTime` from `SDL_GetTicks()` with no clamp. After a window drag-resize, alt-tab, debugger breakpoint, or a long GC pause, the next frame's `dt` can be 1–5 s. The exponential camera lerp (`1 - exp(-dt*22)`, `3d-viewport/editor/lua/preview.lua`) converges instantly at large `dt` (fine for the camera), but anything integrating velocity or physics over raw `dt` will teleport, and frame-based debounce (2.2) misbehaves. The standard fix is `io.DeltaTime = min(io.DeltaTime, 0.05f)` after `NewFrame` (or a `SDL_GetTicks`-based cap in the backend init). Add it to both templates and document it in the skill.

### 2.6 Frame pacing must be measured, not asserted

"60 FPS locked" is currently an unmeasured claim: no frame-time counter, no `--perf` mode (2d has `perf.lua` — wire it into the smoke gate). Concrete gate: in `--test-ui` (proposed in 3.5), pump 300 frames, record per-frame `io.DeltaTime`, and fail on p95 > 33 ms or any frame > 100 ms. That converts the doctrine into a CI assertion and catches regressions like the 3d-vsync omission (which a frame-time test would flag instantly: ~3000 fps means something is wrong, and a wall-clock check catches the no-vsync case).

### 2.7 Lua error path: no traceback, silent blank-window failure

`lua_frame()` uses `lua_pcall(L, 0, 0, 0)` with **no error handler** (`3d-viewport/editor/src/lua.cpp`), so a runtime error prints a one-line message with no stack trace — for a cheap-model-driven codebase, the traceback is the difference between a one-shot fix and a debugging spiral. Fix: `lua_getglobal(L, "debug"); lua_getfield(L, -1, "traceback")` as the error handler, and route through `app_log` (and the log tee in 2d).

Worse: `luaL_dofile(main.lua)` failure is **logged but not fatal** — the app then runs a blank window with exit code 0 (`lua_init`, 3d). A UI-less launch that reports success is the exact silent-failure class this framework claims to eliminate. Exit 1 on init failure, and make `--test` failures exit non-zero (they do, via `luaL_dofile` → `exit(1)` — but note `exit()` inside `lua_init` also makes the code after it in `main.cpp`'s `--test` path (`lua_shutdown(); ImGui::DestroyContext();`) dead code; move the exit to `main`).

---

## 3. Scaffolding Tool & Test Drivers

### 3.1 `scaffold.py` generates repositories that cannot build

`tools/scaffold.py` `main()` writes exactly five files — `flake.nix`, `ORIENTATION.md`, `README.md`, `LICENSE`, `.gitignore` — and creates empty directories (`editor/src`, `editor/lua`, `editor/tests`, …). It writes **no Makefile, no `main.cpp`/`app.cpp`/`ig.cpp`/`lua.cpp`, no Lua modules, no `embed.py`, no fonts, no tests**. The skill file claims it produces "a complete repository with Nix flake, Makefile (Linux + Windows cross), ImGui 1.92+, embedded fonts, Lua 5.4 or C++ core, headless testing (--shot, --test, --eval)". What it produces:

- No build rules at all (`make -C editor` fails: no Makefile).
- A flake whose `luaSrc` is `pkgs.fetchurl` of the **tarball**, exported as `LUA_SRC_DIR` — while every template Makefile requires `$(LUA)/src/*.c` (an extracted tree). The scaffold's own generated environment cannot compile Lua.
- No `SDL3_CROSS_INC` / `SDL3_CROSS_LIB` / `SDL3_CROSS_DLL` / `MCFG_DLL` / `STB_INC` / `MINGW_CC` / `MINGW_CXX` exports — every one of which the template Makefiles hard-depend on (`3d-viewport/editor/Makefile` uses all of them).
- `--template cpp` and `--app-type 3d` are parsed and **completely ignored**; output is identical for all four combinations.

This is the single highest-leverage fix in the repository, and it is trivial: **make `scaffold.py` copy the battle-tested template tree** (`shutil.copytree(templates/2d-canvas or 3d-viewport)`) and token-substitute `{name}`/`{desc}`. Delete the parallel `FLAKE_NIX_TEMPLATE`/`ORIENTATION_MD_TEMPLATE` string blocks — they are drift generators. A generated repo should be byte-identical to the reference template modulo the name, so that "scaffolded" inherits "tested."

### 3.2 `drive.lua` is dead code that contradicts the doctrine

- **No consumer**: no template test `require("drive")` (grep: zero matches), and there is no C++ event-injection binding (`lp.input` does not exist anywhere) that `D.step(events)` could feed. The tape driver cannot drive anything.
- **It uses legacy scancodes** — `Key = { Ctrl = 224, Space = 44, V = 25, ... }` — the exact integer-keycode class the skill files forbid ("NEVER pass legacy numeric integers … `Assertion failed: IsNamedKey(key)`"). If anyone ever wires this up, it will reproduce the very crash the dossier documents, and it trains models to write scancode code.
- **`D.rclick` maps to button 3** (`D.click(f, x, y, 3)`), which is neither ImGui's right button (1) nor SDL's `SDL_BUTTON_RIGHT` (3 → SDL_BUTTON(3) is right in *SDL* numbering, but the consumer would have to translate; ImGui's convention is 0=left,1=right,2=middle). The two conventions are conflated in one constant.
- **`D.step` swallows failures**: planned `assert`s are wrapped in `pcall`; on error it prints `[drive] ERROR on frame N` and **continues** — the run exits 0. A smoke gate built on drive.lua *cannot fail*, which is the one property a gate must have.

If the tape driver is to exist, it needs: (a) a C++ `--test-ui` harness that owns the event loop and injects SDL3 events (`SDL_SendMouseMotion`, `SDL_SendMouseButton`, `SDL_SendKeyboardKey`, `SDL_SendMouseWheel` are public SDL3 APIs — no custom plumbing needed), (b) named ImGuiKey constants, and (c) fail-fast semantics. Otherwise delete it — dead doctrine-contradicting code is worse than no code.

### 3.3 Neither smoke test pumps a frame — the crash gates are fiction

Both `test_ui_smoke.lua` files run under `--test`, where the app **never calls `NewFrame`/`Render`** (`main.cpp` dispatches `--test` to `lua_init` and exits). They call `ig.reset_mouse_drag_delta(0)` and `ig.key.Z > 500` against a context with no frame in flight. Consequently, the three crash classes the dossier says the smoke gate catches:

1. `Assertion failed: IsNamedKey(key)` on hover,
2. `attempt to call nil value 'reset_mouse_drag_delta'` mid-drag,
3. `Missing EndChild()` after a Lua error aborts a frame,

…are **exercised by no test in this repository**. The 3d smoke test doesn't even touch hover/keys/drags; the 2d one touches `preview.state` and two key constants. The `IsNamedKey` guard that the dossier's fix table calls for ("Add a Lua binding runtime check in ig.cpp that asserts or translates integer keys") was **not implemented** — `l_is_key_pressed` still blindly casts `luaL_checkinteger` to `ImGuiKey` (`ig.cpp`). The only reason the assertion can't fire is that the smoke tests never hover over a viewport.

What must exist to make the dossier's claims true:

- **`--test-ui` mode in C++**: create window + renderer (offscreen on CI), pump N frames, inject a scripted sequence of SDL events (hover over the viewport, press `E`, drag, right-click cancel, `Ctrl+Z`), and fail on: any Lua error escaping a panel, any ImGui assertion (enabled via `IMGUI_DEBUG`/debug build), or a frame that throws `Missing EndChild`-style imbalance.
- **ImGui stack balance check**: after each frame, assert the debug `ImGui::GetCurrentWindow()` / debug-log stack depth is back to baseline; after a forced panel error (inject a `error()` into a panel), assert the app survives the *next* frame — the "pcall balance recovery" the dossier claims but which no code path provides (the 3d's single `lua_frame` pcall does not rebalance `Begin`/`EndChild`/`PushStyle`; an error inside `panels.render()` leaves ImGui's stack open and the following frame hits the assert).
- **Binding-parity test (10 lines, catches the `reset_mouse_drag_delta` class for *all* bindings)**: a Lua test that iterates a manifest of required `ig.*`/`lp.*` functions and `assert`s each is callable — plus the C++-side X-macro/registration unification the Opus review proposes, which makes the two lists structurally identical instead of manually synchronized.

### 3.4 Fabricated test counts

`3d-viewport/editor/tests/testmain.lua` prints `"38 Low-Poly, Paint & UI Smoke assertions passed"` and the smoke test prints `"UI smoke test gate passed with 0 assertions!"` — both **hardcoded strings**, not counts. The 2d uses a real `testlib` counter. A test suite whose success message is a constant cannot fail on regressions (beyond the `assert`s themselves — which is fine, but the numbers are misinformation and a model reading them will report "38 assertions passed" to the user). Delete the fake counts; print real ones from a shared `testlib`.

### 3.5 Golden tests: extend the 2d pattern to 3d

The 2d has a real determinism gate: `make_golden.lua` + `test_golden.lua` comparing a rendered `composite.png` byte-for-byte, run inside `make test` (`2d-canvas/editor/Makefile:216-220`, `testmain.lua` suite list). The 3d template has nothing analogous — no golden mesh bake, no screenshot hash. Since the framework's determinism claim ("identical byte outputs across Linux and Windows") is a core selling point, add: (a) a 3d golden (mesh after scripted extrude/move/undo → serialized bytes), and (b) wire `--shot` output into a pixel-hash comparison (hash, not file, to keep the tree clean). Also worth a C++-level check: the same golden must be byte-identical between the Linux and MinGW builds — that is the actual cross-platform determinism test, and it currently runs nowhere.

### 3.6 CI: the skill claims a nightly workflow; the templates have none

`scaffold-native-app/SKILL.md` specifies `.github/workflows/nightly.yml` (Windows PE + Linux artifacts). Neither template contains a `.github/` directory. Given 1.2–1.4, the minimum viable CI is:

1. Linux build + `make test` (exists locally, not in CI).
2. Windows cross-build (`make win`).
3. **Execute the Windows PE**: `wine build/foo.exe --test` (headless; needs no display) — this is the only way the "runs on Windows" claim gets any evidence today.
4. `make shot` + golden hash.

### 3.7 Claims vs. implementation inventory (docs/skills vs. repo)

| Claim (docs / skill / dossier) | Reality |
|---|---|
| `--eval` headless state verification | Unimplemented in both `main.cpp` (`--test`, `--shot` only) |
| `--lua` script mode | Only 2d, implemented ad hoc inside `main.lua` (`arg_value("--lua")`); 3d lacks it |
| 300 ms autosave + `backup.1/2` rotation | 2d: debounced save, no rotation, non-atomic write; 3d: no-op |
| Cross-session undo (`undo.jsonl`) | 2d: real; 3d: absent |
| Embedded Inter/JetBrains Mono fonts | 2d: real; 3d: header generated, never included |
| 60 FPS locked / vsync | 2d: real; 3d: absent |
| Interactive smoke gate pumping hover/drag/keys | Neither template (no frame pumping, no event injection) |
| `test_ui_smoke.lua` fails `make test` on crash | No crash class is reachable in `--test` mode |
| scaffold "complete repository with Makefile, tests" | Five text files + empty dirs; unbuildable |

Every row of this table is a place where a cheap model reading the docs will confidently assert behavior the code does not have. **The single most important systemic fix is to make the 3d template match the 2d template's proven implementations (vsync, atomic save, journal, fonts, screenshot conversion), then make `scaffold.py` copy the templates, then make the smoke gate actually pump frames.** The dossier's "How to Prevent Systematically" column is a wishlist; the repo contains almost none of it.

---

## 4. 3d Template Specific Bugs Found (verified by code trace)

These are in the shipping template, not hypotheticals:

1. **Modal-action undo is a no-op.** `preview.lua` captures `doc.action_orig = doc.snapshot()` at action start, but on commit calls `undo.push(...)`, which snapshots the **current (post-action)** state. `do_undo` then restores that same state — `Ctrl+Z` after an extrude/move does nothing. The undo stack entry must be the *pre-action* snapshot (`doc.action_orig`). The 2d's `undo.ptr` rollback marker exists precisely to solve this; the 3d has the bug the 2d's design already prevents.
2. **`E` double-fires.** `main.lua` reacts to every `E` press with `doc.mutate(function() mesh.extrude_face(doc.mesh, doc.selected_face, 1.0) end, "Extrude")` — a fixed 1.0 discrete extrude — and `preview.lua` reacts to the *same press* by entering modal extrude. One keypress = fixed extrude + modal session. `E` during an active modal also re-fires the discrete extrude (no `doc.action` guard in `main.lua`). The discrete shortcut and the modal trigger must be mutually exclusive.
3. **`g_dl` unbounded growth** (1.6) — both templates.
4. **Autosave stub + no journal** (2.2) — 3d only.
5. **No font embedding** (1.12) — 3d only.
6. **Undo snapshot cost**: `doc.snapshot()` deep-copies the entire mesh on every action start/commit and every undo/redo. Fine at low-poly counts; it is an O(mesh) full-copy per gesture that will not survive 100k-vertex scenes. The 2d's journal stores serialized *params + strokes* ("pixels live in assets/") — the 3d has no equivalent design.

---

## 5. Prioritized Action List

**P0 (correctness/data loss, before any further LLM evaluation):**
1. Fix modal undo (push `action_orig`, or use the 2d `ptr` rollback pattern). [4.1]
2. Fix `E` double-fire (guard `main.lua` with `doc.action` / move discrete extrude into the modal path). [4.2]
3. Implement real autosave + atomic `doc.save()` (temp+rename) in 3d; add backup rotation to both. [2.2, 1.14]
4. `g_dl.clear()` + epoch check. [1.6]
5. Add `SDL_SetRenderVSync` + `DeltaTime` clamp to 3d. [2.1, 2.5]

**P1 (Windows delivery):**
6. `-mwindows` instead of `-mconsole`. [1.1]
7. UTF-8 file IO via `SDL_IOFromFile`; kills the ANSI-path defect and the 2 GB ceiling. [1.5, 1.10]
8. `SDL_ConvertSurface(RGBA32)` in the 3d screenshot path; share one implementation. [1.7]
9. Verify (or fix) the Windows offscreen `--shot` path; run the PE under Wine in CI. [1.3, 3.6]
10. Embed the fonts in 3d (include `fonts_embedded.h`, `AddFontFromMemoryTTF`, `io.IniFilename = nullptr`). [1.12, 1.13]
11. Add `-latomic` to the 3d link line. [1.4]

**P2 (framework plumbing):**
12. Make `scaffold.py` copy the templates; delete the stale string templates; honor or remove `--template`/`--app-type`. [3.1]
13. Real `--test-ui` frame-pumping gate with SDL3 `SDL_Send*` event injection + ImGui balance check; rewire or delete `drive.lua`. [3.2, 3.3]
14. Binding-parity reflection test + X-macro registration. [3.3]
15. `debug.traceback` error handler in `lua_frame`; exit(1) on `main.lua` load failure; remove `exit()` from `lua_init`. [2.7]
16. Wall-clock debounce; real assertion counters; 3d golden test; CI workflow. [2.2, 3.4, 3.5, 3.6]

The order matters: P0 fixes are bugs in the shipped template; P1 fixes the platform story the dossier is built around; P2 fixes the tooling that will otherwise keep regenerating the first two tiers of problems. Until P0-2 are in, a scaffolded project is a fresh instance of every bug this dossier was written to prevent.
