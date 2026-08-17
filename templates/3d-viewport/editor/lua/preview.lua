-- preview.lua — 3D Viewport with Godot-grade camera controls, 3D grid, and direct manipulation gizmo
local preview = {}
local ig = gb.ig
local doc = require("doc")
local theme = require("theme")

preview.cam = {
    target = { 0, 1, 0 },
    yaw = 45.0,
    pitch = 30.0,
    dist = 8.0,
    target_dist = 8.0,
    target_yaw = 45.0,
    target_pitch = 30.0,
    target_pos = { 0, 1, 0 },
    fov = 1.13446, -- ~65 degrees in radians
    fly_mode = false,
    gizmo_axis = nil, -- "x", "y", "z"
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

    local view = gb.math3d.lookat(cx, cy, cz,
        preview.cam.target[1], preview.cam.target[2], preview.cam.target[3],
        0, 1, 0)
    local proj = gb.math3d.perspective(preview.cam.fov, vp_w / math.max(1.0, vp_h), 0.1, 500.0)

    return view, proj, { cx, cy, cz }
end

function preview.frame(rect)
    ig.set_cursor_pos(0, 0)
    local avail_w, avail_h = ig.get_content_region_avail()
    local x0, y0 = ig.get_cursor_screen_pos()
    local io = ig.get_io()
    local dt = io.delta_time > 0 and io.delta_time or 0.016

    -- Smooth camera lerp
    local lerp_factor = 1.0 - math.exp(-dt * 22.0)
    preview.cam.dist = preview.cam.dist + (preview.cam.target_dist - preview.cam.dist) * lerp_factor
    preview.cam.yaw = preview.cam.yaw + (preview.cam.target_yaw - preview.cam.yaw) * lerp_factor
    preview.cam.pitch = preview.cam.pitch + (preview.cam.target_pitch - preview.cam.pitch) * lerp_factor
    for i = 1, 3 do
        preview.cam.target[i] = preview.cam.target[i] + (preview.cam.target_pos[i] - preview.cam.target[i]) * lerp_factor
    end

    -- Viewport invisible button for mouse input
    ig.invisible_button("##vp_canvas", avail_w, avail_h)
    local is_hovered = ig.is_item_hovered()
    local is_active = ig.is_item_active()
    local mx, my = ig.get_mouse_pos()

    -- 1. Bare Scroll Wheel -> Smooth Dolly
    if is_hovered and io.mouse_wheel ~= 0 then
        local factor = math.pow(1.15, -io.mouse_wheel)
        preview.cam.target_dist = clamp(preview.cam.target_dist * factor, 1.0, 150.0)
    end

    -- 2. Orbit -> Middle Drag or Alt+Left Drag
    local is_orbit = (ig.is_mouse_dragging(2) and not io.key_shift) or (io.key_alt and ig.is_mouse_dragging(0))
    if is_hovered and is_orbit then
        local btn = ig.is_mouse_dragging(2) and 2 or 0
        local dx, dy = ig.get_mouse_drag_delta(btn, 0)
        preview.cam.target_yaw = preview.cam.target_yaw - dx * 0.4
        preview.cam.target_pitch = clamp(preview.cam.target_pitch + dy * 0.4, -89.0, 89.0)
        ig.reset_mouse_drag_delta(btn)
    end

    -- 3. Pan -> Shift+Middle Drag or Space+Left Drag
    local is_pan = (ig.is_mouse_dragging(2) and io.key_shift) or ((io.key_alt or ig.is_key_down(ig.Key.Space)) and ig.is_mouse_dragging(0))
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

    -- 4. Focus Selected Brush ('F' key)
    if is_hovered and ig.is_key_pressed(ig.Key.F) then
        local sel = doc.get_brush(doc.selected_id)
        if sel then
            preview.cam.target_pos[1] = sel.pos[1]
            preview.cam.target_pos[2] = sel.pos[2]
            preview.cam.target_pos[3] = sel.pos[3]
            preview.cam.target_dist = clamp(math.max(sel.size[1], math.max(sel.size[2], sel.size[3])) * 3.0, 3.0, 50.0)
        end
    end

    -- Rendering 3D Scene to ImGui DrawList
    ig.dl_push_clip_rect(x0, y0, x0 + avail_w, y0 + avail_h, true)

    -- Background fill
    ig.dl_add_rect_filled(x0, y0, x0 + avail_w, y0 + avail_h, 0.10, 0.10, 0.12, 1.0)

    local view, proj, cam_pos = preview.get_view_proj(avail_w, avail_h)

    -- Helper to project 3D world to 2D screen
    local function world_to_screen(wx, wy, wz)
        local sx, sy, sz = gb.math3d.project(wx, wy, wz, view, proj, avail_w, avail_h)
        return x0 + sx, y0 + sy, sz
    end

    -- 3D Ground Grid
    local grid_extent = 16
    local grid_step = 1.0
    for i = -grid_extent, grid_extent do
        local alpha = (i % 4 == 0) and 0.25 or 0.10
        local x1, y1, z1 = world_to_screen(i * grid_step, 0, -grid_extent * grid_step)
        local x2, y2, z2 = world_to_screen(i * grid_step, 0,  grid_extent * grid_step)
        if z1 > 0 and z2 > 0 then
            ig.dl_add_line(x1, y1, x2, y2, 0.7, 0.7, 0.8, alpha, 1.0)
        end

        local x3, y3, z3 = world_to_screen(-grid_extent * grid_step, 0, i * grid_step)
        local x4, y4, z4 = world_to_screen( grid_extent * grid_step, 0, i * grid_step)
        if z3 > 0 and z4 > 0 then
            ig.dl_add_line(x3, y3, x4, y4, 0.7, 0.7, 0.8, alpha, 1.0)
        end
    end

    -- Axis indicators at origin
    local o_x, o_y, o_z = world_to_screen(0, 0, 0)
    local ax_x, ax_y, ax_z = world_to_screen(2, 0, 0) -- X = Red
    local ay_x, ay_y, ay_z = world_to_screen(0, 2, 0) -- Y = Green
    local az_x, az_y, az_z = world_to_screen(0, 0, 2) -- Z = Blue

    if o_z > 0 and ax_z > 0 then ig.dl_add_line(o_x, o_y, ax_x, ax_y, 0.95, 0.25, 0.25, 0.8, 2.0) end
    if o_z > 0 and ay_z > 0 then ig.dl_add_line(o_x, o_y, ay_x, ay_y, 0.25, 0.95, 0.25, 0.8, 2.0) end
    if o_z > 0 and az_z > 0 then ig.dl_add_line(o_x, o_y, az_x, az_y, 0.25, 0.55, 0.95, 0.8, 2.0) end

    -- Draw CSG Brushes
    for _, b in ipairs(doc.brushes) do
        if b.visible then
            local is_selected = (b.id == doc.selected_id)
            local bx, by, bz = b.pos[1], b.pos[2], b.pos[3]
            local hw, hh, hd = b.size[1] * 0.5, b.size[2] * 0.5, b.size[3] * 0.5

            -- 8 Corners of Box Bounds
            local corners = {
                { bx - hw, by - hh, bz - hd },
                { bx + hw, by - hh, bz - hd },
                { bx + hw, by + hh, bz - hd },
                { bx - hw, by + hh, bz - hd },
                { bx - hw, by - hh, bz + hd },
                { bx + hw, by - hh, bz + hd },
                { bx + hw, by + hh, bz + hd },
                { bx - hw, by + hh, bz + hd },
            }

            local proj_pts = {}
            local all_front = true
            for idx, c in ipairs(corners) do
                local sx, sy, sz = world_to_screen(c[1], c[2], c[3])
                proj_pts[idx] = { sx, sy, sz }
                if sz <= 0 then all_front = false end
            end

            if all_front then
                -- Color coding: Subtractive is translucent red, Additive is brush color
                local col_r, col_g, col_b = b.color[1], b.color[2], b.color[3]
                if b.op == "subtract" then
                    col_r, col_g, col_b = 0.9, 0.2, 0.2
                end

                -- Wireframe edges (12 edges)
                local edges = {
                    {1,2}, {2,3}, {3,4}, {4,1},
                    {5,6}, {6,7}, {7,8}, {8,5},
                    {1,5}, {2,6}, {3,7}, {4,8}
                }

                local edge_r = is_selected and theme.accent[1] or col_r
                local edge_g = is_selected and theme.accent[2] or col_g
                local edge_b = is_selected and theme.accent[3] or col_b
                local edge_thick = is_selected and 2.0 or 1.0

                for _, e in ipairs(edges) do
                    local p1 = proj_pts[e[1]]
                    local p2 = proj_pts[e[2]]
                    ig.dl_add_line(p1[1], p1[2], p2[1], p2[2], edge_r, edge_g, edge_b, 0.85, edge_thick)
                end

                -- Label above brush
                local top_x, top_y, top_z = world_to_screen(bx, by + hh + 0.2, bz)
                if top_z > 0 then
                    ig.dl_add_text(top_x - 16, top_y - 12, edge_r, edge_g, edge_b, 0.9, b.name)
                end
            end
        end
    end

    -- Floating Viewport Pill Info
    ig.set_cursor_pos(12, 12)
    local mode_info = string.format("Grid: %.2fm  ·  Cam: (%.1f, %.1f, %.1f)",
        doc.snap_grid, preview.cam.target[1], preview.cam.target[2], preview.cam.target[3])
    ig.text_colored(mode_info, 0.6, 0.62, 0.7, 0.8)

    ig.dl_pop_clip_rect()
end

return preview
