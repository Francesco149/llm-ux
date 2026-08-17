-- export.lua — 1-Click Export to OBJ 3D Model with MTL and PNG texture
local doc = require("doc")
local export = {}

function export.generate_obj(mesh_data)
    local lines = {}
    lines[#lines + 1] = "# lowpoly-painter export"
    lines[#lines + 1] = "mtllib model.mtl"
    lines[#lines + 1] = "o " .. doc.name
    lines[#lines + 1] = ""

    -- Vertices
    for _, v in ipairs(mesh_data.vertices) do
        lines[#lines + 1] = string.format("v %.4f %.4f %.4f", v.pos[1], v.pos[2], v.pos[3])
    end

    -- UVs
    for _, v in ipairs(mesh_data.vertices) do
        lines[#lines + 1] = string.format("vt %.4f %.4f", v.uv[1], v.uv[2])
    end

    -- Normals
    for _, v in ipairs(mesh_data.vertices) do
        lines[#lines + 1] = string.format("vn %.4f %.4f %.4f", v.normal[1], v.normal[2], v.normal[3])
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "usemtl Material"
    lines[#lines + 1] = "s 1"

    -- Faces
    for _, f in ipairs(mesh_data.faces) do
        if #f.verts == 4 then
            lines[#lines + 1] = string.format("f %d/%d/%d %d/%d/%d %d/%d/%d %d/%d/%d",
                f.verts[1], f.verts[1], f.verts[1],
                f.verts[2], f.verts[2], f.verts[2],
                f.verts[3], f.verts[3], f.verts[3],
                f.verts[4], f.verts[4], f.verts[4])
        elseif #f.verts == 3 then
            lines[#lines + 1] = string.format("f %d/%d/%d %d/%d/%d %d/%d/%d",
                f.verts[1], f.verts[1], f.verts[1],
                f.verts[2], f.verts[2], f.verts[2],
                f.verts[3], f.verts[3], f.verts[3])
        end
    end

    return table.concat(lines, "\n")
end

function export.save_obj(path)
    if not doc.mesh then return false end
    local obj_content = export.generate_obj(doc.mesh)
    return lp.file.write(path, obj_content)
end

return export
