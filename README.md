# llm-ux — Native Creation Tool Framework & LLM Design Doctrine

> **Empowering Frontier & Lightweight LLMs to design and engineer native desktop creation tools with world-class UX, 60 FPS feel, and zero boilerplate.**

---

## 🚀 Overview

LLMs historically default to creating clunky, frustrating user interfaces: unformatted drag inputs, default gray ImGui themes, center-screen zoom jump cuts, destructive state changes without undo, and broken window backends on Windows.

`llm-ux` solves this by establishing:
1. **Master UI/UX Skill Files (`skills/`)**: Teaches any LLM the exact mathematical laws, interaction physics, and design heuristics of pro tools like Figma, tldraw, and Godot.
2. **Hermetic Nix Scaffolding (`tools/scaffold.py` & `templates/`)**: Generates 100% reproducible repositories with cross-compilation toolchains, embedded fonts, and automated test gates in seconds.
3. **Zero-Footgun Windows 7+ / Linux Backend**: Uses SDL3 + `SDL_Renderer` (D3D11 on Windows, Vulkan/OpenGL on Linux) to guarantee that standalone Windows binaries run on any host without missing DLLs or WGL/OpenGL crashes.
4. **Headless Verification Harness (`tools/drive.lua`)**: Enables automated offscreen UI screenshot capture and headless tape replay for autonomous verification with vision models.

---

## 📦 Project Architecture

Native creation tools built under this paradigm follow the **Slim C++ Core + Embedded Lua 5.4** architecture:

```
                  ┌──────────────────────────────────────────────┐
                  │              Embedded Lua 5.4                │
                  │  (Document Model, Undo, Autosave, UI Panels, │
                  │   Tool State Machines, Gesture Physics)      │
                  └──────────────────────┬───────────────────────┘
                                         │  pcall / Lua C-API
                  ┌──────────────────────▼───────────────────────┐
                  │               Slim C++ Core                  │
                  │  (SDL3 + SDL_Renderer / D3D11, ImGui 1.92,  │
                  │   Fast Math/Pixel/CSG Computation Kernels)   │
                  └──────────────────────────────────────────────┘
```

- **Zero Stale Files**: Single compilation unit or clean modular core building in under 2 seconds.
- **Crash Immunity**: Lua UI panels run inside `pcall` wrappers; an error in one panel logs to the console and never crashes the application.
- **Determinism**: Identical byte outputs across Linux and Windows.

---

## 🛠️ Quickstart: Scaffolding a New Native Project

```sh
# Generate a new 2D canvas tool
python3 /opt/src/llm-ux/tools/scaffold.py /opt/src/my-tool --name my-tool --type 2d

# Generate a new 3D level / modeler tool
python3 /opt/src/llm-ux/tools/scaffold.py /opt/src/my-3d-tool --name my-3d-tool --type 3d

# Build and run tests
cd /opt/src/my-tool
nix develop --command make -C editor test

# Package standalone Windows release (exe + DLLs + lua)
nix develop --command make -C editor package
```

---

## 📚 Battle-Tested Evaluation Projects

- **`texturewrangler`** (`/opt/src/texturewrangler`): Non-destructive retro texture editor (350/350 tests passing).
- **`godot-blockout`** (`/opt/src/godot-blockout`): 3D CSG level blockout editor with Godot 3D-grade camera and 1-click `.tscn` export (35/35 tests passing).
- **`lowpoly-painter`** (`/opt/src/lowpoly-painter`): Low-poly 3D modeler with automatic UV unwrapping and procedural texture baking (30/30 tests passing).

---

## 📄 License
MIT
