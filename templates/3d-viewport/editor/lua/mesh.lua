-- mesh.lua — Low-poly mesh primitives and procedural modeling operations
local mesh = {}
local uv = require("uv")

function mesh.create_cube(sx, sy, sz)
    sx = sx or 2.0; sy = sy or 2.0; sz = sz or 2.0
    local hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5

    local m = {
        vertices = {
            { pos = { -hx, -hy, -hz }, normal = { 0, 0, -1 }, uv = { 0, 0 } }, -- 1
            { pos = {  hx, -hy, -hz }, normal = { 0, 0, -1 }, uv = { 1, 0 } }, -- 2
            { pos = {  hx,  hy, -hz }, normal = { 0, 0, -1 }, uv = { 1, 1 } }, -- 3
            { pos = { -hx,  hy, -hz }, normal = { 0, 0, -1 }, uv = { 0, 1 } }, -- 4
            { pos = { -hx, -hy,  hz }, normal = { 0, 0,  1 }, uv = { 0, 0 } }, -- 5
            { pos = {  hx, -hy,  hz }, normal = { 0, 0,  1 }, uv = { 1, 0 } }, -- 6
            { pos = {  hx,  hy,  hz }, normal = { 0, 0,  1 }, uv = { 1, 1 } }, -- 7
            { pos = { -hx,  hy,  hz }, normal = { 0, 0,  1 }, uv = { 0, 1 } }, -- 8
        },
        faces = {
            { verts = { 1, 4, 3, 2 }, normal = { 0, 0, -1 } }, -- Back
            { verts = { 5, 6, 7, 8 }, normal = { 0, 0,  1 } }, -- Front
            { verts = { 1, 5, 8, 4 }, normal = { -1, 0, 0 } }, -- Left
            { verts = { 2, 3, 7, 6 }, normal = {  1, 0, 0 } }, -- Right
            { verts = { 4, 8, 7, 3 }, normal = { 0, 1,  0 } }, -- Top
            { verts = { 1, 2, 6, 5 }, normal = { 0, -1, 0 } }, -- Bottom
        }
    }
    uv.auto_unwrap(m, 256, 4.0)
    return m
end

function mesh.calculate_face_normal(m, f)
    if not f or not f.verts or #f.verts < 3 then return { 0, 1, 0 } end
    local v0 = m.vertices[f.verts[1]] and m.vertices[f.verts[1]].pos
    local v1 = m.vertices[f.verts[2]] and m.vertices[f.verts[2]].pos
    local v2 = m.vertices[f.verts[3]] and m.vertices[f.verts[3]].pos
    if not v0 or not v1 or not v2 then return { 0, 1, 0 } end

    local e1 = { v1[1] - v0[1], v1[2] - v0[2], v1[3] - v0[3] }
    local e2 = { v2[1] - v0[1], v2[2] - v0[2], v2[3] - v0[3] }
    local nx = e1[2] * e2[3] - e1[3] * e2[2]
    local ny = e1[3] * e2[1] - e1[1] * e2[3]
    local nz = e1[1] * e2[2] - e1[2] * e2[1]
    local len = math.sqrt(nx*nx + ny*ny + nz*nz)
    if len > 1e-6 then
        return { nx / len, ny / len, nz / len }
    end
    return { 0, 1, 0 }
end

function mesh.extrude_face(m, face_idx, dist)
    if not m or not m.faces or not m.faces[face_idx] then return end
    local f = m.faces[face_idx]
    local nverts = #f.verts
    if nverts < 3 then return end

    local norm = mesh.calculate_face_normal(m, f)
    local nx, ny, nz = norm[1], norm[2], norm[3]

    local orig_verts = {}
    local new_verts = {}
    for i = 1, nverts do
        local vi = f.verts[i]
        orig_verts[i] = vi
        local old_v = m.vertices[vi]
        if old_v and old_v.pos then
            local new_idx = #m.vertices + 1
            m.vertices[new_idx] = {
                pos = { old_v.pos[1] + nx * dist, old_v.pos[2] + ny * dist, old_v.pos[3] + nz * dist },
                normal = { nx, ny, nz },
                uv = { 0, 0 }
            }
            new_verts[i] = new_idx
        end
    end

    -- Update top face
    f.verts = new_verts
    f.normal = { nx, ny, nz }

    -- Create side quad connecting faces
    for i = 1, nverts do
        local next_i = (i % nverts) + 1
        local side_f = {
            verts = { orig_verts[i], orig_verts[next_i], new_verts[next_i], new_verts[i] },
            normal = { 0, 0, 0 }
        }
        side_f.normal = mesh.calculate_face_normal(m, side_f)
        m.faces[#m.faces + 1] = side_f
    end

    uv.auto_unwrap(m, 256, 4.0)
end

return mesh
