# Windows 7+ Standalone Compatibility & Zero-Footgun Toolchains

> **"A standalone tool must execute out of the box without requiring users to install VC++ redists, DirectX runtimes, or modern OS upgrades."**

---

## 1. Targeting Windows 7 Cleanly (`_WIN32_WINNT = 0x0601`)

Windows 8, 10, and 11 introduced APIs (such as `CreateFile2`, `SetThreadDescription`, and modern D3D12/D3D11.1 features) that trigger `Entry Point Not Found` crashes on Windows 7.

### Compile Flags
```makefile
WIN_CXXFLAGS := -std=c++17 -O2 -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE
```

---

## 2. The Raylib 6.0 + OpenGL 3.3 Solution (Smooth Windows Resize)

Raylib 6.0 cross-compiles cleanly with MinGW against standard Windows OpenGL (`opengl32.dll`).

### Smooth Continuous Resize via Win32 Subclass
On Windows, `DefWindowProc` runs a modal loop during window drag-resize that starves the main loop, causing DWM to stretch the stale backbuffer.

Rather than maintaining a secondary Direct3D 11 backend, the template subclasses the GLFW window in `src/main.cpp` (`cf_resize_subclass_proc`):
1. Intercepts `WM_SIZE` while inside `WM_ENTERSIZEMOVE` modal drag.
2. Calls original GLFW window procedure first (`CallWindowProcW`) so viewport state updates.
3. Calls `render_frame_contents()` and presents with `present_no_poll()` (flushing batch + `SwapBuffers`, strictly avoiding re-entrant event polling).
4. Feeds delta time via `g_own_dt` / `rlImGuiBeginDelta` so time-scaled inputs never freeze.

> See **`docs/WINDOWS_OPENGL_RESIZE.md`** for complete crash-safety rules, the no-nested-poll rule, and the `GetFrameTime()` dt trap.

---

## 3. Static Runtime & Portable Packaging

MinGW binaries statically link GCC runtime where possible and bundle necessary dynamic dependencies (`libraylib.dll`, `glfw3.dll`, `libmcfgthread-2.dll`).

### Linker Flags
```makefile
WIN_LDFLAGS := -static-libgcc -static-libstdc++
WIN_LIBS := -L$(RAYLIB_CROSS_LIB) -lraylib \
  -lopengl32 -lgdi32 -lwinmm -luser32 -lshell32 -lcomdlg32 \
  -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic \
  -ldwmapi -lole32 -lsetupapi
```

### Standalone Distribution Folder Structure
```
my-tool-win64/
├── my-tool.exe
├── libraylib.dll
├── glfw3.dll
├── libmcfgthread-2.dll
├── assets/
│   └── fonts/
│       ├── InterVariable.ttf
│       └── ipag.ttf
├── lua/
│   ├── main.lua
│   └── ...
└── tests/
    ├── testmain.lua
    └── ...
```
Runs immediately on any Windows machine from Windows 7 SP1 to Windows 11 64-bit without installation.
