-- test_mesh.lua — Test low-poly modeling, UV unwrapping, and texture painting
local doc = require("doc")
local mesh = require("mesh")
local uv = require("uv")
local paint = require("paint")
local export = require("export")

print("== test_lowpoly_painter ==")

-- 1. Test Cube Creation
local m = mesh.create_cube(2, 2, 2)
assert(#m.vertices == 8, "Expected 8 vertices for cube")
assert(#m.faces == 6, "Expected 6 faces for cube")

-- 2. Test Auto UVs
uv.auto_unwrap(m, 256, 4.0)
for _, v in ipairs(m.vertices) do
    assert(v.uv[1] >= 0.0 and v.uv[1] <= 1.0, "UV U out of range")
    assert(v.uv[2] >= 0.0 and v.uv[2] <= 1.0, "UV V out of range")
end

-- 3. Test Face Extrude
local initial_faces = #m.faces
mesh.extrude_face(m, 5, 1.5) -- Extrude top face
assert(#m.faces == initial_faces + 4, "Extrude should add 4 side quad faces")
assert(#m.vertices == 12, "Extrude should add 4 new top vertices")

-- 4. Test Texture Stamping
doc.mesh = m
local tex = doc.texture
paint.stamp_uv(0.5, 0.5, 8.0, 0.8, { 1.0, 0.0, 0.0 })
local sample_col = lp.tex.get(tex, 128, 128)
local r = (sample_col >> 24) & 0xFF
assert(r > 200, "Expected stamped red pixel in center")

-- 5. Test OBJ Export
local obj = export.generate_obj(m)
assert(obj:find("v "), "Missing vertex records in OBJ")
assert(obj:find("vt "), "Missing texture coordinates in OBJ")
assert(obj:find("f "), "Missing faces in OBJ")

print("All Low-Poly Mesh and Paint tests passed successfully!")
