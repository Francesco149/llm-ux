-- test_ui_smoke.lua — Interactive UI smoke test gate for lowpoly-painter
local doc = require("doc")
local undo = require("undo")
local mesh = require("mesh")
local preview = require("preview")
local panels = require("panels")
local ig = lp.ig

print("== test_ui_smoke ==")

-- Verify reset_mouse_drag_delta is callable
assert(type(ig.reset_mouse_drag_delta) == "function", "reset_mouse_drag_delta must be bound")
ig.reset_mouse_drag_delta(0)
ig.reset_mouse_drag_delta(2)

-- Verify key constants are valid ImGuiKeys (>500)
assert(ig.key.Z > 500, "Key.Z must be ImGuiKey")
assert(ig.key.Space > 500, "Key.Space must be ImGuiKey")
assert(ig.key.F > 500, "Key.F must be ImGuiKey")
assert(ig.key.G > 500, "Key.G must be ImGuiKey")
assert(ig.key.E > 500, "Key.E must be ImGuiKey")

-- Verify ray-triangle intersection
local hit, hx, hy, hz = lp.math3d.ray_triangle(0, 0, 10, 0, 0, -1, -2, -2, 0, 2, -2, 0, 0, 2, 0)
assert(hit, "Ray triangle intersection should succeed")
-- Verify direct manipulation state transition
local init_faces = #doc.mesh.faces
doc.action = "extrude"
doc.action_orig = doc.snapshot()
mesh.extrude_face(doc.mesh, doc.selected_face or 1, 0.5)
assert(#doc.mesh.faces == init_faces + 4, "Expected +4 faces after extrude")
doc.restore(doc.action_orig)
assert(#doc.mesh.faces == init_faces, "Expected initial face count after cancel restore")

print("UI smoke test gate passed with 0 assertions!")
