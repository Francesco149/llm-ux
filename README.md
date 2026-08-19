# llm-ux — Native Desktop Creation Tool Engineering Doctrine for LLM Agents

> **The definitive framework, architectural doctrine, and skill suite for frontier and lightweight LLMs (Gemini 3.7 Flash, DeepSeek, Claude Opus) to build high-performance, polished, native desktop creation tools (Dear ImGui 1.92+, C++, Embedded Lua 5.4, Raylib 6.0, OpenGL 3.3) that feel incredible, never crash, and run flawlessly across Linux and Windows 7+.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Nix Flake](https://img.shields.io/badge/Nix-Flake%20Reproducible-blue.svg)](flake.nix)
[![Backend: OpenGL 3.3](https://img.shields.io/badge/Backend-OpenGL%203.3-green.svg)](docs/WINDOWS_OPENGL_RESIZE.md)
[![Platform: Linux & Windows 7+](https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%207%2B-orange.svg)](docs/WINDOWS_COMPAT_AND_WIN7.md)

---

## 🎬 Showcase Video

<!-- ================================================================= -->
<!-- VIDEO SHOWCASE PLACEHOLDER: Upload demo showcase video / GIF here  -->
<!-- ================================================================= -->
<div align="center">
  <p><em>Demo Application: <strong>CubeForge</strong> — 3D Block Modeler & 2D Texture Paint Studio</em></p>
  <p><em>(Replace this block with your video / GIF showcase embed)</em></p>
  <!-- <video src="https://github.com/your-username/llm-ux/assets/demo.mp4" controls="controls" width="800"></video> -->
</div>
<!-- ================================================================= -->

---

## 🧠 Why This Setup Exists

Large Language Models (LLMs) are exceptionally capable at generating isolated code snippets, but historically fail when instructed to build native desktop creation tools (modelers, image editors, DAWs, node graphs, CAD utilities). Left to default heuristics, agents produce:

1. **Hostile Interaction Physics**: Center-screen zoom jump cuts, unformatted drag inputs without deadzones, lagging camera panning, and missing hover affordances.
2. **Fragile UI Frameworks & Crashes**: Default gray ImGui windows, manual Begin/End pairs that corrupt frame stacks on early return, and missing `pcall` balance recovery (`Missing EndChild()` fatal aborts).
3. **Data Loss & Destructive Edits**: Instant state mutations with no undo stack, uncoalesced continuous drags flooding history with 60 snapshots per second, and missing autosave rotation.
4. **Broken Windows Graphics Backends**: MinGW WGL context crashes, DWM modal drag-resize starvation causing stretched frames, or bloated dual-engine codebases (e.g. maintaining parallel D3D11 and OpenGL backends).
5. **Slow Agent Feedback Loops**: Bulky multi-minute build systems with fragile system dependencies that break autonomous self-correction.

`llm-ux` completely solves this by providing a battle-tested **slim C++ host + embedded Lua 5.4 architecture**, hermetic Nix cross-compilation, scoped crash-immune ImGui bindings, headless virtual-input drive testing, and master skill guidelines.

---

## ⚙️ The Converged Tech Stack & Architectural Decisions

Through extensive empirical head-to-head stack evaluation (comparing raw C++/OpenGL 3.3, SDL3 + SDL_Renderer, Raylib 6.0, and Odin/Zig), this repository converged on a unified architecture:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Embedded Lua 5.4                               │
│  - Document state model, serialization, mutation tracking, & undo/redo      │
│  - All UI panel layouts, tool state machines, and gizmo interactions        │
│  - Camera controllers (3D Godot language + 2D cursor-anchored pan/zoom)     │
│  - Dynamic GPU resources (materials, textures, RLSL shaders, mesh rebuilds) │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ Scoped C-API & pcall balance recovery
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                                Slim C++ Core                                │
│  - Raylib 6.0 Windowing & OpenGL 3.3 Host (single backend across all OSes)  │
│  - Dear ImGui 1.92+ via rlImGui bridge + Scoped Lua Binding Layer (ig.cpp)  │
│  - Win32 Continuous Drag-Resize Subclass (cf_resize_subclass_proc)          │
│  - Virtual Input Injection Engine (lp.drive.*) for Headless Verification    │
│  - Multi-tier Asset & User Configuration Path Resolution (app_paths.cpp)    │
│  - Embedded FontAwesome 6 Solid TTF Atlas & Dynamic Font Stack              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why Each Choice Was Made:

| Component | Choice | Rationale & Tradeoffs |
|---|---|---|
| **Window & Graphics** | **Raylib 6.0 + OpenGL 3.3** | Hardware depth buffer, 3D models/textures/RLSL shaders, and 2D canvas drawing out of the box. Eliminates hundreds of lines of C++ GPU boilerplate while compiling in < 2 seconds. |
| **Logic & UI Layer** | **Embedded Lua 5.4** | Total crash immunity: panel errors are caught in `pcall` and logged without terminating the process. Agents stay in high-velocity Lua without recompiling C++. |
| **UI Framework** | **Dear ImGui 1.92+ with Scoped Wrappers** | Scoped wrappers (`ig.window`, `ig.child`, `ig.popup`, `ig.table_`, etc.) guarantee matching `End` calls even on Lua errors. Frame-end balance tracking (`ig_balance_check`) prevents frame-stack corruption. |
| **Windows Resize** | **Win32 Window Subclass (`main.cpp`)** | Solves Windows modal drag-resize starvation in-app by re-rendering from `cf_resize_subclass_proc` with `present_no_poll()`. Enables **100% single-backend OpenGL 3.3 everywhere** and completely removes the need for a separate Direct3D 11 engine. *(See [docs/WINDOWS_OPENGL_RESIZE.md](docs/WINDOWS_OPENGL_RESIZE.md))*. |
| **Verification** | **Virtual Input Drive (`lp.drive.*`)** | Frame-accurate headless input injection (mouse, buttons, wheel, keys). Tests run hidden offscreen with **zero window focus, zero xdotool, and zero synthetic OS events**. |
| **Build & Toolchain** | **Hermetic Nix Flakes + MinGW-w64** | 100% reproducible native Linux builds and standalone portable Windows PE `.exe` cross-compilation with static GCC runtimes and bundled DLLs (`libraylib.dll`, `glfw3.dll`, `libmcfgthread-2.dll`). |
| **Typography & Icons** | **Inter + IPA Gothic + FontAwesome 6** | Dual-range dynamic font stack (Latin/Cyrillic primary + merged CJK fallback) loaded at runtime, paired with an embedded binary FontAwesome 6 Solid atlas (`src/fa6/`) for zero runtime asset dependencies. |

---

## ⚡ Recommended Agentic Setup: Gemini 3.7 Flash on Oh My Pi (`omp`)

The optimal, highest-velocity agentic coding configuration for building native tools with this repository is **Gemini 3.7 Flash** running inside the **Oh My Pi (`omp`)** coding harness:

### 1. Why Gemini 3.7 Flash?
- **Speed & Token Velocity**: Extremely low latency allows rapid multi-turn implementation, code iteration, and test tape generation.
- **Flawless Lua & C++ Integration**: Follows strict architectural invariants, avoids hallucinating removed Lua 5.4 APIs, and adheres cleanly to scoped ImGui bindings.
- **Cost Efficiency**: Free within Google AI Pro subscription tiers, enabling unbounded exploration, refinement, and autonomous testing.

### 2. Multi-Model Tiered Delegation
For maximum quality and safety, combine models with complementary strengths:
- **Primary Builder (`Gemini 3.7 Flash`)**: Scaffolding, feature implementation, UI panel layout, mathematical kernels, and input drive scripts.
- **Adversarial Reviewer (`Claude Opus 4.6` or `DeepSeek V4 Flash`)**: One-shot post-implementation audits, ABI boundary validation, and Undefined Behavior checks.
- **Vision Validator (`Qwen 3.7 Flash`)**: Automated visual smoke test verification of offscreen screenshots (`--shot`) and drive tapes.

---

## 🚀 Quickstart: Scaffolding a New Native Project

Generate a fully working, cross-compiling native desktop tool in seconds:

```sh
# Enter the hermetic Nix environment
nix develop ./templates/raylib

# Scaffold a new standalone project
python3 tools/scaffold.py /opt/src/my-tool --name "VoxelStudio" --desc "High-performance voxel creation tool"

# Build and execute the test gate
cd /opt/src/my-tool
nix develop --command make -C editor test

# Run the interactive application
nix develop --command make -C editor run

# Cross-compile standalone portable Windows release (exe + DLLs + fonts + lua)
nix develop --command make -C editor package zip-win
```

---

## 🤖 How to Point Your Agents to This Setup

To instruct autonomous agents (or custom prompt harnesses) to build native creation tools adhering to these standards, point them to the packaged skills and documentation:

### 1. Mount Master LLM Skills
- **`skill://scaffold-native-app`**: Turnkey project generation, Nix flake configuration, directory layout, and headless test harnesses.
- **`skill://native-ui-ux`**: Interaction physics doctrine, 60 FPS locked frame pacing, cursor-anchored zoom math, deadzones, and undo coalescing.
- **`skill://imgui-recipes`**: Production recipes for 2D infinite canvases, 3D viewports, in-window Godot-style splitters, floating pill toolbars, layer stacks, color pickers, and context menus.

### 2. System Directive Hook (`APPEND_SYSTEM.md`)
Add the following directive to your agent harness configuration:
```markdown
When designing or implementing native desktop creation tools:
1. Always base new projects on the Raylib 6.0 + ImGui 1.92 + Lua 5.4 template (`templates/raylib` or `skill://scaffold-native-app`).
2. Adhere strictly to the interaction physics and scoped UI patterns in `skill://native-ui-ux` and `skill://imgui-recipes`.
3. Consult `docs/WINDOWS_OPENGL_RESIZE.md` before modifying C++ frame loop, presentation, or timing code.
4. Verify every feature headlessly using `lp.drive` input tapes (`make -C editor test`, `make shot-drive`).
```

---

## 📂 Repository Map

```
llm-ux/
├── ORIENTATION.md                 # Single-source-of-truth dense project orientation
├── README.md                      # Public overview, stack rationale, & agent guide
├── LICENSE                        # MIT License
├── flake.nix                      # Nix flake definition
├── skills/                        # Master skill packs
│   ├── native-ui-ux/              # Interaction laws, Fitts's law, spring lerp physics
│   ├── scaffold-native-app/       # Scaffolding blueprint & test harness standard
│   └── imgui-recipes/             # Tested C++ & Lua ImGui UI component recipes
├── templates/
│   └── raylib/                    # Master starter template: CubeForge (2D + 3D)
│       ├── flake.nix              # Hermetic Nix flake (Raylib 6.0, MinGW cross, ImGui 1.92)
│       ├── ORIENTATION.md         # Template orientation guide
│       └── editor/
│           ├── Makefile           # Targets: linux, win, package, zip-all, test, shot, shot-drive
│           ├── src/               # Slim C++ host (main.cpp, ig.cpp, app_paths.cpp, winclip.c)
│           ├── lua/               # Embedded Lua 5.4 application (main, doc, geom, undo, drive)
│           └── tests/             # Headless test runner & automated input drive scripts
├── tools/
│   ├── scaffold.py                # Turnkey project generator CLI
│   ├── drive.lua                  # Reference headless input tape library
│   └── embed.py                   # Binary font & asset embedder
└── docs/                          # In-depth architectural references
    ├── WINDOWS_OPENGL_RESIZE.md   # Windows modal resize analysis, subclass fix, & dt trap
    ├── WINDOWS_COMPAT_AND_WIN7.md # Windows 7+ standalone compatibility & MinGW toolchain
    ├── IMGUI_WRAPPER_DESIGN.md    # Scoped ImGui wrappers & frame balance tracker design
    ├── DIRECT_MANIPULATION_AND_FEEL.md # Mathematical HCI & feel doctrine
    └── EVALUATION_RESULTS.md      # Head-to-head stack evaluation findings (Raylib vs OpenGL)
```

---

## 📜 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
All bundled template code, tools, and skills are freely usable in personal and commercial software.
