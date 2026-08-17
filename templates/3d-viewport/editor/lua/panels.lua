-- panels.lua — Tiled UI layout: Toolbar, Scene Hierarchy, Inspector, and Viewport
local panels = {}
local ig = gb.ig
local doc = require("doc")
local theme = require("theme")
local ui = require("ui")
local preview = require("preview")
local export_godot = require("export_godot")
local undo = require("undo")

panels.left_w = 260
panels.right_w = 280
local TOP_H = 36

function panels.render()
    local io = ig.get_io()
    local dw, dh = io.display_w, io.display_h
    local MAIN_FLAGS = 1 + 2 + 4 + 8 + 32 + 512
    ig.set_next_window_pos(0, 0)
    ig.set_next_window_size(dw, dh)
    ig.begin_window("##main", true, MAIN_FLAGS)
    -- ── 1. Top Toolbar ───────────────────────────────────────────────────────
    ig.set_next_window_pos(0, 0)
    ig.set_next_window_size(dw, TOP_H)
    if ig.begin_child("##top_toolbar", dw, TOP_H, 0, 0) then
        ig.set_cursor_pos(10, 6)
        ig.text_colored("godot-blockout", theme.accent[1], theme.accent[2], theme.accent[3], 1.0)

        ig.same_line(140)
        if ig.button("+ Box") then
            doc.mutate(function()
                local b = doc.new_brush("box", nil, { 0, 1, 0 }, { 2, 2, 2 })
                doc.add_brush(b)
            end, "Add Box")
        end
        ui.tooltip("Add Box Primitive", "B", "Creates a 2x2x2 CSG Box")

        ig.same_line()
        if ig.button("+ Cylinder") then
            doc.mutate(function()
                local b = doc.new_brush("cylinder", nil, { 0, 1, 0 }, { 2, 2, 2 })
                doc.add_brush(b)
            end, "Add Cylinder")
        end
        ui.tooltip("Add Cylinder Primitive", "C", "Creates a CSG Cylinder")

        ig.same_line()
        if ig.button("+ Wedge") then
            doc.mutate(function()
                local b = doc.new_brush("wedge", nil, { 0, 1, 0 }, { 2, 2, 2 })
                doc.add_brush(b)
            end, "Add Wedge")
        end
        ui.tooltip("Add Wedge / Ramp Primitive", "R", "Creates a slope ramp")

        ig.same_line()
        if ig.button("+ Stairs") then
            doc.mutate(function()
                local b = doc.new_brush("stairs", nil, { 0, 1, 0 }, { 2, 2, 2 })
                doc.add_brush(b)
            end, "Add Stairs")
        end
        ui.tooltip("Add Stairs Primitive", nil, "Creates 4-step CSG stairs")

        ig.same_line(390)
        if ig.button("Undo") then undo.do_undo() end
        ui.tooltip("Undo", "Ctrl+Z", "Revert last change")

        ig.same_line()
        if ig.button("Redo") then undo.do_redo() end
        ui.tooltip("Redo", "Ctrl+Y", "Reapply change")

        ig.same_line(dw - 190)
        if ig.button("Export Godot 4 (.tscn)") then
            local path = "build/" .. doc.name .. ".tscn"
            export_godot.save_tscn(path)
            gb.app.log("Exported Godot scene to " .. path)
        end
        ui.tooltip("1-Click Godot Export", "Ctrl+E", "Generates Godot 4 .tscn with collisions")
    end
    ig.end_child()

    local body_h = dh - TOP_H

    -- ── 2. Left Panel: Scene Tree Hierarchy ──────────────────────────────────
    ig.set_next_window_pos(0, TOP_H)
    ig.set_next_window_size(panels.left_w, body_h)
    if ig.begin_child("##left_panel", panels.left_w, body_h, 0, 0) then
        ig.set_cursor_pos(8, 6)
        ig.text("Scene Hierarchy")
        ig.separator()

        for i = #doc.brushes, 1, -1 do
            local b = doc.brushes[i]
            ig.push_id(b.id)

            local eye = b.visible and "👁" or " "
            if ig.small_button(eye .. "##vis") then
                b.visible = not b.visible
                doc.mark_dirty()
            end
            ui.tooltip("Toggle Visibility", nil, "Show / hide brush in viewport")

            ig.same_line()
            local is_selected = (b.id == doc.selected_id)
            local op_tag = (b.op == "subtract") and " [-]" or " [+]"
            if ig.selectable(b.name .. op_tag .. "##sel", is_selected) then
                doc.selected_id = b.id
            end

            -- Context menu
            if ig.begin_popup_context_item() then
                if ig.menu_item("Duplicate", "Ctrl+D") then
                    doc.duplicate_brush(b.id)
                end
                if ig.menu_item("Delete", "Del") then
                    doc.remove_brush(b.id)
                end
                ig.end_popup()
            end

            ig.pop_id()
        end
    end
    ig.end_child()

    -- ── 3. Right Panel: Inspector Properties ─────────────────────────────────
    local rx = dw - panels.right_w
    ig.set_next_window_pos(rx, TOP_H)
    ig.set_next_window_size(panels.right_w, body_h)
    if ig.begin_child("##right_panel", panels.right_w, body_h, 0, 0) then
        ig.set_cursor_pos(8, 6)
        ig.text("Brush Properties")
        ig.separator()

        local sel = doc.get_brush(doc.selected_id)
        if sel then
            ig.text("Name: " .. sel.name)
            ig.text("Type: " .. sel.type:upper())

            ig.spacing()
            ig.text("CSG Operation:")
            if ig.selectable("Union (Additive)", sel.op == "union") then
                doc.mutate(function() sel.op = "union" end, "Set Union")
            end
            if ig.selectable("Subtract (Carve)", sel.op == "subtract") then
                doc.mutate(function() sel.op = "subtract" end, "Set Subtract")
            end
            if ig.selectable("Intersection", sel.op == "intersect") then
                doc.mutate(function() sel.op = "intersect" end, "Set Intersect")
            end

            ig.separator()
            ig.text("Transform:")
            ui.undoable_drag3("Position", sel.pos, 0.05, function(v)
                sel.pos = v
                doc.mark_dirty()
            end, function()
                undo.push("Move Brush")
            end)

            ui.undoable_drag3("Size", sel.size, 0.05, function(v)
                sel.size = { math.max(0.1, v[1]), math.max(0.1, v[2]), math.max(0.1, v[3]) }
                doc.mark_dirty()
            end, function()
                undo.push("Resize Brush")
            end)

            ig.separator()
            ig.text("Appearance:")
            ui.undoable_color3("Color", sel.color, function(c)
                sel.color = c
                doc.mark_dirty()
            end, function()
                undo.push("Color Brush")
            end)

            ig.spacing()
            if ig.button("Duplicate Brush (Ctrl+D)", panels.right_w - 24, 26) then
                doc.duplicate_brush(sel.id)
            end
            if ig.button("Delete Brush (Del)", panels.right_w - 24, 26) then
                doc.remove_brush(sel.id)
            end
        else
            ig.text_colored("Select a brush to inspect properties.", 0.5, 0.5, 0.55, 1.0)
        end
    end
    ig.end_child()

    -- ── 4. Center 3D Viewport ────────────────────────────────────────────────
    local center_x = panels.left_w
    local center_w = dw - panels.left_w - panels.right_w
    ig.set_next_window_pos(center_x, TOP_H)
    ig.set_next_window_size(center_w, body_h)
    if ig.begin_child("##center_viewport", center_w, body_h, 0, 0) then
        preview.frame({ x = center_x, y = TOP_H, w = center_w, h = body_h })
    end
    ig.end_child()
    ig.end_window()
end

return panels
