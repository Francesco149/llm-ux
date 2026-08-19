# Windows OpenGL Resize — the Complete Picture

> Definitive writeup of the "contents stretch during resize" problem on
> Windows, why naive fixes crash, and the exact solution shipped in this
> template. Read this BEFORE touching `render_frame_contents()`,
> `present_no_poll()`, `cf_resize_subclass_proc()`, or the main loop in
> `templates/raylib/editor/src/main.cpp`.

---

## 1. The problem (why OGL "stretched" but Linux was fine)

During an interactive drag-resize on Windows, `DefWindowProc` for
`WM_SYSCOMMAND`/`SC_SIZE` enters a **modal loop on the GUI thread** that does
not return until the user releases the mouse. Your main loop is stuck inside
`glfwPollEvents()` — it renders *nothing* while the user drags. DWM only has
the last presented backbuffer, so it **scales the stale frame** to the new
window size. When the drag ends, the modal loop exits, one frame renders at
the new size, everything "settles correctly". That's the entire symptom.

Linux doesn't have this because X11/Wayland resize is event-driven, not modal:
the loop keeps running and re-rendering at every size during the drag.

**Corollary:** this is not an OpenGL or WGL limitation. The GL context resizes
fine. The only problem is that no Present happens inside the modal loop.

## 2. Why previous attempts crashed (do NOT repeat these)

The fix must render from *inside* the modal loop, i.e. from a window
procedure. Three ways to crash doing that:

1. **Calling `EndDrawing()` from the wndproc.** `EndDrawing()` calls
   `PollInputEvents()` → `glfwPollEvents()`. A nested poll executed from
   inside window-proc context (which is itself inside the *outer*
   `glfwPollEvents`) corrupts GLFW's event queue and raylib's
   current/previous input-state rotation: dropped clicks, stuck buttons,
   spurious crashes. **Never call EndDrawing re-entrantly.**
2. **Rendering before the original wndproc ran.** GLFW's `WM_SIZE` handling
   updates `CORE.Window` sizes (and the GL viewport on the next
   `BeginDrawing`). If you re-render before calling the original proc, you
   render at the stale size. **Always `CallWindowProc(g_orig_proc, ...)`
   FIRST, render after.**
3. **No re-entrancy latch.** Any `SendMessage` the DWM/shell sends during
   your wndproc render can re-enter the proc with another `WM_SIZE`. A simple
   `bool` latch (single-threaded, same thread) suffices.

A decoupled render thread doesn't help and adds a second GL-context
minefield: the modal loop still owns the GUI thread, and sharing a GLFW/GL
context cross-thread requires careful locking for zero gain.

## 3. The shipped solution (`main.cpp`)

**Subclass, don't hook.** After `InitWindow()`:

```c
g_orig_proc = (CfWndProc)GetWindowLongPtrW(hwnd, GWLP_WNDPROC);
SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)cf_resize_subclass_proc);
```

In the subclass proc (`cf_resize_subclass_proc`):

- Track `WM_ENTERSIZEMOVE` / `WM_EXITSIZEMOVE` (only render from the subclass
  during the modal loop — regular `WM_SIZE` events are handled by the main
  loop's next frame anyway).
- `CallWindowProcW` the original GLFW proc **first**.
- On `WM_SIZE` (not minimized, in sizemove, latch free, not headless):
  `render_frame_contents(); present_no_poll();`

`present_no_poll()` is the key primitive:

```c
rlDrawRenderBatchActive();      // flush raylib's batch
SwapBuffers(wglGetCurrentDC()); // present, NO event polling
```

`render_frame_contents()` contains the whole draw pass (3D pass, 2D pass,
ImGui frame via `rlImGuiBeginDelta` + `lua_frame()` + `rlImGuiEnd()`) and is
shared verbatim with the main loop — the resize render *is* a normal frame.

**Why manual Win32 imports instead of `#include <windows.h>`:** raylib.h and
wingdi/winuser collide (`Rectangle`, `CloseWindow`, `ShowCursor`, `DrawText`
macros/functions). The template declares the handful of needed imports
(`wglGetCurrentDC`, `SwapBuffers`, `Get/SetWindowLongPtrW`,
`CallWindowProcW`) directly under `extern "C"`.

## 4. The dt trap (the subtle one that bit us TWICE)

raylib only recomputes `CORE.Time.frame` **inside `EndDrawing()`**
(`rcore.c`, EndDrawing body). `GetFrameTime()` just returns it. If you skip
`EndDrawing()` in your main loop (as this template does on Windows so the
subclass owns presentation), `GetFrameTime()` **freezes at its last value**.

Symptom fingerprint (memorize this): every **dt-scaled** interaction dies —
inertial camera smoothing `1 - exp(-dt*22)`, wheel dolly, RMB-fly — while
**raw-delta** interactions (2D pan, painting, clicking) keep working. It
looks like an input bug ("MMB hold broken") but it is a time bug.

Fix shipped: `update_own_dt()` — monotonic `GetTime()` delta, clamped to
0.25s against stalls, feeding:
- `rl.get_frame_time` Lua binding (returns `g_own_dt`, NOT `GetFrameTime()`),
- `rlImGuiBeginDelta(g_own_dt)` (never bare `rlImGuiBegin()` — that uses
  `GetFrameTime()` too).

**Rule for anyone extending this template:** never reintroduce
`GetFrameTime()` for gameplay/UI math on Windows; use `rl.get_frame_time()`.
If you must call raylib functions that internally use `GetFrameTime()`
(e.g. `rlImGuiBegin`), use their delta-taking variant.

## 5. Main-loop contract (the one-poll rule)

```c
render_frame_contents();
#ifdef _WIN32
present_no_poll();
PollInputEvents();      // the ONE poll per frame
#else
EndDrawing();           // flush+swap+time+the one poll (Linux unchanged)
#endif
```

Exactly **one** `PollInputEvents` per frame, everywhere. Two polls per frame
rotate raylib's previous/current input state twice and drop clicks pressed in
between (the old "intermittent unresponsiveness" bug documented in the old
loop comment). The subclass render path never polls — that's what makes it
safe.

## 6. Frame-time accounting detail

The subclass renders count as "extra" frames — `g_own_dt` is updated at the
top of every `render_frame_contents()` including subclass-driven ones, so
during a drag the dt reflects the *subclass* frame cadence (which is
WM_SIZE-driven, i.e. as fast as the drag). This is correct: after
`WM_EXITSIZEMOVE` the main loop resumes and dt is measured from the last
subclass render. No time is "lost" across the modal loop.

## 7. Lua/ImGui during subclass render

- `rlImGuiBeginDelta` → `ImGui_ImplRaylib_ProcessEvents()` only READS raylib
  input state; it never polls. Safe from wndproc. It may consume key edges
  mid-drag — harmless while the user is dragging the caption.
- Lua runs on the same (main) thread from both paths — no threading snags by
  construction; verified with coroutines + GC under high-frequency subclass
  renders (`poc_resize/poc_lua.cpp`). Do NOT move Lua or rendering to another
  thread.

## 8. Verification recipe (reuse, don't reinvent)

- PoCs: `templates/raylib/poc_resize/` (`poc_min`, `poc_imgui`, `poc_lua`) —
  each renders live size text + edge-flush border + corner diagonals so
  stretching is unambiguous in a screenshot.
- Host driving from WSL: exe runs via WSLInterop (`powershell.exe`); simulate
  the modal loop with `WM_ENTERSIZEMOVE` → `SetWindowPos` → screenshot →
  `WM_EXITSIZEMOVE` (see `poc_resize_test.ps1` pattern in this session).
  Grabbing the window needs the ALT-key trick to defeat the foreground lock.
- Always ALSO confirm hold-inputs (MMB/RMB/wheel) after touching the loop —
  the dt trap (§4) produces no crash, just dead camera.

## 9. History / related

- D3D11 backend existed solely to get smooth resize; with this fix OGL 3.3
  ships everywhere and D3D11 is completely removed.
- For the record, the Win7 D3D11 `0x80070057` was
  `D3D_FEATURE_LEVEL_11_1` in the feature-level array on a box without
  KB2670838 (the whole call fails E_INVALIDARG, fallback included, because
  the same array was reused).
