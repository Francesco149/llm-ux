-- uv.lua — Automatic UV unwrapping with smart packed grid layout
local uv = {}

function uv.auto_unwrap(mesh, texture_size, padding)
    if not mesh or #mesh.faces == 0 then return end
    texture_size = texture_size or 256
    padding = padding or 4.0

    local num_faces = #mesh.faces
    local cols = math.ceil(math.sqrt(num_faces))
    local rows = math.ceil(num_faces / cols)

    local cell_w = 1.0 / cols
    local cell_h = 1.0 / rows
    local pad_u = (padding / texture_size) * cell_w
    local pad_v = (padding / texture_size) * cell_h

    for i, f in ipairs(mesh.faces) do
        local gx = (i - 1) % cols
        local gy = math.floor((i - 1) / cols)

        local u0 = gx * cell_w + pad_u
        local v0 = gy * cell_h + pad_v
        local u1 = (gx + 1) * cell_w - pad_u
        local v1 = (gy + 1) * cell_h - pad_v

        if #f.verts == 4 then
            mesh.vertices[f.verts[1]].uv = { u0, v0 }
            mesh.vertices[f.verts[2]].uv = { u1, v0 }
            mesh.vertices[f.verts[3]].uv = { u1, v1 }
            mesh.vertices[f.verts[4]].uv = { u0, v1 }
        elseif #f.verts == 3 then
            mesh.vertices[f.verts[1]].uv = { (u0 + u1) * 0.5, v0 }
            mesh.vertices[f.verts[2]].uv = { u1, v1 }
            mesh.vertices[f.verts[3]].uv = { u0, v1 }
        end
    end
end

return uv
