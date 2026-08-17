-- panels.lua — Tiled UI layout with direct manipulation controls and 2D UV inspector for lowpoly-painter
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

panels.left_w = 250
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

        ig.same_line()
        ig.spacing()
        ig.same_line()

        -- Mode Selection Pills
        local is_vert = (doc.sel_mode == "vertex")
        if is_vert then ig.push_style_color(ig.col.Button, theme.accent[1], theme.accent[2], theme.accent[3], 0.85) end
        if ig.button("1 Vert") then doc.sel_mode = "vertex" end
        if is_vert then ig.pop_style_color(1) end
        ui.tooltip("Vertex Mode", "1", "Select and manipulate vertices in 3D")

        ig.same_line()
        local is_edge = (doc.sel_mode == "edge")
        if is_edge then ig.push_style_color(ig.col.Button, theme.accent[1], theme.accent[2], theme.accent[3], 0.85) end
        if ig.button("2 Edge") then doc.sel_mode = "edge" end
        if is_edge then ig.pop_style_color(1) end
        ui.tooltip("Edge Mode", "2", "Select and manipulate edges in 3D")

        ig.same_line()
        local is_face = (doc.sel_mode == "face")
        if is_face then ig.push_style_color(ig.col.Button, theme.accent[1], theme.accent[2], theme.accent[3], 0.85) end
        if ig.button("3 Face") then doc.sel_mode = "face" end
        if is_face then ig.pop_style_color(1) end
        ui.tooltip("Face Mode", "3", "Select, Move (G), Scale (S), and Extrude (E) faces")

        ig.same_line()
        local is_paint = (doc.sel_mode == "paint")
        if is_paint then ig.push_style_color(ig.col.Button, theme.accent[1], theme.accent[2], theme.accent[3], 0.85) end
        if ig.button("4 Paint") then doc.sel_mode = "paint" end
        if is_paint then ig.pop_style_color(1) end
        ui.tooltip("3D Paint Mode", "4 / B", "Left-drag directly in 3D viewport to stamp texture paint")

        ig.same_line()
        ig.text_colored("|", 0.35, 0.35, 0.4, 1.0)

        ig.same_line()
        if ig.button("+ Cube") then
            doc.mutate(function()
                doc.mesh = mesh.create_cube(2, 2, 2)
                uv.auto_unwrap(doc.mesh, doc.tex_w, 4.0)
            end, "New Cube")
        end
        ui.tooltip("New Cube Primitive", nil, "Creates 2x2x2 cube with auto UVs")

        ig.same_line()
        if ig.button("Auto UVs") then
            if doc.mesh then
                doc.mutate(function() uv.auto_unwrap(doc.mesh, doc.tex_w, 4.0) end, "Auto Unwrap UVs")
            end
        end
        ui.tooltip("Auto Unwrap UVs", "U", "Automatically packs face UV islands")

        ig.same_line()
        ig.text_colored("|", 0.35, 0.35, 0.4, 1.0)

        ig.same_line()
        if ig.button("Undo") then undo.do_undo() end
        ui.tooltip("Undo", "Ctrl+Z", "Revert last change")

        ig.same_line()
        if ig.button("Redo") then undo.do_redo() end
        ui.tooltip("Redo", "Ctrl+Y", "Reapply change")

        ig.same_line(dw - 185)
        if ig.button("Export Model (.obj)") then
            local path = "build/" .. doc.name .. ".obj"
            export.save_obj(path)
            lp.app.log("Exported model to " .. path)
        end
        ui.tooltip("Export OBJ", "Ctrl+E", "Exports 3D mesh with UVs and MTL")
    end
    ig.end_child()

    local body_h = dh - TOP_H

    -- ── 2. Left Panel: Scene Hierarchy & 2D UV Inspector ────────────────────
    ig.set_next_window_pos(0, TOP_H)
    ig.set_next_window_size(panels.left_w, body_h)
    if ig.begin_child("##left_panel", panels.left_w, body_h, 0, 0) then
        ig.set_cursor_pos(8, 6)
        ig.text("Mesh Hierarchy")
        ig.separator()

        local list_h = math.max(100, body_h - 260)
        if ig.begin_child("##mesh_list", panels.left_w - 16, list_h, 1, 0) then
            if doc.mesh then
                for i = 1, #doc.mesh.faces do
                    ig.push_id(i)
                    local is_selected = (doc.sel_mode == "face" and i == doc.selected_face)
                    if ig.selectable("Face #" .. i, is_selected) then
                        doc.selected_face = i
                        doc.sel_mode = "face"
                    end
                    ig.pop_id()
                end
            end
        end
        ig.end_child()

        ig.spacing()
        ig.separator()
        ig.text("UV Map Inspector (Read-Only)")
        ig.text_colored("Auto-packed UV islands:", 0.55, 0.58, 0.65, 1.0)

        -- 2D UV Preview Box
        local uv_box_size = panels.left_w - 24
        local uv_p0_x, uv_p0_y = ig.get_cursor_screen_pos()
        ig.dummy(uv_box_size, uv_box_size)

        local dl = ig.get_window_draw_list()
        -- Background container
        ig.dl_add_rect_filled(dl, uv_p0_x, uv_p0_y, uv_p0_x + uv_box_size, uv_p0_y + uv_box_size, 0.12, 0.13, 0.16, 1.0, 4.0)
        ig.dl_add_rect(dl, uv_p0_x, uv_p0_y, uv_p0_x + uv_box_size, uv_p0_y + uv_box_size, 0.25, 0.28, 0.35, 1.0, 4.0)

        -- Draw Wireframe UV Islands
        if doc.mesh and #doc.mesh.faces > 0 then
            for f_idx, f in ipairs(doc.mesh.faces) do
                local is_sel_f = (doc.sel_mode == "face" and f_idx == doc.selected_face)
                local ur = is_sel_f and theme.accent[1] or 0.35
                local ug = is_sel_f and theme.accent[2] or 0.65
                local ub = is_sel_f and theme.accent[3] or 0.85
                local u_thick = is_sel_f and 2.0 or 1.0

                local cx_uv, cy_uv = 0, 0
                for i = 1, #f.verts do
                    local next_i = (i % #f.verts) + 1
                    local v1 = doc.mesh.vertices[f.verts[i]]
                    local v2 = doc.mesh.vertices[f.verts[next_i]]
                    if v1 and v2 and v1.uv and v2.uv then
                        local px1 = uv_p0_x + v1.uv[1] * uv_box_size
                        local py1 = uv_p0_y + v1.uv[2] * uv_box_size
                        local px2 = uv_p0_x + v2.uv[1] * uv_box_size
                        local py2 = uv_p0_y + v2.uv[2] * uv_box_size
                        ig.dl_add_line(dl, px1, py1, px2, py2, ur, ug, ub, 0.9, u_thick)
                        cx_uv = cx_uv + v1.uv[1]
                        cy_uv = cy_uv + v1.uv[2]
                    end
                end
                if #f.verts > 0 then
                    cx_uv = uv_p0_x + (cx_uv / #f.verts) * uv_box_size - 4
                    cy_uv = uv_p0_y + (cy_uv / #f.verts) * uv_box_size - 5
                    ig.dl_add_text(dl, cx_uv, cy_uv, ur, ug, ub, 0.85, tostring(f_idx))
                end
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
        ig.text_colored("  [1/2/3/4] Vert / Edge / Face / Paint", 0.7, 0.75, 0.85, 1.0)
        ig.text_colored("  [G] Move Selection", 0.7, 0.75, 0.85, 1.0)
        ig.text_colored("  [E] Extrude Face Normal", 0.7, 0.75, 0.85, 1.0)
        ig.text_colored("  [S] Scale Selection", 0.7, 0.75, 0.85, 1.0)
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
        ig.text("Texture Actions:")
        if ig.button("Fill Base Color", panels.right_w - 24, 28) then
            local r = math.floor(doc.brush_color[1] * 255)
            local g = math.floor(doc.brush_color[2] * 255)
            local b = math.floor(doc.brush_color[3] * 255)
            local col32 = (r << 24) | (g << 16) | (b << 8) | 0xFF
            if doc.texture and lp and lp.tex then
                lp.tex.clear(doc.texture, col32)
                doc.mark_dirty()
            end
        end
        ui.tooltip("Fill Entire Texture", nil, "Fills the entire 256x256 texture map with the active brush color")

        ig.spacing()
        ig.text("Procedural Baked Effects:")
        if ig.button("Bake Height Gradient", panels.right_w - 24, 28) then
            bake.vertical_gradient({ 0.9, 0.95, 1.0 }, { 0.2, 0.25, 0.35 })
        end
        ui.tooltip("Bake Gradient Ramp", nil, "Applies smooth stylized vertical height shading")
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
