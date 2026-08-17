-- panels.lua — Tiled UI layout with direct manipulation controls for lowpoly-painter
local panels = {}
local ig = lp.ig
local doc = require("doc")
local theme = require("theme")
local ui = require("ui")
local mesh = require("mesh")
local uv = require("uv")
local bake = require("bake")
local export = require("export")
local undo = require("undo")
local preview = require("preview")

panels.left_w = 230
panels.right_w = 290
local TOP_H = 36

function panels.render()
    local io = ig.get_io()
    local dw, dh = io.display_w, io.display_h

    local MAIN_FLAGS = 1 + 2 + 4 + 8 + 32 + 512
    ig.set_next_window_pos(0, 0)
    ig.set_next_window_size(dw, dh)
    ig.begin("##main", MAIN_FLAGS)

    -- ── 1. Top Toolbar ───────────────────────────────────────────────────────
    ig.set_next_window_pos(0, 0)
    ig.set_next_window_size(dw, TOP_H)
    if ig.begin_child("##top_toolbar", dw, TOP_H, 0, 0) then
        ig.set_cursor_pos(10, 6)
        ig.text_colored("lowpoly-painter", theme.accent[1], theme.accent[2], theme.accent[3], 1.0)

        ig.same_line(140)
        -- Mode Selection Pills
        if ig.selectable("1 Vert", doc.sel_mode == "vertex", 0, 50, 24) then doc.sel_mode = "vertex" end
        ui.tooltip("Vertex Selection Mode", "1", "Select individual vertices in 3D")

        ig.same_line()
        if ig.selectable("2 Edge", doc.sel_mode == "edge", 0, 50, 24) then doc.sel_mode = "edge" end
        ui.tooltip("Edge Selection Mode", "2", "Select mesh edges in 3D")

        ig.same_line()
        if ig.selectable("3 Face", doc.sel_mode == "face", 0, 50, 24) then doc.sel_mode = "face" end
        ui.tooltip("Face Selection Mode", "3", "Select polygon faces in 3D")

        ig.same_line(320)
        if ig.button("+ Cube") then
            doc.mutate(function() doc.mesh = mesh.create_cube(2, 2, 2) end, "New Cube")
        end
        ui.tooltip("New Cube", nil, "Creates 2x2 low-poly cube")

        ig.same_line()
        if ig.button("Auto UVs") then
            if doc.mesh then
                doc.mutate(function() uv.auto_unwrap(doc.mesh, doc.tex_w, 4.0) end, "Auto Unwrap UVs")
            end
        end
        ui.tooltip("Auto Unwrap UVs", "U", "Automatically packs face UV islands")

        ig.same_line(460)
        if ig.button("Undo") then undo.do_undo() end
        ui.tooltip("Undo", "Ctrl+Z", "Revert last change")

        ig.same_line()
        if ig.button("Redo") then undo.do_redo() end
        ui.tooltip("Redo", "Ctrl+Y", "Reapply change")

        ig.same_line(dw - 180)
        if ig.button("Export 3D Model (.obj)") then
            local path = "build/" .. doc.name .. ".obj"
            export.save_obj(path)
            lp.app.log("Exported model to " .. path)
        end
        ui.tooltip("Export OBJ", "Ctrl+E", "Exports 3D mesh with UVs and MTL")
    end
    ig.end_child()

    local body_h = dh - TOP_H

    -- ── 2. Left Panel: Face / Mesh Hierarchy ─────────────────────────────────
    ig.set_next_window_pos(0, TOP_H)
    ig.set_next_window_size(panels.left_w, body_h)
    if ig.begin_child("##left_panel", panels.left_w, body_h, 0, 0) then
        ig.set_cursor_pos(8, 6)
        ig.text("Mesh Hierarchy")
        ig.separator()

        if doc.mesh then
            for i = 1, #doc.mesh.faces do
                ig.push_id(i)
                local is_selected = (i == doc.selected_face)
                if ig.selectable("Face #" .. i, is_selected) then
                    doc.selected_face = i
                end
                ig.pop_id()
            end
        end
    end
    ig.end_child()

    -- ── 3. Right Panel: Shading & Texture Controls ───────────────────────────
    local rx = dw - panels.right_w
    ig.set_next_window_pos(rx, TOP_H)
    ig.set_next_window_size(panels.right_w, body_h)
    if ig.begin_child("##right_panel", panels.right_w, body_h, 0, 0) then
        ig.set_cursor_pos(8, 6)
        ig.text("Paint & Shading")
        ig.separator()

        ig.text("Direct Hotkeys:")
        ig.text_colored("  [G] Grab / Move Face", 0.7, 0.75, 0.85, 1.0)
        ig.text_colored("  [E] Extrude Face Normal", 0.7, 0.75, 0.85, 1.0)
        ig.text_colored("  [S] Scale Face", 0.7, 0.75, 0.85, 1.0)
        ig.text_colored("  [F] Focus Camera", 0.7, 0.75, 0.85, 1.0)

        ig.separator()
        ig.text("Brush Settings:")
        ui.undoable_slider_float("Radius", doc.brush_radius, 1.0, 64.0, function(v)
            doc.brush_radius = v
        end)
        ui.undoable_slider_float("Hardness", doc.brush_hardness, 0.0, 1.0, function(v)
            doc.brush_hardness = v
        end)

        ig.spacing()
        ui.undoable_color3("Brush Color", doc.brush_color, function(c)
            doc.brush_color = c
        end)

        ig.separator()
        ig.text("Procedural Baked Effects:")
        if ig.button("Bake Height Gradient", panels.right_w - 24, 28) then
            bake.vertical_gradient({ 0.9, 0.95, 1.0 }, { 0.2, 0.25, 0.35 })
        end
        ui.tooltip("Bake Gradient Ramp", nil, "Applies smooth stylized vertical height shading")

        if ig.button("Fill Base Color", panels.right_w - 24, 28) then
            local r = math.floor(doc.brush_color[1] * 255)
            local g = math.floor(doc.brush_color[2] * 255)
            local b = math.floor(doc.brush_color[3] * 255)
            lp.tex.clear(doc.texture, (r << 24) | (g << 16) | (b << 8) | 0xFF)
            doc.mark_dirty()
        end
    end
    ig.end_child()

    -- ── 4. Center 3D Viewport ────────────────────────────────────────────────
    local center_x = panels.left_w
    local center_w = dw - panels.left_w - panels.right_w
    ig.set_next_window_pos(center_x, TOP_H)
    ig.set_next_window_size(center_w, body_h)
    if ig.begin_child("##center_vp", center_w, body_h, 0, 0) then
        preview.frame({ x = center_x, y = TOP_H, w = center_w, h = body_h })
    end
    ig.end_child()

    ig.end_()
end

return panels
