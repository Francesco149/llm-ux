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

## 2. The SDL3 + `SDL_Renderer` Solution (Eliminating OpenGL/WGL Pitfalls)

When cross-compiling for Windows with MinGW, requesting raw OpenGL via `SDL_WINDOW_OPENGL` fails with:
`Failed to create window: SDL not configured with OpenGL/WGL support.`

### Why SDL_Renderer Succeeds
`SDL_CreateRenderer(window, nullptr)` automatically queries and selects:
1. **Direct3D 11 (`d3d11`)** on Windows (universal hardware acceleration on Win7+).
2. **Vulkan / OpenGL** on Linux.

Pairing `SDL_Renderer` with `imgui_impl_sdlrenderer3.h` provides:
- Crisp vector and dynamic font rasterization.
- Sub-pixel drawing precision.
- Zero manual WGL/EGL context management.

---

## 3. Static Runtime & Portable Packaging

MinGW binaries often depend on `libgcc_s_seh-1.dll`, `libstdc++-6.dll`, and `libmcfgthread-2.dll`.

### Linker Flags
```makefile
WIN_LDFLAGS := -static-libgcc -static-libstdc++ -mconsole
WIN_LIBS := -L$(SDL3_CROSS_LIB) -lSDL3 -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic \
  -lgdi32 -limm32 -lole32 -loleaut32 -lversion -lwinmm -luuid -ldxgi -ld3d11 \
  -lsetupapi -lcomdlg32 -lshell32 -luser32 -lkernel32
```

### Standalone Distribution Folder Structure
```
my-tool-win64/
├── my-tool.exe
├── SDL3.dll
├── libmcfgthread-2.dll
└── lua/
    ├── main.lua
    └── ...
```
Runs immediately on any Windows machine from Windows 7 SP1 to Windows 11 64-bit without installation.
