-- export_godot.lua — 1-Click export to Godot 4 CSG Scene (.tscn)
local doc = require("doc")
local export_godot = {}

function export_godot.generate_tscn(doc_data)
    local lines = {}
    lines[#lines + 1] = '[gd_scene format=3]'
    lines[#lines + 1] = ''
    lines[#lines + 1] = '[node name="' .. doc_data.name .. '" type="Node3D"]'
    lines[#lines + 1] = ''
    lines[#lines + 1] = '[node name="CSGCombiner3D" type="CSGCombiner3D" parent="."]'
    lines[#lines + 1] = 'use_collision = true'
    lines[#lines + 1] = ''

    local op_map = { union = 0, intersect = 1, subtract = 2 }

    for _, b in ipairs(doc_data.brushes) do
        if b.visible then
            local node_type = "CSGBox3D"
            if b.type == "cylinder" then node_type = "CSGCylinder3D"
            elseif b.type == "wedge" or b.type == "stairs" then node_type = "CSGBox3D" end

            lines[#lines + 1] = string.format('[node name="%s" type="%s" parent="CSGCombiner3D"]', b.name, node_type)
            lines[#lines + 1] = string.format('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4f, %.4f, %.4f)',
                b.pos[1], b.pos[2], b.pos[3])

            local op_val = op_map[b.op] or 0
            if op_val ~= 0 then
                lines[#lines + 1] = string.format('operation = %d', op_val)
            end

            if b.type == "box" or b.type == "wedge" or b.type == "stairs" then
                lines[#lines + 1] = string.format('size = Vector3(%.4f, %.4f, %.4f)', b.size[1], b.size[2], b.size[3])
            elseif b.type == "cylinder" then
                lines[#lines + 1] = string.format('radius = %.4f', b.size[1] * 0.5)
                lines[#lines + 1] = string.format('height = %.4f', b.size[2])
                lines[#lines + 1] = 'sides = 16'
            end
            lines[#lines + 1] = ''
        end
    end

    return table.concat(lines, '\n')
end

function export_godot.save_tscn(path)
    local tscn_content = export_godot.generate_tscn(doc)
    return gb.file.write(path, tscn_content)
end

return export_godot
