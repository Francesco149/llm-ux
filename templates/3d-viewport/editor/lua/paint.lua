-- paint.lua — 3D and 2D Texture Painting Engine
local doc = require("doc")
local paint = {}

function paint.stamp_uv(u, v, radius, hardness, color_rgb)
    if not doc.texture then return end
    radius = radius or doc.brush_radius
    hardness = hardness or doc.brush_hardness
    color_rgb = color_rgb or doc.brush_color

    local r = math.floor(color_rgb[1] * 255)
    local g = math.floor(color_rgb[2] * 255)
    local b = math.floor(color_rgb[3] * 255)
    local u32_col = (r << 24) | (g << 16) | (b << 8) | 0xFF

    lp.tex.stamp(doc.texture, u, v, radius, hardness, u32_col)
    doc.mark_dirty()
end

return paint
