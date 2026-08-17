-- bake.lua — Procedural baked texture effects (Vertical Gradient, Cavity, Base Fill)
local doc = require("doc")
local bake = {}

function bake.vertical_gradient(top_col, bottom_col)
    if not doc.texture or not doc.mesh then return end
    top_col = top_col or { 0.85, 0.90, 0.95 }
    bottom_col = bottom_col or { 0.25, 0.28, 0.35 }

    local min_y, max_y = 1e9, -1e9
    for _, v in ipairs(doc.mesh.vertices) do
        if v.pos[2] < min_y then min_y = v.pos[2] end
        if v.pos[2] > max_y then max_y = v.pos[2] end
    end
    local range_y = math.max(1e-4, max_y - min_y)

    for y = 0, doc.tex_h - 1 do
        local t = 1.0 - (y / (doc.tex_h - 1))
        local r = math.floor((bottom_col[1] + (top_col[1] - bottom_col[1]) * t) * 255)
        local g = math.floor((bottom_col[2] + (top_col[2] - bottom_col[2]) * t) * 255)
        local b = math.floor((bottom_col[3] + (top_col[3] - bottom_col[3]) * t) * 255)
        local col = (r << 24) | (g << 16) | (b << 8) | 0xFF
        for x = 0, doc.tex_w - 1 do
            lp.tex.set(doc.texture, x, y, col)
        end
    end
    doc.mark_dirty()
end

return bake
