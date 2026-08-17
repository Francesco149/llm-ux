# Adversarial Review Dossier: LLM-UX Engineering & Harness Evaluation

> **For Review by Claude Opus 4.6 and DeepSeek V4 Flash**  
> **Objective**: Critically evaluate the entire engineering session, identify systemic root causes of all bugs/UX failures encountered, and propose concrete improvements to harness configurations, defaults, skill files, and automated testing gates.

---

## 1. Executive Summary & Project Goal

The goal of this research project is to establish the definitive framework, harness configuration, and skill files that allow LLMs (starting with cheap models like Gemini 3.7 Flash and DeepSeek V4 Flash, with optional offloading to Claude Opus 4.6) to autonomously make world-class UI/UX decisions for high-performance native desktop creation tools (Dear ImGui 1.92+, C++, embedded Lua 5.4, SDL3, Direct3D 11, Windows 7+ and Linux).

Three evaluation projects were built and refined:
1. **`texturewrangler`** (`/opt/src/texturewrangler`): Non-destructive retro texture editor.
2. **`godot-blockout`** (`/opt/src/godot-blockout`): 3D CSG level blockout editor with Godot 3D camera and 1-click `.tscn` export.
3. **`lowpoly-painter`** (`/opt/src/lowpoly-painter`): Low-poly 3D modeler and texture painter with automatic UV unwrapping and procedural texture baking.

---

## 2. Forensic Timeline of Bugs & UX Deficiencies Encountered

| Bug / UX Failure | Root Cause | Impact | Resolution | How to Prevent Systematically in Future |
|---|---|---|---|---|
| **Windows OpenGL/WGL Failure** (`Failed to create window: SDL not configured with OpenGL/WGL support`) | MinGW cross-compiled SDL3 with `SDL_WINDOW_OPENGL` requires explicit WGL context dispatch on Windows. | The `.exe` crashed immediately on startup on Windows host. | Switched to `SDL3` + `SDL_Renderer` (`imgui_impl_sdlrenderer3.h`), which automatically uses **Direct3D 11 (`d3d11`)** on Windows and Vulkan/OpenGL on Linux. | Standardize all native project templates to use `SDL_Renderer` / D3D11 by default. |
| **3D Perspective Matrix Shearing** | Typo in `mat4_transform_point`: `float y = m.m[1]*p.x + m.m[5]*p.y + m.m[9]*p.y + m.m[13];` (`p.y` used twice instead of `p.z`). | 3D geometry severely distorted and sheared vertically whenever camera panned or rotated. | Corrected to `m.m[9] * p.z`. | Add algebraic 3D projection unit tests that verify invariance under camera translation. |
| **ImGui 1.92 `IsNamedKey` Crash on Hover** (`Assertion failed: IsNamedKey(key)`) | Passing legacy integer scancodes (e.g. `46`, `44`) to `ig.is_key_pressed()` instead of `ImGuiKey` named enums (`ig.key.*`). | App crashed the moment the mouse hovered over the viewport window. | Replaced all integer keycodes with `ig.key.*` named keys. | Add a Lua binding runtime check in `ig.cpp` that asserts or translates integer keys, plus an interactive smoke test gate. |
| **Middle-Mouse Drag Crash** (`attempt to call nil value 'reset_mouse_drag_delta'`) | `reset_mouse_drag_delta` was bound in C++ but omitted from the Lua `REG(...)` registration table. | Dragging with middle mouse threw a nil error, aborted Lua frame, and crashed ImGui on `Missing EndChild()`. | Registered `REG(reset_mouse_drag_delta);` and added `pcall` balance recovery. | Automated API parity tests that reflect over C++ bindings and verify all exported functions exist in Lua. |
| **Pan Snap-Back Bug** | Panning in `"fit"` zoom mode did not disengage fit mode, so the next frame reset `st.ox, st.oy = 0, 0`. | Panning with mouse immediately snapped back to center upon release. | Panning/zooming sets `st.zoom = "custom"`, preserving camera offsets. | Include continuous drag & release assertions in UI smoke tests. |
| **Clunky Button-Driven UI vs True Direct Manipulation** | The LLM defaulted to placing buttons in a sidebar (`[Extrude]`, `[Move]`) rather than implementing direct in-viewport manipulation. | Frustrating, unnatural creator experience far below Blender/Godot/Figma standards. | Implemented Blender-grade modal interactions (`1/2/3` modes, `G` move in 3D, `E` interactive normal extrusion, `S` scale, HUD status badge). | Codify direct manipulation state machine recipes in `skill://native-ui-ux`. |
| **Test Blindness** | `make test` previously only ran state/math unit tests, never pumping ImGui frames or simulating mouse hover. | All UI-level crashes (hover keycode assertion, drag nil call) passed `make test` undetected. | Added `test_ui_smoke.lua` that pumps simulated interactive frames (hover, drag, keys) on every `make test`. | Make interactive UI smoke testing a mandatory build gate in all templates. |

---

## 3. Current Architecture & Harness Setup

1. **Harness & Config in `/opt/src/nix-lab`**:
   - `hosts/wslop/hm/omp.nix` manages declarative config.
   - `APPEND_SYSTEM.md` injects native UI/UX directives into system prompts.
   - Global skills in `~/.omp/agent/skills/`:
     - `skill://native-ui-ux`
     - `skill://scaffold-native-app`
     - `skill://imgui-recipes`
2. **Framework Repository in `/opt/src/llm-ux`**:
   - `ORIENTATION.md` & `README.md`
   - `templates/2d-canvas/` & `templates/3d-viewport/`
   - `tools/scaffold.py`, `tools/drive.lua`, `tools/embed.py`
   - `docs/DIRECT_MANIPULATION_AND_FEEL.md`, `docs/WINDOWS_COMPAT_AND_WIN7.md`, `docs/ZERO_DATA_LOSS_AND_UNDO.md`

---

## 4. Adversarial Review Prompts for Models

### Prompt for Claude Opus 4.6 (`docs/ADVERSARIAL_REVIEW_OPUS.md`):
> "You are an expert systems engineer and principal interaction designer conducting an adversarial critique of our native UI/UX architecture.
> Read `/opt/src/llm-ux/REVIEW_DOSSIER.md` and examine `/opt/src/llm-ux/`.
> 1. Critique our Slim C++ + Lua 5.4 + ImGui 1.92 + SDL_Renderer architectural split. Where are the remaining latent failure modes?
> 2. Why did a frontier model initially produce a clunky button-based UI instead of direct manipulation, and how can we alter the skill files / system instructions to guarantee that even Gemini 3.7 Flash or DeepSeek V4 always designs direct-manipulation workflows by default?
> 3. What exact static analysis, compile-time assertions, and automated smoke test gates should be added to our Nix templates?
> Write your complete, unsparing technical critique to `/opt/src/llm-ux/docs/ADVERSARIAL_REVIEW_OPUS.md`."

### Prompt for DeepSeek V4 Flash (`docs/ADVERSARIAL_REVIEW_DEEPSEEK.md`):
> "You are a compiler, graphics backend, and systems architect conducting an adversarial code review.
> Read `/opt/src/llm-ux/REVIEW_DOSSIER.md` and examine `/opt/src/llm-ux/`.
> 1. Audit the Windows 7 cross-compilation toolchain, Direct3D 11 / SDL_Renderer integration, and static runtime linking. Are there any edge cases, memory leaks, or ABI hazards on Windows or Linux?
> 2. How can we optimize Lua-to-C++ binding overhead and ensure 60fps frame pacing is strictly maintained?
> 3. Propose concrete improvements to our scaffolding tool and test drivers.
> Write your complete technical critique to `/opt/src/llm-ux/docs/ADVERSARIAL_REVIEW_DEEPSEEK.md`."

---

## 5. Instructions for Running Multi-Model Review Sessions

To execute standalone review sessions:

```sh
# 1. Claude Opus 4.6 Review Session
omp --model google-antigravity/claude-opus-4-6 "Read /opt/src/llm-ux/REVIEW_DOSSIER.md and write a comprehensive adversarial review to /opt/src/llm-ux/docs/ADVERSARIAL_REVIEW_OPUS.md following the prompt in Section 4."

# 2. DeepSeek V4 Flash Review Session
omp --model deepseek/deepseek-v4-flash "Read /opt/src/llm-ux/REVIEW_DOSSIER.md and write a comprehensive adversarial review to /opt/src/llm-ux/docs/ADVERSARIAL_REVIEW_DEEPSEEK.md following the prompt in Section 4."
```
