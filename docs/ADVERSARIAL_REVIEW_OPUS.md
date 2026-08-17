# Adversarial Review: LLM-UX Native Creation Tool Framework

**Reviewer**: Claude Opus 4.6 (adversarial systems engineering & interaction design critique)
**Date**: 2026-08-17
**Scope**: Full repository (`/opt/src/llm-ux`), all skill files, templates, tooling, docs, and the forensic dossier of bugs encountered across three evaluation projects.

---

## Verdict

The architecture is fundamentally sound. The C++/Lua split, SDL_Renderer backend choice, and the skill-driven LLM guidance approach are correct decisions that have been validated by shipping three working tools. But the framework has **systemic weaknesses in five areas** that will produce recurring classes of bugs as new projects and new LLM models are added. This review identifies each, explains the root cause mechanism, and proposes concrete structural fixes.

---

## 1. Critique of the Slim C++ + Lua 5.4 + ImGui 1.92 + SDL_Renderer Split

### 1.1 What's Right

The architectural split is well-chosen:
- C++ owns the hot loop, GPU surface, and pixel kernels. Lua owns all mutable state, UI layout, and tool logic. This means LLMs only need to write Lua for product features and never touch the C++ frame loop after initial scaffolding.
- `pcall` isolation prevents Lua panel errors from crashing the process.
- SDL_Renderer abstracts away the WGL/D3D11/Vulkan backend selection entirely, eliminating the class of bugs that killed the first Windows build.
- Single-TU or flat-file C++ compilation keeps build times under 2 seconds.

### 1.2 Latent Failure Modes That Remain

**F1: The Binding Parity Gap is structural, not incidental.**

The `reset_mouse_drag_delta` bug (C++ function implemented but omitted from the `REG(...)` table) is not a one-off typo. It is a *structural inevitability* of the current architecture. The `ig.cpp` binding surface is ~980 lines of hand-written `static int l_*(lua_State* L)` functions paired with a separate `REG(name)` registration block. There is no mechanism ensuring these two lists stay synchronized. Every time an LLM (or human) adds a new ImGui binding:

1. They write the `l_foo` function.
2. They must *separately* remember to add `REG(foo)` in the registration block 200+ lines below.
3. No compiler error, no linker error, no test failure occurs if step 2 is forgotten.

The current smoke tests check for `reset_mouse_drag_delta` specifically because it was the *known* missing binding. They do not check for *any other* missing binding. A new binding added tomorrow and omitted from REG will pass all tests.

**Concrete fix**: Add a compile-time or startup-time binding parity check. Two approaches:

*Option A (compile-time, preferred)*: Replace the hand-written `REG(name)` block with an X-macro table:
```cpp
#define IG_BINDINGS(X) \
    X(begin) \
    X(end_) \
    X(begin_child) \
    X(end_child) \
    X(reset_mouse_drag_delta) \
    // ...every binding
```
Then generate both the function declarations and the registration from the same macro. An `l_foo` function that exists without an X-entry won't compile (unused static function warning under `-Werror`), and an X-entry without an `l_foo` function won't link.

*Option B (runtime)*: At startup, after `ig_register()`, iterate the `tw.ig` Lua table and compare it against a known-complete list. Or: tag every `static int l_*` with `__attribute__((used))` and compare the set of tagged symbols against the registered set at startup.

**F2: The `g_dl` draw list handle vector leaks stale pointers across frames.**

`ig.cpp` uses a `static std::vector<ImDrawList*> g_dl` that grows monotonically. `l_dl_gc` releases the Lua userdata but the vector entry is never cleared. If Lua code holds a draw list handle across frames (which `pcall` error recovery makes possible), the `ImDrawList*` in `g_dl` points to a freed ImGui-internal buffer. The `check_dl` function dereferences it without validation.

This hasn't crashed yet because draw list handles are typically short-lived within a single frame's `pcall`. But it *will* crash under:
- A Lua coroutine that yields mid-frame (not currently used, but nothing prevents it).
- A leaked upvalue in a Lua closure that captures a draw list handle.
- An error path where a draw list handle survives into the next frame.

**Concrete fix**: Clear `g_dl` at the start of each frame (in `lua_frame()` or at ImGui `NewFrame()`). Add an epoch counter; each draw list userdata records the epoch it was created in; `check_dl` asserts the epoch matches the current frame.

**F3: `path_join` / `path_dirname` static buffer aliasing.**

The ORIENTATION.md for texturewrangler explicitly warns: *"path_join/path_dirname use a rotating static buffer ring — nested calls alias."* This is a ticking time bomb that has already required special handling. The correct fix is `std::string` return values or caller-provided buffers. The current design optimizes for zero-allocation at the cost of correctness under composition. Since these functions are called from Lua (which already allocates freely), the zero-allocation argument is moot.

**Concrete fix**: Change `path_join` and `path_dirname` to return `std::string` or to take a `char* buf, size_t bufsz` parameter. The static buffer ring is a premature optimization that creates aliasing bugs at the callsite.

**F4: SDL3 API surface is not version-pinned.**

The Nix flake pins `pkgs.sdl3` from `nixos-unstable`. SDL3 is pre-1.0-stability (the dossier already notes `SDL_RenderReadPixels` changed signature in 3.4.12, and `SDL_GetVersion()` changed return type). Every `nix flake update` can silently break the build or change runtime behavior. The ImGui source is correctly pinned to `v1.92.4` by hash; SDL3 is not.

**Concrete fix**: Pin SDL3 to a specific commit hash in the flake, like ImGui. Add a comment with the version. Update deliberately, not accidentally.

**F5: No Lua type-checking for ImGui enum arguments.**

Every widget function in `ig.cpp` accepts raw `lua_Integer` arguments for flags, colors, and style vars. There is no runtime validation that the integer is a valid enum member. Passing `ig.col.Button` where `ig.var.FrameRounding` is expected silently corrupts ImGui state. The skill file warns about `PushStyleVar float vs ImVec2`, but the binding layer itself performs no check.

**Concrete fix**: In `l_push_style_var`, validate the integer against the known set of `ImGuiStyleVar_*` values. For color indices, bounds-check against `ImGuiCol_COUNT`. These are single-comparison guards, not performance-relevant.

---

## 2. Why Frontier Models Default to Button-Based UI (and How to Fix It)

### 2.1 Root Cause Analysis

The dossier records: *"The LLM defaulted to placing buttons in a sidebar (`[Extrude]`, `[Move]`) rather than implementing direct in-viewport manipulation."*

This is not a knowledge gap. Frontier models (including Gemini, DeepSeek, and Claude) *know* that Blender uses `G` for grab and `E` for extrude. The problem is **output probability distribution bias**:

1. **Training data skew**: The vast majority of ImGui tutorial code, GitHub repositories, and Stack Overflow answers demonstrate ImGui via `if (ImGui::Button("Extrude")) { ... }`. Direct manipulation state machines are rare in ImGui codebases. The model's *default completion* for "create an extrude feature" is overwhelmingly a button.

2. **Incremental complexity avoidance**: A button-based UI is 5 lines of code. A modal state machine with hover highlights, mouse tracking, constraint axes, cancel/confirm, and HUD overlay is 80-150 lines. LLMs optimize for the shortest correct completion unless the prompt *structurally forces* the longer path.

3. **Ambiguity in task specification**: "Add extrude" is ambiguous between "add a button that extrudes" and "add Blender-style interactive extrusion." Without explicit disambiguation, the model picks the simpler interpretation.

4. **Missing interaction recipes**: The skill file (`native-ui-ux`) describes the *principle* of direct manipulation ("The Anti-Button Law") and names the hotkeys, but does not provide a **copy-pasteable state machine template** in Lua. The `imgui-recipes` skill has canvas, toolbar, layer stack, slider, and context menu recipes — but *no modal transform state machine recipe*. This is the single biggest gap.

### 2.2 Concrete Fixes to Skill Files and System Instructions

**Fix 1: Add a Modal Transform State Machine Recipe to `imgui-recipes/SKILL.md`**

This is the highest-impact change. Add a complete, copy-pasteable Lua recipe that implements:
```
Idle → (press G) → GrabActive → (mouse delta applied each frame) → (LClick/Enter) → Commit
                                                                  → (RClick/Esc) → Cancel + Restore
```

With: snapshot capture on enter, live preview each frame, HUD status badge, constraint axis locking (`X`/`Y`/`Z` while in mode), and undo push on commit. The recipe should be a generic `modal_transform(doc, selection, transform_fn, axis_constraint)` that any project can instantiate.

Models that see a concrete, working 60-line state machine recipe will copy its structure. Models that see only the *principle* of direct manipulation will default to buttons.

**Fix 2: Make the Anti-Button Law a hard gate, not a guideline**

In `native-ui-ux/SKILL.md`, change Section 2 from descriptive ("THE LLM TRAP") to prescriptive:

> **MANDATORY**: Every geometric transform operation (move, scale, rotate, extrude) MUST be implemented as a modal state machine activated by a single-key hotkey, with real-time mouse-following preview, commit on Left-Click/Enter, and cancel on Right-Click/Escape. Sidebar buttons MAY exist as secondary access but MUST NOT be the primary interaction path. A `make test` smoke test MUST verify that pressing the hotkey enters the modal state and that cancel restores the prior state.

**Fix 3: Add a "Negative Example" section to the skill file**

LLMs respond strongly to explicit negative examples. Add:

> **WRONG** (button-driven):
> ```lua
> if ig.button("Extrude") then mesh.extrude_face(doc.mesh, sel, 1.0) end
> ```
> **RIGHT** (direct manipulation):
> ```lua
> if not doc.action and ig.is_key_pressed(ig.key.E) and doc.selected_face then
>     doc.action = "extrude"
>     doc.action_orig = doc.snapshot()
>     mesh.extrude_face(doc.mesh, doc.selected_face, 0)
> end
> if doc.action == "extrude" then
>     -- mouse delta → extrusion distance each frame, HUD badge, commit/cancel
> end
> ```

**Fix 4: Add a mandatory "Interaction Architecture" section to ORIENTATION.md templates**

The scaffold's `ORIENTATION_MD_TEMPLATE` currently says: *"All actions have keyboard shortcuts and clear tooltips."* This is too weak. Add:

> ## Interaction Architecture
> - All transform operations use modal state machines (not buttons). See `skill://imgui-recipes` Section 6 for the template.
> - Hotkey activation → real-time mouse preview → commit/cancel.
> - HUD status badge during in-flight operations.

This primes every LLM that reads the ORIENTATION at the start of a session.

**Fix 5: For weaker models (Gemini Flash, DeepSeek Flash), inject the recipe directly**

These models have smaller context windows and weaker instruction-following. For them, the scaffold should generate a `editor/lua/modal.lua` file containing the generic modal transform state machine, pre-wired. The model then only needs to *call* `modal.begin("extrude", ...)` rather than *invent* the state machine from principles.

---

## 3. Static Analysis, Compile-Time Assertions, and Automated Smoke Test Gates

### 3.1 Current State (Insufficient)

The current test gates are:
- `make test`: Runs Lua headless tests (state/kernel assertions + basic smoke test).
- `make test-asan`: Same under AddressSanitizer.
- `make shot`: Offscreen screenshot for vision model inspection.
- Golden composite regression (2d-canvas only).

The smoke tests (`test_ui_smoke.lua`) are **retrospective patches**: they check for the *specific* bugs that were already found (`reset_mouse_drag_delta` binding, `ig.key.*` constants > 500, ray intersection). They do not systematically prevent *new instances of the same bug classes*.

### 3.2 Required Additions

**Gate 1: Binding Parity Test (compile-time or `--test` startup)**

As described in F1 above. Every C++ function matching `static int l_*(lua_State* L)` in `ig.cpp` must have a corresponding entry in the Lua `tw.ig` table. Automate this:

```lua
-- test_binding_parity.lua
local ig = tw.ig
local expected = {
    "begin", "end_", "begin_child", "end_child", "same_line",
    -- ... exhaustive list generated from ig.cpp at scaffold time
}
for _, name in ipairs(expected) do
    assert(type(ig[name]) == "function",
           "BINDING PARITY: ig." .. name .. " is not registered")
end
```

Better: generate this list from `ig.cpp` at build time with a simple grep/awk rule in the Makefile:
```makefile
tests/binding_parity.lua: src/ig.cpp
	grep -oP 'static int l_(\w+)\b' $< | sed 's/static int l_//' | \
	  python3 -c "import sys; names=sys.stdin.read().split(); print('return {' + ','.join('\"'+n+'\"' for n in names) + '}')" > $@
```

**Gate 2: ImGuiKey Assertion Guard in C++ (compile-time)**

In `l_is_key_pressed` and `l_is_key_down`, add a runtime assertion:
```cpp
static int l_is_key_pressed(lua_State* L) {
    ImGuiKey key = (ImGuiKey)luaL_checkinteger(L, 1);
    if (!ImGui::IsNamedKey(key)) {
        return luaL_error(L, "is_key_pressed: %d is not a valid ImGuiKey "
                             "(use ig.key.* constants)", (int)key);
    }
    lua_pushboolean(L, ImGui::IsKeyPressed(key));
    return 1;
}
```
This converts the ImGui assertion crash into a clean Lua error with a diagnostic message. This is a 2-line change that eliminates an entire class of crash.

**Gate 3: Begin/End Balance Verification**

ImGui crashes hard on unbalanced `Begin`/`End` pairs. The `pcall` wrapper in `main.lua` is the current mitigation, but it's reactive (catches the crash after it happens). Add proactive verification:

```cpp
// In ig.cpp: track begin/end depth
static int g_begin_depth = 0;
static int l_begin(lua_State* L) { g_begin_depth++; /* ... */ }
static int l_end(lua_State* L)   { g_begin_depth--; /* ... */ }
// Expose: int ig_get_begin_depth() { return g_begin_depth; }
```

At the end of each `lua_frame()`, assert `g_begin_depth == 0`. On mismatch, log the imbalance and force-close remaining windows rather than crashing.

**Gate 4: 3D Math Algebraic Invariant Tests**

The `mat4_transform_point` typo (`p.y` instead of `p.z`) was a single-character bug that produced dramatic visual corruption. Add algebraic tests:

```lua
-- test_math3d.lua
-- Identity transform preserves points
local p = {1.5, 2.7, 3.9}
local tp = math3d.transform_point(math3d.identity(), p)
assert(math.abs(tp.x - p[1]) < 1e-6)
assert(math.abs(tp.y - p[2]) < 1e-6)
assert(math.abs(tp.z - p[3]) < 1e-6)

-- Translation moves exactly
local t = math3d.translate(10, 20, 30)
local tp2 = math3d.transform_point(t, {0, 0, 0})
assert(math.abs(tp2.x - 10) < 1e-6)
assert(math.abs(tp2.y - 20) < 1e-6)
assert(math.abs(tp2.z - 30) < 1e-6)

-- Perspective projection invariant: a point at the camera origin
-- projects to the center of the screen
local proj = math3d.perspective(math.rad(60), 1.0, 0.1, 100)
local view = math3d.lookat({0,0,5}, {0,0,0}, {0,1,0})
local clip = math3d.transform_point(math3d.mul(proj, view), {0, 0, 0})
-- After perspective divide, x and y should be near 0 (screen center)
assert(math.abs(clip.x / clip.w) < 0.01, "Center point must project to screen center X")
assert(math.abs(clip.y / clip.w) < 0.01, "Center point must project to screen center Y")
```

These tests would have caught the `p.y`/`p.z` swap immediately.

**Gate 5: Continuous Drag Smoke Test**

The pan snap-back bug occurred because fit mode wasn't disengaged on pan. Add a smoke test that simulates a drag and verifies the camera state persists:

```lua
-- test_ui_smoke.lua addition
function M.test_pan_persists()
    preview.state.zoom = "fit"
    preview.state.ox, preview.state.oy = 0, 0
    -- Simulate pan gesture
    preview.on_pan_start(100, 100)
    preview.on_pan_move(150, 120)
    preview.on_pan_end()
    -- After pan, zoom must be "custom" and offsets non-zero
    t.eq(preview.state.zoom, "custom", "Pan must disengage fit mode")
    t.true_(preview.state.ox ~= 0 or preview.state.oy ~= 0,
            "Pan offsets must persist after release")
end
```

**Gate 6: Scaffold Template Validation**

`scaffold.py` generates a directory structure and writes files, but it does not validate the result. Add a self-test:

```python
# After writing all files:
required_files = [
    "flake.nix", "ORIENTATION.md", "README.md", "LICENSE", ".gitignore",
    "editor/src/main.cpp",   # or at minimum the directories
    "editor/lua/main.lua",
    "editor/tests/test_ui_smoke.lua",
]
for f in required_files:
    assert (target_dir / f).exists() or (target_dir / f).parent.is_dir(), \
        f"Scaffold validation failed: {f} not created"
```

More critically: `scaffold.py` currently creates empty directories but writes *zero* source files. It generates `flake.nix`, `ORIENTATION.md`, `README.md`, `LICENSE`, and `.gitignore` from templates, then creates empty `editor/src/`, `editor/lua/`, and `editor/tests/` directories. **The scaffolder does not actually produce a buildable project.** It should either:
- Copy the template files from `templates/2d-canvas/` or `templates/3d-viewport/` into the target, or
- Generate minimal `main.cpp`, `app.cpp`, `ig.cpp`, `lua.cpp`, `main.lua`, and `test_ui_smoke.lua` from templates.

As-is, running `scaffold.py` and then `make -C editor` will fail because there are no source files. The scaffold tool is, at best, a documentation generator — not a project generator.

---

## 4. Additional Systemic Concerns

### 4.1 The `drive.lua` Test Driver Uses Raw Scancodes

The very tool designed to prevent keycode bugs *itself* uses raw integer scancodes:
```lua
Key = {
    Ctrl = 224, Shift = 225, Alt = 226, Space = 44,
    Enter = 40, Escape = 41, V = 25, H = 11, ...
}
```

These are SDL scancodes, not ImGuiKey values. The test driver injects them as synthetic `key_event` with a `scancode` field. If the application's C++ side converts SDL scancodes to ImGuiKey values (which ImGui 1.92's `imgui_impl_sdl3.cpp` does internally), this works. But:

1. The mapping is implicit and undocumented.
2. If someone adds a test that calls `ig.is_key_pressed(D.Key.V)` directly (confusing the drive scancode with an ImGuiKey), it will trigger the exact `IsNamedKey` assertion the framework was designed to prevent.
3. The `Key` table in `drive.lua` is incomplete (no letter keys beyond V, H, B, E, R, C, G, S, Z, Y, F; no number keys).

**Fix**: Either make `drive.lua` use ImGuiKey constants (which requires the Lua VM to be initialized before the drive table is constructed) or add a big comment warning that these are SDL scancodes, not ImGuiKey values, and must only be used in `D.key_event()` synthetic injection.

### 4.2 Undo Journal Grows Without Bound

`undo.jsonl` is append-only with no rotation, truncation, or compaction. A long editing session pushing full state snapshots every few seconds will produce a multi-gigabyte journal. The autosave doc mentions backup rotation for `project.json`, but the undo journal has no such mechanism.

**Fix**: Add a configurable max journal size (e.g., 10 MB or 1000 entries). On overflow, truncate the oldest half, or rotate to `undo.1.jsonl`. Alternatively, switch from full-state snapshots to delta encoding (which also dramatically reduces journal size for large documents).

### 4.3 No High-DPI Support

The entire framework assumes 1x pixel density. On 4K displays at 200% scaling (common on modern laptops), all UI elements will be half-sized. ImGui supports high-DPI via `io.FontGlobalScale` and per-monitor DPI awareness, but none of the templates, skill files, or docs mention it. The `ApplyModernDarkTheme()` hardcodes pixel sizes (`WindowPadding = 8.0`, `FramePadding = 6.0`) without DPI scaling.

This is noted as a "Next idea" in the texturewrangler ORIENTATION but is not addressed anywhere in the framework itself.

**Fix**: Add a DPI scale factor to the theme application, and document the pattern in `native-ui-ux/SKILL.md`. At minimum:
```cpp
float scale = SDL_GetDisplayContentScale(SDL_GetPrimaryDisplay());
io.FontGlobalScale = scale;
// Apply scale to all hardcoded padding/spacing values
```

### 4.4 The 3D Template is Significantly Less Mature Than the 2D Template

Comparing the two templates:

| Aspect | 2d-canvas | 3d-viewport |
|---|---|---|
| C++ source files | 8 (130 KB total) | 7 (64 KB total) |
| Test files | 10 (65 KB) | 3 (3 KB) |
| Makefile | Full (ASan, golden, run, test-bless) | Basic (no ASan, no golden) |
| ORIENTATION.md | 230 lines, detailed gotchas | 35 lines, minimal |
| Crash debugging infra | VEH/SEH handlers, minidump parser, debug log | None |
| Smoke test | Checks key constants + binding + state | Checks key constants + binding + mesh ops |

The 3d-viewport template is the one most likely to be used for the *harder* class of projects (3D editors, level designers) but has 1/20th the test coverage and no crash debugging infrastructure. An LLM scaffolding a 3D project gets a significantly weaker starting point.

**Fix**: Port the 2d-canvas's ASan targets, crash handlers, debug logging, and golden composite regression framework to the 3d-viewport template. Add `mat4_transform_point` algebraic tests and raycast invariant tests.

### 4.5 Template Code Duplication

Both templates contain *identical* copies of `ig.cpp` (32.5 KB each). The `editor.h`, `app.cpp`, `lua.cpp`, and Makefiles are near-identical with project-name substitutions. This means:
- A bug fix to `ig.cpp` must be applied to both templates manually.
- A new ImGui binding must be added in two places.
- The templates will inevitably diverge as one gets more attention.

**Fix**: Extract the shared C++ infrastructure (`ig.cpp`, `app.cpp`, common Makefile rules) into a `shared/` directory or a git submodule. Templates would include the shared code and add only project-specific files (`kernels.cpp`, `mesh.cpp`).

---

## 5. Summary of Prioritized Recommendations

| Priority | Action | Effort | Impact |
|---|---|---|---|
| **P0** | Add ImGuiKey validation guard in `l_is_key_pressed`/`l_is_key_down` | 10 min | Eliminates entire crash class |
| **P0** | Add modal transform state machine recipe to `imgui-recipes` | 2 hrs | Fixes the button-UI default for all models |
| **P0** | Pin SDL3 version in flake.nix | 5 min | Prevents silent breakage on `nix flake update` |
| **P1** | Implement binding parity check (X-macro or generated test) | 1 hr | Prevents all future missing-binding bugs |
| **P1** | Fix `scaffold.py` to actually generate source files from templates | 2 hrs | Makes the scaffold tool functional |
| **P1** | Add 3D math algebraic invariant tests to 3d-viewport template | 1 hr | Prevents matrix/projection typo bugs |
| **P1** | Clear `g_dl` draw list vector per frame + epoch guard | 30 min | Prevents stale draw list pointer dereference |
| **P2** | Undo journal rotation / size cap | 1 hr | Prevents unbounded disk usage |
| **P2** | Port 2d-canvas test/debug infra to 3d-viewport | 3 hrs | Parity between template maturity |
| **P2** | Deduplicate shared C++ code between templates | 4 hrs | Prevents template divergence |
| **P2** | Add high-DPI scaling pattern to skill files + templates | 2 hrs | Prevents tiny UI on modern displays |
| **P3** | Replace `path_join`/`path_dirname` static buffers with `std::string` | 30 min | Eliminates aliasing footgun |
| **P3** | Document `drive.lua` scancode vs ImGuiKey distinction | 15 min | Prevents test-side keycode confusion |
| **P3** | Add Begin/End balance tracking to ig.cpp | 30 min | Converts ImGui assertion crash to diagnostic |

---

## 6. Closing Assessment

The framework succeeds at its stated goal: it produces working native tools with good UX when guided by the skill files. The three evaluation projects demonstrate this. But the framework's *meta-goal* — enabling cheap LLMs to autonomously produce these tools without human debugging — is undermined by:

1. **Missing concrete recipes** for the hardest interaction pattern (modal state machines), causing models to fall back to buttons.
2. **No structural enforcement** of binding parity, keycode safety, or draw list lifetime, leaving classes of crash bugs detectable only at runtime on specific interaction paths.
3. **Incomplete scaffolding** that generates documentation but not buildable code.
4. **Asymmetric template maturity** that makes 3D projects second-class.

The P0 fixes (ImGuiKey guard, modal recipe, SDL3 pin) are small changes with outsized impact. They should be applied before the next LLM evaluation session.
