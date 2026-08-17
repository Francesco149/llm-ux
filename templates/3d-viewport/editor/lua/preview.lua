-- preview.lua — 3D Viewport with raycast click selection, 3D face extrusion gizmo, and paint stamping
local preview = {}
local ig = lp.ig
local doc = require("doc")
local theme = require("theme")
local paint = require("paint")
local mesh = require("mesh")
local undo = require("undo")

preview.cam = {
    target = { 0, 0, 0 },
    yaw = 45.0,
    pitch = 25.0,
    dist = 6.0,
    target_dist = 6.0,
    target_yaw = 45.0,
    target_pitch = 25.0,
    target_pos = { 0, 0, 0 },
    fov = 1.13446, -- 65 deg
    active_gizmo = nil,
    gizmo_drag_start = nil,
}

local function clamp(v, min_v, max_v)
    return math.max(min_v, math.min(max_v, v))
end

local function deg2rad(deg)
    return deg * 3.141592653589793 / 180.0
end

function preview.get_view_proj(vp_w, vp_h)
    local rad_yaw = deg2rad(preview.cam.yaw)
    local rad_pitch = deg2rad(preview.cam.pitch)

    local cx = preview.cam.target[1] + preview.cam.dist * math.cos(rad_pitch) * math.sin(rad_yaw)
    local cy = preview.cam.target[2] + preview.cam.dist * math.sin(rad_pitch)
    local cz = preview.cam.target[3] + preview.cam.dist * math.cos(rad_pitch) * math.cos(rad_yaw)

    local view = lp.math3d.lookat(cx, cy, cz,
        preview.cam.target[1], preview.cam.target[2], preview.cam.target[3],
        0, 1, 0)
    local proj = lp.math3d.perspective(preview.cam.fov, vp_w / math.max(1.0, vp_h), 0.1, 500.0)

    return view, proj, { cx, cy, cz }
end

function preview.frame(rect)
    ig.set_cursor_pos(0, 0)
    local avail_w, avail_h = ig.get_content_region_avail()
    local x0, y0 = ig.get_cursor_screen_pos()
    local io = ig.get_io()
    local dt = io.delta_time > 0 and io.delta_time or 0.016

    -- Camera damping lerp
    local lerp_factor = 1.0 - math.exp(-dt * 22.0)
    preview.cam.dist = preview.cam.dist + (preview.cam.target_dist - preview.cam.dist) * lerp_factor
    preview.cam.yaw = preview.cam.yaw + (preview.cam.target_yaw - preview.cam.yaw) * lerp_factor
    preview.cam.pitch = preview.cam.pitch + (preview.cam.target_pitch - preview.cam.pitch) * lerp_factor
    for i = 1, 3 do
        preview.cam.target[i] = preview.cam.target[i] + (preview.cam.target_pos[i] - preview.cam.target[i]) * lerp_factor
    end

    ig.invisible_button("##model_vp", avail_w, avail_h)
    local is_hovered = ig.is_item_hovered()
    local mx, my = ig.get_mouse_pos()

    local view, proj, cam_pos = preview.get_view_proj(avail_w, avail_h)

    local function world_to_screen(wx, wy, wz)
        local sx, sy, sz = lp.math3d.project(wx, wy, wz, view, proj, avail_w, avail_h)
        return x0 + sx, y0 + sy, sz
    end

    -- 1. Scroll Wheel Dolly
    if is_hovered and io.mouse_wheel ~= 0 then
        local factor = math.pow(1.15, -io.mouse_wheel)
        preview.cam.target_dist = clamp(preview.cam.target_dist * factor, 1.0, 100.0)
    end

    -- 2. Orbit Camera
    local is_orbit = (ig.is_mouse_dragging(2) and not io.key_shift) or (io.key_alt and ig.is_mouse_dragging(0))
    if is_hovered and is_orbit then
        local btn = ig.is_mouse_dragging(2) and 2 or 0
        local dx, dy = ig.get_mouse_drag_delta(btn, 0)
        preview.cam.target_yaw = preview.cam.target_yaw - dx * 0.4
        preview.cam.target_pitch = clamp(preview.cam.target_pitch + dy * 0.4, -89.0, 89.0)
        ig.reset_mouse_drag_delta(btn)
    end

    -- 3. Pan Camera
    local is_pan = (ig.is_mouse_dragging(2) and io.key_shift) or ((io.key_alt or ig.is_key_down(ig.key.Space)) and ig.is_mouse_dragging(0))
    if is_hovered and is_pan then
        local btn = ig.is_mouse_dragging(2) and 2 or 0
        local dx, dy = ig.get_mouse_drag_delta(btn, 0)
        local rad_yaw = deg2rad(preview.cam.yaw)
        local right_x = math.cos(rad_yaw)
        local right_z = -math.sin(rad_yaw)
        local pan_speed = preview.cam.dist * 0.0015

        preview.cam.target_pos[1] = preview.cam.target_pos[1] - right_x * dx * pan_speed
        preview.cam.target_pos[3] = preview.cam.target_pos[3] - right_z * dx * pan_speed
        preview.cam.target_pos[2] = preview.cam.target_pos[2] + dy * pan_speed
        ig.reset_mouse_drag_delta(btn)
    end

    -- 4. Focus Camera ('F')
    if is_hovered and ig.is_key_pressed(ig.key.F) then
        preview.cam.target_pos = { 0, 0, 0 }
        preview.cam.target_dist = 6.0
    end

    -- 5. 3D Raycast Click Selection on Faces
    if is_hovered and ig.is_mouse_clicked(0) and not io.key_alt and not ig.is_key_down(ig.key.Space) then
        if doc.mesh then
            local nearest_f = nil
            local nearest_t = 1e9
            for f_idx, f in ipairs(doc.mesh.faces) do
                if #f.verts >= 3 then
                    local v0 = doc.mesh.vertices[f.verts[1]].pos
                    local v1 = doc.mesh.vertices[f.verts[2]].pos
                    local v2 = doc.mesh.vertices[f.verts[3]].pos
                    local s0_x, s0_y, s0_z = world_to_screen(v0[1], v0[2], v0[3])
                    local s1_x, s1_y, s1_z = world_to_screen(v1[1], v1[2], v1[3])
                    local s2_x, s2_y, s2_z = world_to_screen(v2[1], v2[2], v2[3])

                    local function sign(p1x, p1y, p2x, p2y, p3x, p3y)
                        return (p1x - p3x) * (p2y - p3y) - (p2x - p3x) * (p1y - p3y)
                    end
                    local d1 = sign(mx, my, s0_x, s0_y, s1_x, s1_y)
                    local d2 = sign(mx, my, s1_x, s1_y, s2_x, s2_y)
                    local d3 = sign(mx, my, s2_x, s2_y, s0_x, s0_y)
                    local has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
                    local has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)

                    if not (has_neg and has_pos) and s0_z > 0 and s0_z < nearest_t then
                        nearest_t = s0_z
                        nearest_f = f_idx
                    end
                end
            end
            if nearest_f then
                doc.selected_face = nearest_f
            end
        end
    end

    -- DrawList 3D Rendering
    local dl = ig.get_window_draw_list()
    ig.dl_push_clip_rect(dl, x0, y0, x0 + avail_w, y0 + avail_h, true)
    ig.dl_add_rect_filled(dl, x0, y0, x0 + avail_w, y0 + avail_h, 0.09, 0.09, 0.11, 1.0)

    -- Ground Grid
    for i = -8, 8 do
        local alpha = (i % 4 == 0) and 0.20 or 0.07
        local x1, y1, z1 = world_to_screen(i, -1.0, -8)
        local x2, y2, z2 = world_to_screen(i, -1.0,  8)
        if z1 > 0 and z2 > 0 then
            ig.dl_add_line(dl, x1, y1, x2, y2, 0.7, 0.7, 0.8, alpha, 1.0)
        end
        local x3, y3, z3 = world_to_screen(-8, -1.0, i)
        local x4, y4, z4 = world_to_screen( 8, -1.0, i)
        if z3 > 0 and z4 > 0 then
            ig.dl_add_line(dl, x3, y3, x4, y4, 0.7, 0.7, 0.8, alpha, 1.0)
        end
    end

    -- Render 3D Model Mesh
    if doc.mesh then
        for f_idx, f in ipairs(doc.mesh.faces) do
            local is_selected = (f_idx == doc.selected_face)
            local pts = {}
            local all_front = true
            for _, vi in ipairs(f.verts) do
                local v = doc.mesh.vertices[vi]
                if v and v.pos then
                    local sx, sy, sz = world_to_screen(v.pos[1], v.pos[2], v.pos[3])
                    pts[#pts + 1] = { sx, sy, sz }
                    if sz <= 0 then all_front = false end
                end
            end

            if all_front and #pts >= 3 then
                local norm = f.normal or mesh.calculate_face_normal(doc.mesh, f)
                local nx, ny, nz = norm[1], norm[2], norm[3]
                local light_dot = math.max(0.15, nx * 0.5 + ny * 0.7 + nz * 0.5)

                local shade_r = is_selected and (theme.accent[1] * 0.9) or (0.45 * light_dot)
                local shade_g = is_selected and (theme.accent[2] * 0.9) or (0.50 * light_dot)
                local shade_b = is_selected and (theme.accent[3] * 0.9) or (0.60 * light_dot)

                -- Draw Triangles
                ig.dl_add_triangle_filled(dl, pts[1][1], pts[1][2], pts[2][1], pts[2][2], pts[3][1], pts[3][2],
                    shade_r, shade_g, shade_b, 0.95)
                if #pts == 4 then
                    ig.dl_add_triangle_filled(dl, pts[1][1], pts[1][2], pts[3][1], pts[3][2], pts[4][1], pts[4][2],
                        shade_r, shade_g, shade_b, 0.95)
                end

                -- Wireframe Edges
                local edge_r = is_selected and 1.0 or 0.28
                local edge_g = is_selected and 1.0 or 0.32
                local edge_b = is_selected and 1.0 or 0.40
                local thick = is_selected and 2.5 or 1.0

                for i = 1, #pts do
                    local next_i = (i % #pts) + 1
                    ig.dl_add_line(dl, pts[i][1], pts[i][2], pts[next_i][1], pts[next_i][2], edge_r, edge_g, edge_b, 0.85, thick)
                end

                -- 3D Face Extrusion / Normal Gizmo on selected face
                if is_selected then
                    local fc_x, fc_y, fc_z = 0, 0, 0
                    for _, vi in ipairs(f.verts) do
                        local vp = doc.mesh.vertices[vi].pos
                        fc_x = fc_x + vp[1]; fc_y = fc_y + vp[2]; fc_z = fc_z + vp[3]
                    end
                    fc_x = fc_x / #f.verts; fc_y = fc_y / #f.verts; fc_z = fc_z / #f.verts

                    local g_len = 1.0
                    local gn_x, gn_y, gn_z = world_to_screen(fc_x + nx * g_len, fc_y + ny * g_len, fc_z + nz * g_len)
                    local sc_x, sc_y, sc_z = world_to_screen(fc_x, fc_y, fc_z)

                    if sc_z > 0 then
                        -- Normal Extrude Arrow (Gold / Cyan)
                        ig.dl_add_line(dl, sc_x, sc_y, gn_x, gn_y, 1.0, 0.85, 0.2, 1.0, 3.5)
                        ig.dl_add_circle_filled(dl, gn_x, gn_y, 5.0, 1.0, 0.85, 0.2, 1.0)
                        ig.dl_add_text(dl, gn_x + 8, gn_y - 8, 1.0, 0.85, 0.2, 1.0, "Extrude (E)")
                    end
                end
            end
        end
    end

    -- Floating Viewport Header
    ig.set_cursor_pos(12, 12)
    ig.text_colored(string.format("Selected Face: #%d  ·  Faces: %d  ·  Verts: %d",
        doc.selected_face or 1, doc.mesh and #doc.mesh.faces or 0, doc.mesh and #doc.mesh.vertices or 0),
        theme.accent[1], theme.accent[2], theme.accent[3], 0.9)

    ig.dl_pop_clip_rect(dl)
end

return preview
