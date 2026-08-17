-- preview.lua — 3D Viewport with front-facing 3D raycast picking, Vertex/Edge/Face modes, 3D texture painting, and near-plane clipped rendering
local preview = {}
local ig = lp.ig
local doc = require("doc")
local theme = require("theme")
local undo = require("undo")
local mesh = require("mesh")
local paint = require("paint")

preview.cam = {
    target = { 0, 0, 0 },
    yaw = 45.0,
    pitch = 30.0,
    dist = 6.0,
    target_dist = 6.0,
    target_yaw = 45.0,
    target_pitch = 30.0,
    target_pos = { 0, 0, 0 },
    fov = 1.13446, -- ~65 degrees in radians
    drag_start_mouse = nil,
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

    local tx, ty, tz = preview.cam.target[1], preview.cam.target[2], preview.cam.target[3]
    local fx, fy, fz = tx - cx, ty - cy, tz - cz
    local flen = math.sqrt(fx * fx + fy * fy + fz * fz)
    if flen > 1e-6 then
        fx, fy, fz = fx / flen, fy / flen, fz / flen
    else
        fx, fy, fz = 0, 0, -1
    end

    local view = lp.math3d.lookat(cx, cy, cz, tx, ty, tz, 0, 1, 0)
    local proj = lp.math3d.perspective(preview.cam.fov, vp_w / math.max(1.0, vp_h), 0.1, 500.0)

    return view, proj, { cx, cy, cz }, { fx, fy, fz }
end

-- 3D line drawing with near-plane clipping: prevents points behind camera from inverting
local function draw_line_3d(dl, x1, y1, z1, x2, y2, z2, r, g, b, a, thickness, eye, fwd, world_to_screen, near_plane)
    near_plane = near_plane or 0.15
    local d1 = (x1 - eye[1]) * fwd[1] + (y1 - eye[2]) * fwd[2] + (z1 - eye[3]) * fwd[3]
    local d2 = (x2 - eye[1]) * fwd[1] + (y2 - eye[2]) * fwd[2] + (z2 - eye[3]) * fwd[3]

    if d1 < near_plane and d2 < near_plane then
        return
    end

    local px1, py1, pz1 = x1, y1, z1
    local px2, py2, pz2 = x2, y2, z2

    if d1 < near_plane then
        local t = (near_plane - d1) / (d2 - d1)
        px1 = x1 + t * (x2 - x1)
        py1 = y1 + t * (y2 - y1)
        pz1 = z1 + t * (z2 - z1)
    elseif d2 < near_plane then
        local t = (near_plane - d1) / (d2 - d1)
        px2 = x1 + t * (x2 - x1)
        py2 = y1 + t * (y2 - y1)
        pz2 = z1 + t * (z2 - z1)
    end

    local s1x, s1y, s1z = world_to_screen(px1, py1, pz1)
    local s2x, s2y, s2z = world_to_screen(px2, py2, pz2)

    if s1z > 0 and s2z > 0 then
        ig.dl_add_line(dl, s1x, s1y, s2x, s2y, r, g, b, a, thickness or 1.0)
    end
end

-- Distance from 2D point to line segment
local function point_to_segment_dist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len_sq = dx * dx + dy * dy
    if len_sq < 1e-6 then
        local dpx, dpy = px - ax, py - ay
        return math.sqrt(dpx * dpx + dpy * dpy)
    end
    local t = math.max(0.0, math.min(1.0, ((px - ax) * dx + (py - ay) * dy) / len_sq))
    local cx, cy = ax + t * dx, ay + t * dy
    local dpx, dpy = px - cx, py - cy
    return math.sqrt(dpx * dpx + dpy * dpy)
end

-- Build 3D unprojected ray from mouse position through viewport
local function unproject_ray(mx, my, x0, y0, avail_w, avail_h, eye, fwd, fov)
    local ndc_x = ((mx - x0) / avail_w) * 2.0 - 1.0
    local ndc_y = 1.0 - ((my - y0) / avail_h) * 2.0
    local aspect = avail_w / math.max(1.0, avail_h)
    local tan_fov = math.tan(fov * 0.5)

    -- Right = Fwd x Up where Up=(0,1,0) -> (-fwd[3], 0, fwd[1])
    local rx = -fwd[3]
    local ry = 0
    local rz = fwd[1]
    local rlen = math.sqrt(rx * rx + rz * rz)
    if rlen > 1e-6 then
        rx, rz = rx / rlen, rz / rlen
    else
        rx, rz = 1, 0
    end

    -- Up = Right x Fwd
    local ux = ry * fwd[3] - rz * fwd[2]
    local uy = rz * fwd[1] - rx * fwd[3]
    local uz = rx * fwd[2] - ry * fwd[1]
    local ulen = math.sqrt(ux * ux + uy * uy + uz * uz)
    if ulen > 1e-6 then
        ux, uy, uz = ux / ulen, uy / ulen, uz / ulen
    else
        ux, uy, uz = 0, 1, 0
    end

    local dx = fwd[1] + (ndc_x * tan_fov * aspect) * rx + (ndc_y * tan_fov) * ux
    local dy = fwd[2] + (ndc_x * tan_fov * aspect) * ry + (ndc_y * tan_fov) * uy
    local dz = fwd[3] + (ndc_x * tan_fov * aspect) * rz + (ndc_y * tan_fov) * uz
    local dlen = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dlen > 1e-6 then
        dx, dy, dz = dx / dlen, dy / dlen, dz / dlen
    end

    return eye, { dx, dy, dz }
end

-- Raycast against mesh faces with front-facing normal check
local function raycast_mesh(ray_origin, ray_dir, m)
    if not m or not m.faces then return nil end
    local nearest_hit = nil
    local nearest_t = 1e9

    for f_idx, f in ipairs(m.faces) do
        if #f.verts >= 3 then
            local v0 = m.vertices[f.verts[1]]
            local v1 = m.vertices[f.verts[2]]
            local v2 = m.vertices[f.verts[3]]
            local v3 = f.verts[4] and m.vertices[f.verts[4]]

            -- Check front-facing normal (normal dot ray_dir < 0)
            local norm = f.normal
            if not norm and v0 and v1 and v2 then
                local e1x, e1y, e1z = v1.pos[1] - v0.pos[1], v1.pos[2] - v0.pos[2], v1.pos[3] - v0.pos[3]
                local e2x, e2y, e2z = v2.pos[1] - v0.pos[1], v2.pos[2] - v0.pos[2], v2.pos[3] - v0.pos[3]
                norm = { e1y * e2z - e1z * e2y, e1z * e1x - e1x * e2z, e1x * e2y - e1y * e2x }
            end

            local is_front = true
            if norm then
                local dot = norm[1] * ray_dir[1] + norm[2] * ray_dir[2] + norm[3] * ray_dir[3]
                if dot >= 0.001 then is_front = false end -- Cull backfaces!
            end

            if is_front and v0 and v1 and v2 then
                -- Triangle 1: (v0, v1, v2)
                local hit1, hx1, hy1, hz1, bu1, bv1, ht1 = lp.math3d.ray_triangle(
                    ray_origin[1], ray_origin[2], ray_origin[3],
                    ray_dir[1], ray_dir[2], ray_dir[3],
                    v0.pos[1], v0.pos[2], v0.pos[3],
                    v1.pos[1], v1.pos[2], v1.pos[3],
                    v2.pos[1], v2.pos[2], v2.pos[3]
                )
                if hit1 and ht1 > 0.001 and ht1 < nearest_t then
                    nearest_t = ht1
                    local uv0 = v0.uv or {0, 0}
                    local uv1 = v1.uv or {1, 0}
                    local uv2 = v2.uv or {1, 1}
                    local w0 = 1.0 - bu1 - bv1
                    local u = w0 * uv0[1] + bu1 * uv1[1] + bv1 * uv2[1]
                    local v = w0 * uv0[2] + bu1 * uv1[2] + bv1 * uv2[2]
                    nearest_hit = {
                        face_idx = f_idx,
                        t = ht1,
                        point = { hx1, hy1, hz1 },
                        uv = { u, v },
                    }
                end

                -- Triangle 2: (v0, v2, v3) if quad
                if v3 then
                    local hit2, hx2, hy2, hz2, bu2, bv2, ht2 = lp.math3d.ray_triangle(
                        ray_origin[1], ray_origin[2], ray_origin[3],
                        ray_dir[1], ray_dir[2], ray_dir[3],
                        v0.pos[1], v0.pos[2], v0.pos[3],
                        v2.pos[1], v2.pos[2], v2.pos[3],
                        v3.pos[1], v3.pos[2], v3.pos[3]
                    )
                    if hit2 and ht2 > 0.001 and ht2 < nearest_t then
                        nearest_t = ht2
                        local uv0 = v0.uv or {0, 0}
                        local uv2 = v2.uv or {1, 1}
                        local uv3 = v3.uv or {0, 1}
                        local w0 = 1.0 - bu2 - bv2
                        local u = w0 * uv0[1] + bu2 * uv2[1] + bv2 * uv3[1]
                        local v = w0 * uv0[2] + bu2 * uv2[2] + bv2 * uv3[2]
                        nearest_hit = {
                            face_idx = f_idx,
                            t = ht2,
                            point = { hx2, hy2, hz2 },
                            uv = { u, v },
                        }
                    end
                end
            end
        end
    end
    return nearest_hit
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

    local view, proj, cam_eye, cam_fwd = preview.get_view_proj(avail_w, avail_h)
    local function world_to_screen(wx, wy, wz)
        local sx, sy, sz = lp.math3d.project(wx, wy, wz, view, proj, avail_w, avail_h)
        return x0 + sx, y0 + sy, sz
    end

    local ray_origin, ray_dir = unproject_ray(mx, my, x0, y0, avail_w, avail_h, cam_eye, cam_fwd, preview.cam.fov)

    -- ── 1. Selection Mode Hotkeys (1=Vertex, 2=Edge, 3=Face, 4/B=Paint) ─────
    if is_hovered and not io.want_text_input and not doc.action then
        if ig.key then
            if ig.is_key_pressed(ig.key["1"]) then doc.sel_mode = "vertex" end
            if ig.is_key_pressed(ig.key["2"]) then doc.sel_mode = "edge" end
            if ig.is_key_pressed(ig.key["3"]) then doc.sel_mode = "face" end
            if ig.is_key_pressed(ig.key["4"]) or ig.is_key_pressed(ig.key.B) then doc.sel_mode = "paint" end
        end
    end

    -- ── 2. Direct Manipulation Action Triggers (G=Move, E=Extrude, S=Scale) ─
    if is_hovered and not io.want_text_input and not doc.action and doc.mesh then
        -- 'E' -> Direct Extrude Face (Face mode only)
        if ig.key and ig.is_key_pressed(ig.key.E) and not io.key_ctrl and doc.sel_mode == "face" and doc.selected_face then
            doc.action = "extrude"
            doc.action_orig = doc.snapshot()
            mesh.extrude_face(doc.mesh, doc.selected_face, 0.0)
            preview.cam.drag_start_mouse = { mx, my }
            doc.action_delta = 0.0
        end

        -- 'G' -> Direct Grab / Move Selection (Vertex, Edge, or Face)
        if ig.key and ig.is_key_pressed(ig.key.G) then
            local can_move = (doc.sel_mode == "face" and doc.selected_face) or
                             (doc.sel_mode == "vertex" and doc.selected_vert) or
                             (doc.sel_mode == "edge" and doc.selected_edge)
            if can_move then
                doc.action = "move"
                doc.action_orig = doc.snapshot()
                preview.cam.drag_start_mouse = { mx, my }
                doc.action_delta = 0.0
            end
        end

        -- 'S' -> Direct Scale Selection (Vertex, Edge, or Face)
        if ig.key and ig.is_key_pressed(ig.key.S) then
            local can_scale = (doc.sel_mode == "face" and doc.selected_face) or
                              (doc.sel_mode == "vertex" and doc.selected_vert) or
                              (doc.sel_mode == "edge" and doc.selected_edge)
            if can_scale then
                doc.action = "scale"
                doc.action_orig = doc.snapshot()
                preview.cam.drag_start_mouse = { mx, my }
                doc.action_delta = 1.0
            end
        end
    end

    -- ── 3. In-Flight Modal Interaction Handling (Move, Scale, Extrude) ───────
    if doc.action then
        local start_m = preview.cam.drag_start_mouse or { mx, my }
        local d_mouse_y = start_m[2] - my
        local d_mouse_x = mx - start_m[1]

        if doc.action == "extrude" and doc.mesh and doc.selected_face then
            local dist = (d_mouse_y * 0.02)
            doc.action_delta = dist
            local f = doc.mesh.faces[doc.selected_face]
            if f and f.normal then
                local orig_mesh = doc.action_orig.mesh
                local orig_f = orig_mesh.faces[doc.selected_face]
                for i, vi in ipairs(f.verts) do
                    local orig_vi = orig_f.verts[i]
                    local orig_v = orig_mesh.vertices[orig_vi]
                    if orig_v then
                        doc.mesh.vertices[vi].pos = {
                            orig_v.pos[1] + f.normal[1] * dist,
                            orig_v.pos[2] + f.normal[2] * dist,
                            orig_v.pos[3] + f.normal[3] * dist,
                        }
                    end
                end
            end
        elseif doc.action == "move" and doc.mesh then
            local rad_yaw = deg2rad(preview.cam.yaw)
            local right_x = math.cos(rad_yaw)
            local right_z = -math.sin(rad_yaw)
            local move_speed = preview.cam.dist * 0.002
            local dx = right_x * d_mouse_x * move_speed
            local dz = right_z * d_mouse_x * move_speed
            local dy = d_mouse_y * move_speed

            local orig_mesh = doc.action_orig.mesh

            if doc.sel_mode == "face" and doc.selected_face then
                local f = doc.mesh.faces[doc.selected_face]
                local orig_f = orig_mesh.faces[doc.selected_face]
                for i, vi in ipairs(f.verts) do
                    local orig_v = orig_mesh.vertices[orig_f.verts[i]]
                    if orig_v then
                        doc.mesh.vertices[vi].pos = { orig_v.pos[1] + dx, orig_v.pos[2] + dy, orig_v.pos[3] + dz }
                    end
                end
            elseif doc.sel_mode == "vertex" and doc.selected_vert then
                local orig_v = orig_mesh.vertices[doc.selected_vert]
                if orig_v then
                    doc.mesh.vertices[doc.selected_vert].pos = { orig_v.pos[1] + dx, orig_v.pos[2] + dy, orig_v.pos[3] + dz }
                end
            elseif doc.sel_mode == "edge" and doc.selected_edge then
                local v1, v2 = doc.selected_edge[1], doc.selected_edge[2]
                local ov1, ov2 = orig_mesh.vertices[v1], orig_mesh.vertices[v2]
                if ov1 then doc.mesh.vertices[v1].pos = { ov1.pos[1] + dx, ov1.pos[2] + dy, ov1.pos[3] + dz } end
                if ov2 then doc.mesh.vertices[v2].pos = { ov2.pos[1] + dx, ov2.pos[2] + dy, ov2.pos[3] + dz } end
            end
        elseif doc.action == "scale" and doc.mesh then
            local scale_factor = math.max(0.01, 1.0 + (d_mouse_x + d_mouse_y) * 0.01)
            doc.action_delta = scale_factor
            local orig_mesh = doc.action_orig.mesh

            if doc.sel_mode == "face" and doc.selected_face then
                local f = doc.mesh.faces[doc.selected_face]
                local orig_f = orig_mesh.faces[doc.selected_face]
                if f and orig_f and #orig_f.verts > 0 then
                    local cx, cy, cz = 0, 0, 0
                    for _, vi in ipairs(orig_f.verts) do
                        local v = orig_mesh.vertices[vi]
                        if v then cx = cx + v.pos[1]; cy = cy + v.pos[2]; cz = cz + v.pos[3] end
                    end
                    cx = cx / #orig_f.verts; cy = cy / #orig_f.verts; cz = cz / #orig_f.verts
                    for i, vi in ipairs(f.verts) do
                        local orig_v = orig_mesh.vertices[orig_f.verts[i]]
                        if orig_v then
                            doc.mesh.vertices[vi].pos = {
                                cx + (orig_v.pos[1] - cx) * scale_factor,
                                cy + (orig_v.pos[2] - cy) * scale_factor,
                                cz + (orig_v.pos[3] - cz) * scale_factor,
                            }
                        end
                    end
                end
            elseif doc.sel_mode == "edge" and doc.selected_edge then
                local v1, v2 = doc.selected_edge[1], doc.selected_edge[2]
                local ov1, ov2 = orig_mesh.vertices[v1], orig_mesh.vertices[v2]
                if ov1 and ov2 then
                    local mx_ = (ov1.pos[1] + ov2.pos[1]) * 0.5
                    local my_ = (ov1.pos[2] + ov2.pos[2]) * 0.5
                    local mz_ = (ov1.pos[3] + ov2.pos[3]) * 0.5
                    doc.mesh.vertices[v1].pos = {
                        mx_ + (ov1.pos[1] - mx_) * scale_factor,
                        my_ + (ov1.pos[2] - my_) * scale_factor,
                        mz_ + (ov1.pos[3] - mz_) * scale_factor,
                    }
                    doc.mesh.vertices[v2].pos = {
                        mx_ + (ov2.pos[1] - mx_) * scale_factor,
                        my_ + (ov2.pos[2] - my_) * scale_factor,
                        mz_ + (ov2.pos[3] - mz_) * scale_factor,
                    }
                end
            elseif doc.sel_mode == "vertex" and doc.selected_vert then
                local orig_v = orig_mesh.vertices[doc.selected_vert]
                if orig_v then
                    doc.mesh.vertices[doc.selected_vert].pos = {
                        orig_v.pos[1] * scale_factor,
                        orig_v.pos[2] * scale_factor,
                        orig_v.pos[3] * scale_factor,
                    }
                end
            end
        end

        -- Confirm on Left-Click / Enter / Space
        if ig.is_mouse_clicked(0) or (ig.key and ig.is_key_pressed(ig.key.Enter)) then
            if undo and doc.action_orig then
                undo.push_state(doc.action:upper() .. " " .. doc.sel_mode:upper(), doc.action_orig)
            end
            doc.action = nil
            doc.action_orig = nil
            preview.cam.drag_start_mouse = nil
            doc.mark_dirty()
        end

        -- Cancel on Right-Click / Escape
        if ig.is_mouse_clicked(1) or (ig.key and ig.is_key_pressed(ig.key.Escape)) then
            doc.restore(doc.action_orig)
            doc.action = nil
            preview.cam.drag_start_mouse = nil
        end
    end

    -- ── 4. Camera Navigation (Orbit / Pan / Zoom) ───────────────────────────
    local is_orbit = (ig.is_mouse_dragging(2) and not io.key_shift) or (io.key_alt and ig.is_mouse_dragging(0))
    local is_pan = (ig.is_mouse_dragging(2) and io.key_shift) or ((io.key_alt or (ig.key and ig.is_key_down(ig.key.Space))) and ig.is_mouse_dragging(0))

    if not doc.action then
        -- Bare Scroll Wheel -> Dolly
        if is_hovered and io.mouse_wheel ~= 0 then
            local factor = 1.15 ^ (-io.mouse_wheel)
            preview.cam.target_dist = clamp(preview.cam.target_dist * factor, 1.0, 100.0)
        end

        -- Orbit -> Middle Drag or Alt+Left Drag
        if is_hovered and is_orbit and not is_pan then
            local btn = ig.is_mouse_dragging(2) and 2 or 0
            local dx, dy = ig.get_mouse_drag_delta(btn, 0)
            preview.cam.target_yaw = preview.cam.target_yaw - dx * 0.4
            preview.cam.target_pitch = clamp(preview.cam.target_pitch + dy * 0.4, -89.0, 89.0)
            ig.reset_mouse_drag_delta(btn)
        end

        -- Pan -> Shift+Middle Drag or Space+Left Drag
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

        -- Focus Camera ('F')
        if is_hovered and ig.key and ig.is_key_pressed(ig.key.F) then
            preview.cam.target_pos = { 0, 0, 0 }
            preview.cam.target_dist = 6.0
        end

        -- ── 3D Texture Painting (Paint Mode) ────────────────────────────────
        if doc.sel_mode == "paint" and is_hovered and ig.is_mouse_down(0) and not is_orbit and not is_pan then
            local hit = raycast_mesh(ray_origin, ray_dir, doc.mesh)
            if hit and hit.uv then
                paint.stamp_uv(hit.uv[1], hit.uv[2], doc.brush_radius, doc.brush_hardness, doc.brush_color)
            end
        end

        -- ── 3D Selection (Vertex / Edge / Face) on Left-Click ────────────────
        if doc.sel_mode ~= "paint" and is_hovered and ig.is_mouse_clicked(0) and not io.key_alt and not (ig.key and ig.is_key_down(ig.key.Space)) then
            if doc.mesh then
                if doc.sel_mode == "face" then
                    local hit = raycast_mesh(ray_origin, ray_dir, doc.mesh)
                    if hit then
                        doc.selected_face = hit.face_idx
                    end
                elseif doc.sel_mode == "vertex" then
                    local best_dist, best_vi = 16.0, nil
                    for vi, v in ipairs(doc.mesh.vertices) do
                        local sx, sy, sz = world_to_screen(v.pos[1], v.pos[2], v.pos[3])
                        if sz > 0 then
                            local d = math.sqrt((mx - sx)^2 + (my - sy)^2)
                            if d < best_dist then
                                best_dist = d
                                best_vi = vi
                            end
                        end
                    end
                    if best_vi then
                        doc.selected_vert = best_vi
                    end
                elseif doc.sel_mode == "edge" then
                    local best_dist, best_edge = 14.0, nil
                    for _, f in ipairs(doc.mesh.faces) do
                        for i = 1, #f.verts do
                            local ni = (i % #f.verts) + 1
                            local v1, v2 = f.verts[i], f.verts[ni]
                            local p1, p2 = doc.mesh.vertices[v1], doc.mesh.vertices[v2]
                            local s1x, s1y, s1z = world_to_screen(p1.pos[1], p1.pos[2], p1.pos[3])
                            local s2x, s2y, s2z = world_to_screen(p2.pos[1], p2.pos[2], p2.pos[3])
                            if s1z > 0 and s2z > 0 then
                                local d = point_to_segment_dist(mx, my, s1x, s1y, s2x, s2y)
                                if d < best_dist then
                                    best_dist = d
                                    best_edge = { v1, v2 }
                                end
                            end
                        end
                    end
                    if best_edge then
                        doc.selected_edge = best_edge
                    end
                end
            end
        end
    end

    -- ── 5. DrawList 3D Rendering ────────────────────────────────────────────
    local dl = ig.get_window_draw_list()
    ig.dl_push_clip_rect(dl, x0, y0, x0 + avail_w, y0 + avail_h, true)
    ig.dl_add_rect_filled(dl, x0, y0, x0 + avail_w, y0 + avail_h, 0.09, 0.09, 0.11, 1.0)

    -- Ground Grid (Near-plane clipped)
    for i = -8, 8 do
        local alpha = (i % 4 == 0) and 0.20 or 0.07
        draw_line_3d(dl, i, -1.0, -8, i, -1.0, 8, 0.7, 0.7, 0.8, alpha, 1.0, cam_eye, cam_fwd, world_to_screen)
        draw_line_3d(dl, -8, -1.0, i, 8, -1.0, i, 0.7, 0.7, 0.8, alpha, 1.0, cam_eye, cam_fwd, world_to_screen)
    end

    -- Render 3D Model Mesh
    if doc.mesh then
        -- Collect and sort faces by depth (painter's algorithm)
        local sorted_faces = {}
        for f_idx, f in ipairs(doc.mesh.faces) do
            local pts = {}
            local all_front = true
            local avg_z = 0
            for _, vi in ipairs(f.verts) do
                local v = doc.mesh.vertices[vi]
                if v and v.pos then
                    local sx, sy, sz = world_to_screen(v.pos[1], v.pos[2], v.pos[3])
                    pts[#pts + 1] = { sx, sy, sz }
                    avg_z = avg_z + sz
                    if sz <= 0 then all_front = false end
                end
            end
            if all_front and #pts >= 3 then
                avg_z = avg_z / #pts
                sorted_faces[#sorted_faces + 1] = { f_idx = f_idx, f = f, pts = pts, avg_z = avg_z }
            end
        end
        table.sort(sorted_faces, function(a, b) return a.avg_z > b.avg_z end)

        for _, sf in ipairs(sorted_faces) do
            local f_idx = sf.f_idx
            local f = sf.f
            local pts = sf.pts
            local is_selected_face = (doc.sel_mode == "face" and f_idx == doc.selected_face)

            local norm = f.normal or mesh.calculate_face_normal(doc.mesh, f)
            local nx, ny, nz = norm[1], norm[2], norm[3]
            local light_dot = math.max(0.18, nx * 0.45 + ny * 0.75 + nz * 0.45)

            -- Sample texture color for this face from doc.texture at UV center
            local tr, tg, tb = 0.55, 0.58, 0.65
            if doc.texture and lp and lp.tex then
                local u_c, v_c = 0.5, 0.5
                if #f.verts > 0 then
                    u_c, v_c = 0, 0
                    for _, vi in ipairs(f.verts) do
                        local v = doc.mesh.vertices[vi]
                        if v and v.uv then u_c = u_c + v.uv[1]; v_c = v_c + v.uv[2] end
                    end
                    u_c = u_c / #f.verts; v_c = v_c / #f.verts
                end
                local tx = math.max(0, math.min(doc.tex_w - 1, math.floor(u_c * (doc.tex_w - 1) + 0.5)))
                local ty = math.max(0, math.min(doc.tex_h - 1, math.floor(v_c * (doc.tex_h - 1) + 0.5)))
                local col32 = lp.tex.get(doc.texture, tx, ty)
                if col32 and col32 ~= 0 then
                    tr = ((col32 >> 24) & 0xFF) / 255.0
                    tg = ((col32 >> 16) & 0xFF) / 255.0
                    tb = ((col32 >> 8) & 0xFF) / 255.0
                end
            end

            local shade_r = is_selected_face and (theme.accent[1] * 0.95) or (tr * light_dot)
            local shade_g = is_selected_face and (theme.accent[2] * 0.95) or (tg * light_dot)
            local shade_b = is_selected_face and (theme.accent[3] * 0.95) or (tb * light_dot)

            -- Draw Filled Triangles
            ig.dl_add_triangle_filled(dl, pts[1][1], pts[1][2], pts[2][1], pts[2][2], pts[3][1], pts[3][2],
                shade_r, shade_g, shade_b, 0.95)
            if #pts == 4 then
                ig.dl_add_triangle_filled(dl, pts[1][1], pts[1][2], pts[3][1], pts[3][2], pts[4][1], pts[4][2],
                    shade_r, shade_g, shade_b, 0.95)
            end

            -- Wireframe Edges
            for i = 1, #pts do
                local next_i = (i % #pts) + 1
                local vi1 = f.verts[i]
                local vi2 = f.verts[next_i]

                local is_selected_edge = (doc.sel_mode == "edge" and doc.selected_edge and
                    ((doc.selected_edge[1] == vi1 and doc.selected_edge[2] == vi2) or
                     (doc.selected_edge[1] == vi2 and doc.selected_edge[2] == vi1)))

                local edge_r = is_selected_face and 1.0 or (is_selected_edge and theme.accent[1] or 0.28)
                local edge_g = is_selected_face and 1.0 or (is_selected_edge and theme.accent[2] or 0.32)
                local edge_b = is_selected_face and 1.0 or (is_selected_edge and theme.accent[3] or 0.40)
                local thick = (is_selected_face or is_selected_edge) and 2.5 or 1.0

                ig.dl_add_line(dl, pts[i][1], pts[i][2], pts[next_i][1], pts[next_i][2], edge_r, edge_g, edge_b, 0.85, thick)
            end

            -- 3D Normal Vector Gizmo on Selected Face
            if is_selected_face and not doc.action then
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
                    ig.dl_add_line(dl, sc_x, sc_y, gn_x, gn_y, 1.0, 0.85, 0.2, 1.0, 3.5)
                    ig.dl_add_circle_filled(dl, gn_x, gn_y, 5.0, 1.0, 0.85, 0.2, 1.0)
                end
            end
        end

        -- ── Vertex Handles in Vertex Mode ───────────────────────────────────
        if doc.sel_mode == "vertex" then
            for vi, v in ipairs(doc.mesh.vertices) do
                local sx, sy, sz = world_to_screen(v.pos[1], v.pos[2], v.pos[3])
                if sz > 0 then
                    local is_sel = (vi == doc.selected_vert)
                    local rad = is_sel and 6.0 or 3.5
                    local vr = is_sel and theme.accent[1] or 0.85
                    local vg = is_sel and theme.accent[2] or 0.88
                    local vb = is_sel and theme.accent[3] or 0.95
                    ig.dl_add_circle_filled(dl, sx, sy, rad, vr, vg, vb, 1.0)
                end
            end
        end

        -- ── 3D Brush Reticle Cursor in Paint Mode ────────────────────────────
        if doc.sel_mode == "paint" and is_hovered and not doc.action then
            local hit = raycast_mesh(ray_origin, ray_dir, doc.mesh)
            if hit and hit.point then
                local sx, sy, sz = world_to_screen(hit.point[1], hit.point[2], hit.point[3])
                if sz > 0 then
                    local brad = math.max(4.0, doc.brush_radius * 0.5)
                    ig.dl_add_circle(dl, sx, sy, brad, 1.0, 0.85, 0.2, 1.0, 16, 2.0)
                    ig.dl_add_circle_filled(dl, sx, sy, 3.0, 1.0, 0.85, 0.2, 0.9)
                end
            end
        end
    end

    -- ── 6. Live Interactive Modal HUD ───────────────────────────────────────
    if doc.action then
        local hud_text = string.format("%s: %+.2fm  |  Left-Click/Enter: Confirm  ·  Right-Click/Esc: Cancel",
            doc.action:upper(), doc.action_delta or 0.0)
        local tw = ig.calc_text_size(hud_text)
        local hx = x0 + (avail_w - tw) * 0.5
        local hy = y0 + 16.0
        ig.dl_add_rect_filled(dl, hx - 12, hy - 4, hx + tw + 12, hy + 24, 0.12, 0.13, 0.16, 0.95)
        ig.dl_add_rect(dl, hx - 12, hy - 4, hx + tw + 12, hy + 24, theme.accent[1], theme.accent[2], theme.accent[3], 1.0, 4.0, 1.5)
        ig.dl_add_text(dl, hx, hy, theme.accent[1], theme.accent[2], theme.accent[3], 1.0, hud_text)
    else
        -- Floating Viewport Header Pill
        ig.set_cursor_pos(12, 12)
        local sel_desc = ""
        if doc.sel_mode == "face" then
            sel_desc = "Face #" .. (doc.selected_face or 1) .. " · [G] Move [E] Extrude [S] Scale"
        elseif doc.sel_mode == "vertex" then
            sel_desc = "Vert #" .. (doc.selected_vert or "-") .. " · [G] Move [S] Scale"
        elseif doc.sel_mode == "edge" then
            local ed = doc.selected_edge and (doc.selected_edge[1] .. "-" .. doc.selected_edge[2]) or "-"
            sel_desc = "Edge " .. ed .. " · [G] Move [S] Scale"
        elseif doc.sel_mode == "paint" then
            sel_desc = string.format("Paint Brush (Rad: %.0f) · Left-Drag to paint in 3D", doc.brush_radius)
        end
        local mode_str = string.format("Mode: %s (1/2/3/4)  ·  %s", doc.sel_mode:upper(), sel_desc)
        ig.text_colored(mode_str, theme.accent[1], theme.accent[2], theme.accent[3], 0.95)
    end

    ig.dl_pop_clip_rect(dl)
end

return preview
