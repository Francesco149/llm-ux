-- test_binding_parity.lua — Verify all expected C++ bindings are registered in Lua
-- Catches the class of bug where a C++ l_foo() function exists but is missing
-- from the REG(...) registration table, making it nil in Lua.

print("== test_binding_parity ==")

local ig = lp.ig

-- Core ImGui bindings that MUST be available
local required_ig = {
    -- Window
    "begin", "end_", "begin_child", "end_child",
    -- Layout
    "same_line", "separator", "spacing", "dummy",
    "set_cursor_pos", "get_cursor_pos", "get_cursor_screen_pos",
    "get_content_region_avail", "indent", "unindent",
    -- Widgets
    "text", "text_colored", "text_wrapped", "button", "small_button",
    "checkbox", "radio_button",
    "slider_float", "slider_int", "drag_float", "drag_int",
    "input_text", "input_float", "input_int",
    "color_edit3", "color_edit4", "color_picker3", "color_picker4",
    "selectable", "combo",
    -- Trees / Collapsing
    "tree_node", "tree_pop", "collapsing_header",
    -- Popups / Menus
    "begin_popup", "end_popup", "open_popup",
    "begin_popup_context_window", "begin_popup_context_item",
    "begin_menu_bar", "end_menu_bar", "begin_menu", "end_menu", "menu_item",
    -- Tables
    "begin_table", "end_table", "table_next_row",
    "table_next_column", "table_set_column_index",
    -- Tabs
    "begin_tab_bar", "end_tab_bar", "begin_tab_item", "end_tab_item",
    -- ID
    "push_id", "pop_id",
    -- Style
    "push_style_color", "pop_style_color",
    "push_style_var", "pop_style_var",
    -- Input State
    "is_item_hovered", "is_item_active", "is_item_clicked",
    "is_item_deactivated_after_edit",
    "is_mouse_clicked", "is_mouse_down", "is_mouse_dragging",
    "is_mouse_released",
    "get_mouse_pos", "get_mouse_drag_delta", "reset_mouse_drag_delta",
    "is_key_pressed", "is_key_down",
    "invisible_button",
    -- IO
    "get_io",
    -- DrawList
    "get_window_draw_list", "get_foreground_draw_list",
    "dl_add_line", "dl_add_rect", "dl_add_rect_filled",
    "dl_add_circle", "dl_add_circle_filled",
    "dl_add_triangle_filled",
    "dl_add_text",
    "dl_push_clip_rect", "dl_pop_clip_rect",
    -- Window state
    "get_window_pos", "get_window_size",
    "set_next_window_pos", "set_next_window_size",
    "set_next_window_bg_alpha",
    -- Utility
    "calc_text_size",
    -- Font
    "push_font", "pop_font",
}

local missing = {}
for _, name in ipairs(required_ig) do
    if type(ig[name]) ~= "function" then
        missing[#missing + 1] = "ig." .. name
    end
end

-- Verify key table exists and has essential keys
assert(ig.key, "ig.key table must exist")
local required_keys = {
    "Space", "Enter", "Escape", "Delete", "Backspace", "Tab",
    "A", "B", "C", "D", "E", "F", "G", "H", "R", "S", "V", "X", "Y", "Z",
}
for _, k in ipairs(required_keys) do
    if not ig.key[k] then
        missing[#missing + 1] = "ig.key." .. k
    elseif ig.key[k] < 500 then
        missing[#missing + 1] = "ig.key." .. k .. " (value " .. ig.key[k] .. " < 500, not a valid ImGuiKey)"
    end
end

-- Verify math3d bindings
if lp.math3d then
    local required_math3d = {
        "lookat", "perspective", "project", "ray_triangle",
    }
    for _, name in ipairs(required_math3d) do
        if type(lp.math3d[name]) ~= "function" then
            missing[#missing + 1] = "lp.math3d." .. name
        end
    end
end

if #missing > 0 then
    print("FAIL: Missing " .. #missing .. " required bindings:")
    for _, m in ipairs(missing) do
        print("  MISSING: " .. m)
    end
    error("Binding parity check failed")
end

print(string.format("  Verified %d ig bindings + %d keys + math3d. All present.",
    #required_ig, #required_keys))
