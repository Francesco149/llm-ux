# ImGui Lua Wrapper Design: Scoped API + Auto-Balance Safety Net

## Problem

ImGui has paired Begin/End calls with two different semantics:

### "Always End" pairs (must call End even if Begin returns false)
- `Begin` / `End` (windows)
- `BeginChild` / `EndChild`

### "Conditional End" pairs (call End ONLY when Begin returns true)
- `BeginPopup` / `EndPopup`
- `BeginPopupModal` / `EndPopup`
- `BeginPopupContextWindow` / `EndPopup`
- `BeginPopupContextItem` / `EndPopup`
- `BeginMenu` / `EndMenu`
- `BeginMenuBar` / `EndMenuBar`
- `BeginTable` / `EndTable`
- `BeginTabBar` / `EndTabBar`
- `BeginTabItem` / `EndTabItem`
- `BeginListBox` / `EndListBox`
- `TreeNode` / `TreePop`
- `BeginTooltip` / `EndTooltip`
- `BeginGroup` / `EndGroup`
- `BeginDisabled` / `EndDisabled`

LLMs (and humans) constantly:
1. Put EndChild inside `if begin_child then ... end` (skips End when collapsed)
2. Forget EndPopup entirely
3. Early-return from a panel function with unbalanced Begin/End
4. Put End calls in wrong scope after `pcall` catches an error

## Solution: Two Layers

### Layer 1: Scoped Lua Wrappers (primary API for LLMs)

Replace the error-prone pattern:
```lua
-- FRAGILE: Gemini will put end_child() inside the if, or forget it
if ig.begin_child("panel", w, h) then
    draw_stuff()
end
ig.end_child()
```

With callback-based scoped wrappers:
```lua
-- SAFE: end_child() always called, even on error
ig.child("panel", w, h, function(open)
    if open then
        draw_stuff()
    end
end)
```

Or even simpler for the common case (body only runs when open):
```lua
-- SIMPLEST: body only runs when Begin returns true, End always called
ig.child("panel", w, h, function()
    draw_stuff()
end)
```

The wrapper implementation (in C++, not Lua, for performance):
```cpp
// For "always end" pairs: callback always runs, End always called
static int l_child(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    float w = (float)luaL_optnumber(L, 2, 0);
    float h = (float)luaL_optnumber(L, 3, 0);
    // fn is arg 4 (no flags) or arg 6 (with flags)
    int fn_idx = lua_isfunction(L, 4) ? 4 : 6;
    ImGuiChildFlags cf = fn_idx > 4 ? (ImGuiChildFlags)luaL_optinteger(L, 4, 0) : 0;
    ImGuiWindowFlags wf = fn_idx > 5 ? (ImGuiWindowFlags)luaL_optinteger(L, 5, 0) : 0;
    luaL_checktype(L, fn_idx, LUA_TFUNCTION);

    bool open = ImGui::BeginChild(name, ImVec2(w, h), cf, wf);
    lua_pushvalue(L, fn_idx);
    if (open) {
        // Call fn() — body only runs when visible
        int err = lua_pcall(L, 0, 0, 0);
        ImGui::EndChild();
        if (err) return lua_error(L); // re-raise after End
    } else {
        ImGui::EndChild();
    }
    return 0;
}

// For "conditional end" pairs: body runs and End called only when Begin is true
static int l_popup(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    if (ImGui::BeginPopup(name)) {
        lua_pushvalue(L, 2);
        int err = lua_pcall(L, 0, 0, 0);
        ImGui::EndPopup();
        if (err) return lua_error(L);
    }
    return 0;
}
```

### Full Scoped API Surface

```lua
-- "Always End" wrappers (body runs only when open, End always called)
ig.window(name, flags, fn)         -- Begin/End
ig.child(name, w, h, fn)           -- BeginChild/EndChild
ig.child(name, w, h, cf, wf, fn)  -- with flags

-- "Conditional End" wrappers (body+End only when Begin true)
ig.popup(name, fn)                 -- BeginPopup/EndPopup
ig.popup_modal(name, flags, fn)    -- BeginPopupModal/EndPopup
ig.popup_context_window(id, flags, fn) -- BeginPopupContextWindow/EndPopup
ig.popup_context_item(id, flags, fn)   -- BeginPopupContextItem/EndPopup
ig.menu(name, fn)                  -- BeginMenu/EndMenu
ig.menu_bar(fn)                    -- BeginMenuBar/EndMenuBar
ig.table(name, cols, flags, fn)    -- BeginTable/EndTable
ig.tab_bar(name, flags, fn)        -- BeginTabBar/EndTabBar
ig.tab_item(name, flags, fn)       -- BeginTabItem/EndTabItem
ig.list_box(name, w, h, fn)       -- BeginListBox/EndListBox
ig.tree_node(name, flags, fn)     -- TreeNodeEx/TreePop
ig.tooltip(fn)                     -- BeginTooltip/EndTooltip
ig.group(fn)                       -- BeginGroup/EndGroup
ig.disabled(cond, fn)              -- BeginDisabled/EndDisabled
```

### Layer 2: C++ Auto-Balance Safety Net

Track Begin/End depth per category at the C++ level. At frame end, force-close
any unbalanced pairs with a logged warning.

```cpp
struct BalanceTracker {
    int window_depth = 0;   // Begin/End
    int child_depth = 0;    // BeginChild/EndChild
    int popup_depth = 0;    // BeginPopup*/EndPopup
    int menu_depth = 0;     // BeginMenu/EndMenu
    int table_depth = 0;    // BeginTable/EndTable
    // etc.
};

static BalanceTracker g_balance;

// Called at end of lua_frame():
void ig_balance_check() {
    while (g_balance.child_depth > 0) {
        fprintf(stderr, "[ig] WARNING: force-closing unbalanced EndChild()\n");
        ImGui::EndChild();
        g_balance.child_depth--;
    }
    while (g_balance.popup_depth > 0) {
        fprintf(stderr, "[ig] WARNING: force-closing unbalanced EndPopup()\n");
        ImGui::EndPopup();
        g_balance.popup_depth--;
    }
    // ... etc for each category
    while (g_balance.window_depth > 0) {
        fprintf(stderr, "[ig] WARNING: force-closing unbalanced End()\n");
        ImGui::End();
        g_balance.window_depth--;
    }
}
```

## Migration Path

The raw `begin_child`/`end_child` functions remain available for edge cases,
but the scoped `ig.child(name, w, h, fn)` is the recommended API. Skills and
templates should use ONLY the scoped forms. The raw forms become "escape hatch"
for advanced patterns.

## Impact on LLM Code Generation

Before (fragile):
```lua
function panels.render()
    ig.begin("##main", flags)
    if ig.begin_child("##toolbar", dw, 36) then
        -- toolbar content
    end
    ig.end_child()  -- LLM forgets this, or puts it in wrong scope
    if ig.begin_child("##left", 250, body_h) then
        if ig.begin_popup_context_window("ctx") then
            -- menu items
            ig.end_popup()  -- LLM forgets this
        end
    end
    ig.end_child()  -- LLM puts this inside the if
    ig.end_()
end
```

After (safe):
```lua
function panels.render()
    ig.window("##main", flags, function()
        ig.child("##toolbar", dw, 36, function()
            -- toolbar content
        end)
        ig.child("##left", 250, body_h, function()
            ig.popup_context_window("ctx", 0, function()
                -- menu items
            end)
        end)
    end)
end
```

The callback nesting makes the scope visually obvious and structurally
impossible to get wrong. The pcall inside each wrapper means errors in one
panel don't crash the frame — they just skip that panel and properly close it.
