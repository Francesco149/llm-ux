-- test_csg.lua — Headless CSG and Math assertions
local doc = require("doc")
local undo = require("undo")
local export_godot = require("export_godot")

print("== test_csg ==")

-- 1. Test Brush Creation
doc.brushes = {}
local b1 = doc.new_brush("box", "Test_Box", { 1, 2, 3 }, { 4, 5, 6 }, "union")
doc.add_brush(b1)
assert(#doc.brushes == 1, "Expected 1 brush")
assert(doc.brushes[1].name == "Test_Box", "Brush name mismatch")
assert(doc.brushes[1].size[1] == 4, "Brush size X mismatch")

-- 2. Test Duplicate
local b2 = doc.duplicate_brush(b1.id)
assert(#doc.brushes == 2, "Expected 2 brushes after duplicate")
assert(b2.pos[1] == 1.5, "Expected pos X offset by snap grid")

-- 3. Test Undo / Redo
undo.push("State 1")
local b3 = doc.new_brush("cylinder", "Test_Cyl", { 0, 0, 0 }, { 2, 4, 2 }, "subtract")
doc.add_brush(b3)
assert(#doc.brushes == 3, "Expected 3 brushes")

undo.do_undo()
assert(#doc.brushes == 2, "Expected 2 brushes after undo")

undo.do_redo()
assert(#doc.brushes == 3, "Expected 3 brushes after redo")

-- 4. Test Godot 4 .tscn Export
local tscn = export_godot.generate_tscn(doc)
assert(tscn:find("CSGCombiner3D"), "Missing CSGCombiner3D in export")
assert(tscn:find("Test_Box"), "Missing Test_Box in export")
assert(tscn:find("Test_Cyl"), "Missing Test_Cyl in export")
assert(tscn:find("operation = 2"), "Missing subtract operation in export")

-- 5. Test 3D Math Projection
local view = gb.math3d.lookat(0, 0, 10, 0, 0, 0, 0, 1, 0)
local proj = gb.math3d.perspective(1.134, 1280.0 / 800.0, 0.1, 500.0)
local sx, sy, sz = gb.math3d.project(0, 0, 0, view, proj, 1280, 800)

assert(math.abs(sx - 640.0) < 1.0, "Center point project X should be screen center")
assert(math.abs(sy - 400.0) < 1.0, "Center point project Y should be screen center")
assert(sz > 0, "Z distance should be positive in front of camera")

print("All CSG tests passed successfully!")
