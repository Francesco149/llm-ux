// ig.cpp — ImGui 1.92 Lua Bindings and Drawlist API
#include "editor.h"
#include <cstdio>
#include <cstring>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

#include <imgui.h>

// ── Windows & Panels ─────────────────────────────────────────────────────────
static int l_ig_begin_window(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    bool open = true;
    ImGuiWindowFlags flags = (ImGuiWindowFlags)luaL_optinteger(L, 3, 0);
    bool res = ImGui::Begin(name, &open, flags);
    lua_pushboolean(L, res);
    return 1;
}

static int l_ig_end_window(lua_State* L) {
    ImGui::End();
    return 0;
}

static int l_ig_begin_child(lua_State* L) {
    const char* id = luaL_checkstring(L, 1);
    float w = (float)luaL_optnumber(L, 2, 0);
    float h = (float)luaL_optnumber(L, 3, 0);
    ImGuiChildFlags flags = (ImGuiChildFlags)luaL_optinteger(L, 4, 0);
    ImGuiWindowFlags wflags = (ImGuiWindowFlags)luaL_optinteger(L, 5, 0);
    bool res = ImGui::BeginChild(id, ImVec2(w, h), flags, wflags);
    lua_pushboolean(L, res);
    return 1;
}

static int l_ig_end_child(lua_State* L) {
    ImGui::EndChild();
    return 0;
}

// ── Layout & Positioning ────────────────────────────────────────────────────
static int l_ig_set_cursor_pos(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    ImGui::SetCursorPos(ImVec2(x, y));
    return 0;
}

static int l_ig_get_cursor_pos(lua_State* L) {
    ImVec2 p = ImGui::GetCursorPos();
    lua_pushnumber(L, p.x);
    lua_pushnumber(L, p.y);
    return 2;
}

static int l_ig_get_cursor_screen_pos(lua_State* L) {
    ImVec2 p = ImGui::GetCursorScreenPos();
    lua_pushnumber(L, p.x);
    lua_pushnumber(L, p.y);
    return 2;
}

static int l_ig_set_next_window_pos(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    ImGuiCond cond = (ImGuiCond)luaL_optinteger(L, 3, 0);
    ImGui::SetNextWindowPos(ImVec2(x, y), cond);
    return 0;
}

static int l_ig_set_next_window_size(lua_State* L) {
    float w = (float)luaL_checknumber(L, 1);
    float h = (float)luaL_checknumber(L, 2);
    ImGuiCond cond = (ImGuiCond)luaL_optinteger(L, 3, 0);
    ImGui::SetNextWindowSize(ImVec2(w, h), cond);
    return 0;
}

static int l_ig_set_next_item_width(lua_State* L) {
    float w = (float)luaL_checknumber(L, 1);
    ImGui::SetNextItemWidth(w);
    return 0;
}

static int l_ig_same_line(lua_State* L) {
    float offset_x = (float)luaL_optnumber(L, 1, 0.0f);
    float spacing = (float)luaL_optnumber(L, 2, -1.0f);
    ImGui::SameLine(offset_x, spacing);
    return 0;
}

static int l_ig_separator(lua_State* L) {
    ImGui::Separator();
    return 0;
}

static int l_ig_spacing(lua_State* L) {
    ImGui::Spacing();
    return 0;
}

static int l_ig_dummy(lua_State* L) {
    float w = (float)luaL_checknumber(L, 1);
    float h = (float)luaL_checknumber(L, 2);
    ImGui::Dummy(ImVec2(w, h));
    return 0;
}

static int l_ig_get_content_region_avail(lua_State* L) {
    ImVec2 sz = ImGui::GetContentRegionAvail();
    lua_pushnumber(L, sz.x);
    lua_pushnumber(L, sz.y);
    return 2;
}

// ── Widgets ──────────────────────────────────────────────────────────────────
static int l_ig_text(lua_State* L) {
    const char* str = luaL_checkstring(L, 1);
    ImGui::TextUnformatted(str);
    return 0;
}

static int l_ig_text_colored(lua_State* L) {
    const char* str = luaL_checkstring(L, 1);
    float r = (float)luaL_checknumber(L, 2);
    float g = (float)luaL_checknumber(L, 3);
    float b = (float)luaL_checknumber(L, 4);
    float a = (float)luaL_optnumber(L, 5, 1.0f);
    ImGui::TextColored(ImVec4(r, g, b, a), "%s", str);
    return 0;
}

static int l_ig_button(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float w = (float)luaL_optnumber(L, 2, 0.0f);
    float h = (float)luaL_optnumber(L, 3, 0.0f);
    lua_pushboolean(L, ImGui::Button(label, ImVec2(w, h)));
    return 1;
}

static int l_ig_small_button(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    lua_pushboolean(L, ImGui::SmallButton(label));
    return 1;
}

static int l_ig_invisible_button(lua_State* L) {
    const char* id = luaL_checkstring(L, 1);
    float w = (float)luaL_checknumber(L, 2);
    float h = (float)luaL_checknumber(L, 3);
    lua_pushboolean(L, ImGui::InvisibleButton(id, ImVec2(w, h)));
    return 1;
}

static int l_ig_selectable(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    bool selected = lua_toboolean(L, 2);
    ImGuiSelectableFlags flags = (ImGuiSelectableFlags)luaL_optinteger(L, 3, 0);
    float w = (float)luaL_optnumber(L, 4, 0);
    float h = (float)luaL_optnumber(L, 5, 0);
    lua_pushboolean(L, ImGui::Selectable(label, selected, flags, ImVec2(w, h)));
    return 1;
}

static int l_ig_checkbox(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    bool v = lua_toboolean(L, 2);
    bool changed = ImGui::Checkbox(label, &v);
    lua_pushboolean(L, changed);
    lua_pushboolean(L, v);
    return 2;
}

static int l_ig_slider_float(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float v = (float)luaL_checknumber(L, 2);
    float v_min = (float)luaL_checknumber(L, 3);
    float v_max = (float)luaL_checknumber(L, 4);
    const char* fmt = luaL_optstring(L, 5, "%.3f");
    bool changed = ImGui::SliderFloat(label, &v, v_min, v_max, fmt);
    lua_pushboolean(L, changed);
    lua_pushnumber(L, v);
    return 2;
}

static int l_ig_drag_float3(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float v[3] = {
        (float)luaL_checknumber(L, 2),
        (float)luaL_checknumber(L, 3),
        (float)luaL_checknumber(L, 4)
    };
    float speed = (float)luaL_optnumber(L, 5, 0.1f);
    bool changed = ImGui::DragFloat3(label, v, speed);
    lua_pushboolean(L, changed);
    lua_pushnumber(L, v[0]);
    lua_pushnumber(L, v[1]);
    lua_pushnumber(L, v[2]);
    return 4;
}

static int l_ig_color_edit3(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    float col[3] = {
        (float)luaL_checknumber(L, 2),
        (float)luaL_checknumber(L, 3),
        (float)luaL_checknumber(L, 4)
    };
    bool changed = ImGui::ColorEdit3(label, col);
    lua_pushboolean(L, changed);
    lua_pushnumber(L, col[0]);
    lua_pushnumber(L, col[1]);
    lua_pushnumber(L, col[2]);
    return 4;
}

// ── Popups & Tooltips ────────────────────────────────────────────────────────
static int l_ig_begin_tooltip(lua_State* L) {
    ImGui::BeginTooltip();
    return 0;
}

static int l_ig_end_tooltip(lua_State* L) {
    ImGui::EndTooltip();
    return 0;
}

static int l_ig_open_popup(lua_State* L) {
    const char* id = luaL_checkstring(L, 1);
    ImGui::OpenPopup(id);
    return 0;
}

static int l_ig_begin_popup(lua_State* L) {
    const char* id = luaL_checkstring(L, 1);
    lua_pushboolean(L, ImGui::BeginPopup(id));
    return 1;
}

static int l_ig_end_popup(lua_State* L) {
    ImGui::EndPopup();
    return 0;
}
static int l_ig_begin_popup_context_item(lua_State* L) {
    const char* id = luaL_optstring(L, 1, nullptr);
    ImGuiPopupFlags flags = (ImGuiPopupFlags)luaL_optinteger(L, 2, 1);
    lua_pushboolean(L, ImGui::BeginPopupContextItem(id, flags));
    return 1;
}

static int l_ig_begin_popup_context_window(lua_State* L) {
    const char* id = luaL_optstring(L, 1, nullptr);
    ImGuiPopupFlags flags = (ImGuiPopupFlags)luaL_optinteger(L, 2, 1);
    lua_pushboolean(L, ImGui::BeginPopupContextWindow(id, flags));
    return 1;
}


static int l_ig_menu_item(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    const char* shortcut = luaL_optstring(L, 2, nullptr);
    bool selected = lua_toboolean(L, 3);
    bool enabled = lua_isnoneornil(L, 4) ? true : lua_toboolean(L, 4);
    lua_pushboolean(L, ImGui::MenuItem(label, shortcut, selected, enabled));
    return 1;
}

// ── Input & State Queries ────────────────────────────────────────────────────
static int l_ig_is_item_hovered(lua_State* L) {
    lua_pushboolean(L, ImGui::IsItemHovered());
    return 1;
}

static int l_ig_is_item_active(lua_State* L) {
    lua_pushboolean(L, ImGui::IsItemActive());
    return 1;
}

static int l_ig_is_item_deactivated_after_edit(lua_State* L) {
    lua_pushboolean(L, ImGui::IsItemDeactivatedAfterEdit());
    return 1;
}

static int l_ig_is_mouse_down(lua_State* L) {
    int button = (int)luaL_optinteger(L, 1, 0);
    lua_pushboolean(L, ImGui::IsMouseDown(button));
    return 1;
}

static int l_ig_is_mouse_clicked(lua_State* L) {
    int button = (int)luaL_optinteger(L, 1, 0);
    lua_pushboolean(L, ImGui::IsMouseClicked(button));
    return 1;
}

static int l_ig_is_mouse_dragging(lua_State* L) {
    int button = (int)luaL_optinteger(L, 1, 0);
    float threshold = (float)luaL_optnumber(L, 2, -1.0f);
    lua_pushboolean(L, ImGui::IsMouseDragging(button, threshold));
    return 1;
}

static int l_ig_get_mouse_drag_delta(lua_State* L) {
    int button = (int)luaL_optinteger(L, 1, 0);
    float threshold = (float)luaL_optnumber(L, 2, -1.0f);
    ImVec2 d = ImGui::GetMouseDragDelta(button, threshold);
    lua_pushnumber(L, d.x);
    lua_pushnumber(L, d.y);
    return 2;
}

static int l_ig_reset_mouse_drag_delta(lua_State* L) {
    int button = (int)luaL_optinteger(L, 1, 0);
    ImGui::ResetMouseDragDelta(button);
    return 0;
}

static int l_ig_get_mouse_pos(lua_State* L) {
    ImVec2 p = ImGui::GetMousePos();
    lua_pushnumber(L, p.x);
    lua_pushnumber(L, p.y);
    return 2;
}

static int l_ig_is_key_down(lua_State* L) {
    int key = (int)luaL_checkinteger(L, 1);
    lua_pushboolean(L, ImGui::IsKeyDown((ImGuiKey)key));
    return 1;
}

static int l_ig_is_key_pressed(lua_State* L) {
    int key = (int)luaL_checkinteger(L, 1);
    lua_pushboolean(L, ImGui::IsKeyPressed((ImGuiKey)key));
    return 1;
}

static int l_ig_push_id(lua_State* L) {
    if (lua_isnumber(L, 1)) {
        ImGui::PushID((int)lua_tointeger(L, 1));
    } else {
        ImGui::PushID(luaL_checkstring(L, 1));
    }
    return 0;
}

static int l_ig_pop_id(lua_State* L) {
    ImGui::PopID();
    return 0;
}

// ── Drawlist API ─────────────────────────────────────────────────────────────
static int l_ig_dl_add_line(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float x2 = (float)luaL_checknumber(L, 3);
    float y2 = (float)luaL_checknumber(L, 4);
    float r = (float)luaL_checknumber(L, 5);
    float g = (float)luaL_checknumber(L, 6);
    float b = (float)luaL_checknumber(L, 7);
    float a = (float)luaL_optnumber(L, 8, 1.0f);
    float thickness = (float)luaL_optnumber(L, 9, 1.0f);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddLine(ImVec2(x1, y1), ImVec2(x2, y2), ImColor(r, g, b, a), thickness);
    return 0;
}

static int l_ig_dl_add_rect(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float x2 = (float)luaL_checknumber(L, 3);
    float y2 = (float)luaL_checknumber(L, 4);
    float r = (float)luaL_checknumber(L, 5);
    float g = (float)luaL_checknumber(L, 6);
    float b = (float)luaL_checknumber(L, 7);
    float a = (float)luaL_optnumber(L, 8, 1.0f);
    float rounding = (float)luaL_optnumber(L, 9, 0.0f);
    float thickness = (float)luaL_optnumber(L, 10, 1.0f);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddRect(ImVec2(x1, y1), ImVec2(x2, y2), ImColor(r, g, b, a), rounding, 0, thickness);
    return 0;
}

static int l_ig_dl_add_rect_filled(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float x2 = (float)luaL_checknumber(L, 3);
    float y2 = (float)luaL_checknumber(L, 4);
    float r = (float)luaL_checknumber(L, 5);
    float g = (float)luaL_checknumber(L, 6);
    float b = (float)luaL_checknumber(L, 7);
    float a = (float)luaL_optnumber(L, 8, 1.0f);
    float rounding = (float)luaL_optnumber(L, 9, 0.0f);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddRectFilled(ImVec2(x1, y1), ImVec2(x2, y2), ImColor(r, g, b, a), rounding);
    return 0;
}

static int l_ig_dl_add_triangle_filled(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float x2 = (float)luaL_checknumber(L, 3);
    float y2 = (float)luaL_checknumber(L, 4);
    float x3 = (float)luaL_checknumber(L, 5);
    float y3 = (float)luaL_checknumber(L, 6);
    float r = (float)luaL_checknumber(L, 7);
    float g = (float)luaL_checknumber(L, 8);
    float b = (float)luaL_checknumber(L, 9);
    float a = (float)luaL_optnumber(L, 10, 1.0f);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddTriangleFilled(ImVec2(x1, y1), ImVec2(x2, y2), ImVec2(x3, y3), ImColor(r, g, b, a));
    return 0;
}

static int l_ig_dl_add_text(lua_State* L) {
    float x = (float)luaL_checknumber(L, 1);
    float y = (float)luaL_checknumber(L, 2);
    float r = (float)luaL_checknumber(L, 3);
    float g = (float)luaL_checknumber(L, 4);
    float b = (float)luaL_checknumber(L, 5);
    float a = (float)luaL_optnumber(L, 6, 1.0f);
    const char* text = luaL_checkstring(L, 7);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddText(ImVec2(x, y), ImColor(r, g, b, a), text);
    return 0;
}

static int l_ig_dl_push_clip_rect(lua_State* L) {
    float x1 = (float)luaL_checknumber(L, 1);
    float y1 = (float)luaL_checknumber(L, 2);
    float x2 = (float)luaL_checknumber(L, 3);
    float y2 = (float)luaL_checknumber(L, 4);
    bool intersect = lua_toboolean(L, 5);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->PushClipRect(ImVec2(x1, y1), ImVec2(x2, y2), intersect);
    return 0;
}

static int l_ig_dl_pop_clip_rect(lua_State* L) {
    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->PopClipRect();
    return 0;
}

static int l_ig_get_io(lua_State* L) {
    ImGuiIO& io = ImGui::GetIO();
    lua_newtable(L);
    lua_pushnumber(L, io.DisplaySize.x); lua_setfield(L, -2, "display_w");
    lua_pushnumber(L, io.DisplaySize.y); lua_setfield(L, -2, "display_h");
    lua_pushnumber(L, io.DeltaTime); lua_setfield(L, -2, "delta_time");
    lua_pushnumber(L, io.MouseWheel); lua_setfield(L, -2, "mouse_wheel");
    lua_pushboolean(L, io.KeyCtrl); lua_setfield(L, -2, "key_ctrl");
    lua_pushboolean(L, io.KeyShift); lua_setfield(L, -2, "key_shift");
    lua_pushboolean(L, io.KeyAlt); lua_setfield(L, -2, "key_alt");
    return 1;
}

void register_ig_bindings(lua_State* L) {
    lua_newtable(L);

    lua_pushcfunction(L, l_ig_begin_window); lua_setfield(L, -2, "begin_window");
    lua_pushcfunction(L, l_ig_end_window); lua_setfield(L, -2, "end_window");
    lua_pushcfunction(L, l_ig_begin_child); lua_setfield(L, -2, "begin_child");
    lua_pushcfunction(L, l_ig_end_child); lua_setfield(L, -2, "end_child");
    lua_pushcfunction(L, l_ig_set_cursor_pos); lua_setfield(L, -2, "set_cursor_pos");
    lua_pushcfunction(L, l_ig_get_cursor_pos); lua_setfield(L, -2, "get_cursor_pos");
    lua_pushcfunction(L, l_ig_get_cursor_screen_pos); lua_setfield(L, -2, "get_cursor_screen_pos");
    lua_pushcfunction(L, l_ig_set_next_window_pos); lua_setfield(L, -2, "set_next_window_pos");
    lua_pushcfunction(L, l_ig_set_next_window_size); lua_setfield(L, -2, "set_next_window_size");
    lua_pushcfunction(L, l_ig_set_next_item_width); lua_setfield(L, -2, "set_next_item_width");
    lua_pushcfunction(L, l_ig_same_line); lua_setfield(L, -2, "same_line");
    lua_pushcfunction(L, l_ig_separator); lua_setfield(L, -2, "separator");
    lua_pushcfunction(L, l_ig_spacing); lua_setfield(L, -2, "spacing");
    lua_pushcfunction(L, l_ig_dummy); lua_setfield(L, -2, "dummy");
    lua_pushcfunction(L, l_ig_get_content_region_avail); lua_setfield(L, -2, "get_content_region_avail");

    lua_pushcfunction(L, l_ig_text); lua_setfield(L, -2, "text");
    lua_pushcfunction(L, l_ig_text_colored); lua_setfield(L, -2, "text_colored");
    lua_pushcfunction(L, l_ig_button); lua_setfield(L, -2, "button");
    lua_pushcfunction(L, l_ig_small_button); lua_setfield(L, -2, "small_button");
    lua_pushcfunction(L, l_ig_invisible_button); lua_setfield(L, -2, "invisible_button");
    lua_pushcfunction(L, l_ig_selectable); lua_setfield(L, -2, "selectable");
    lua_pushcfunction(L, l_ig_checkbox); lua_setfield(L, -2, "checkbox");
    lua_pushcfunction(L, l_ig_slider_float); lua_setfield(L, -2, "slider_float");
    lua_pushcfunction(L, l_ig_drag_float3); lua_setfield(L, -2, "drag_float3");
    lua_pushcfunction(L, l_ig_color_edit3); lua_setfield(L, -2, "color_edit3");

    lua_pushcfunction(L, l_ig_begin_tooltip); lua_setfield(L, -2, "begin_tooltip");
    lua_pushcfunction(L, l_ig_end_tooltip); lua_setfield(L, -2, "end_tooltip");
    lua_pushcfunction(L, l_ig_open_popup); lua_setfield(L, -2, "open_popup");
    lua_pushcfunction(L, l_ig_begin_popup); lua_setfield(L, -2, "begin_popup");
    lua_pushcfunction(L, l_ig_end_popup); lua_setfield(L, -2, "end_popup");
    lua_pushcfunction(L, l_ig_menu_item); lua_setfield(L, -2, "menu_item");
    lua_pushcfunction(L, l_ig_begin_popup_context_item); lua_setfield(L, -2, "begin_popup_context_item");
    lua_pushcfunction(L, l_ig_begin_popup_context_window); lua_setfield(L, -2, "begin_popup_context_window");

    lua_pushcfunction(L, l_ig_is_item_hovered); lua_setfield(L, -2, "is_item_hovered");
    lua_pushcfunction(L, l_ig_is_item_active); lua_setfield(L, -2, "is_item_active");
    lua_pushcfunction(L, l_ig_is_item_deactivated_after_edit); lua_setfield(L, -2, "is_item_deactivated_after_edit");
    lua_pushcfunction(L, l_ig_is_mouse_down); lua_setfield(L, -2, "is_mouse_down");
    lua_pushcfunction(L, l_ig_is_mouse_clicked); lua_setfield(L, -2, "is_mouse_clicked");
    lua_pushcfunction(L, l_ig_is_mouse_dragging); lua_setfield(L, -2, "is_mouse_dragging");
    lua_pushcfunction(L, l_ig_get_mouse_drag_delta); lua_setfield(L, -2, "get_mouse_drag_delta");
    lua_pushcfunction(L, l_ig_reset_mouse_drag_delta); lua_setfield(L, -2, "reset_mouse_drag_delta");
    lua_pushcfunction(L, l_ig_get_mouse_pos); lua_setfield(L, -2, "get_mouse_pos");
    lua_pushcfunction(L, l_ig_is_key_down); lua_setfield(L, -2, "is_key_down");
    lua_pushcfunction(L, l_ig_is_key_pressed); lua_setfield(L, -2, "is_key_pressed");
    lua_pushcfunction(L, l_ig_push_id); lua_setfield(L, -2, "push_id");
    lua_pushcfunction(L, l_ig_pop_id); lua_setfield(L, -2, "pop_id");

    lua_pushcfunction(L, l_ig_dl_add_line); lua_setfield(L, -2, "dl_add_line");
    lua_pushcfunction(L, l_ig_dl_add_rect); lua_setfield(L, -2, "dl_add_rect");
    lua_pushcfunction(L, l_ig_dl_add_rect_filled); lua_setfield(L, -2, "dl_add_rect_filled");
    lua_pushcfunction(L, l_ig_dl_add_triangle_filled); lua_setfield(L, -2, "dl_add_triangle_filled");
    lua_pushcfunction(L, l_ig_dl_add_text); lua_setfield(L, -2, "dl_add_text");
    lua_pushcfunction(L, l_ig_dl_push_clip_rect); lua_setfield(L, -2, "dl_push_clip_rect");
    lua_pushcfunction(L, l_ig_dl_pop_clip_rect); lua_setfield(L, -2, "dl_pop_clip_rect");
    lua_pushcfunction(L, l_ig_get_io); lua_setfield(L, -2, "get_io");
    // Key enum table
    lua_newtable(L);
    lua_pushinteger(L, ImGuiKey_Space); lua_setfield(L, -2, "Space");
    lua_pushinteger(L, ImGuiKey_F); lua_setfield(L, -2, "F");
    lua_pushinteger(L, ImGuiKey_Z); lua_setfield(L, -2, "Z");
    lua_pushinteger(L, ImGuiKey_Y); lua_setfield(L, -2, "Y");
    lua_pushinteger(L, ImGuiKey_D); lua_setfield(L, -2, "D");
    lua_pushinteger(L, ImGuiKey_E); lua_setfield(L, -2, "E");
    lua_pushinteger(L, ImGuiKey_Delete); lua_setfield(L, -2, "Delete");
    lua_pushinteger(L, ImGuiKey_Escape); lua_setfield(L, -2, "Escape");
    lua_setfield(L, -2, "Key");

    lua_setfield(L, -2, "ig");
}
