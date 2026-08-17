-- main.lua — Bootstrap, frame loop, and shortcuts for lowpoly-painter
local doc = require("doc")
local undo = require("undo")
local autosave = require("autosave")
local mesh = require("mesh")
local panels = require("panels")
local export = require("export")
local ig = lp.ig
local theme = require("theme")

-- Create default cube on startup
if not doc.mesh then
    doc.mesh = mesh.create_cube(2, 2, 2)
    doc.selected_face = 5 -- Top face
end

function lp_frame()
    theme.apply()
    local io = ig.get_io()

    -- Global Shortcuts
    if io.key_ctrl and ig.is_key_pressed(ig.key.Z) then
        undo.do_undo()
    end
    if io.key_ctrl and ig.is_key_pressed(ig.key.Y) then
        undo.do_redo()
    end
    if io.key_ctrl and ig.is_key_pressed(ig.key.E) then
        export.save_obj("build/" .. doc.name .. ".obj")
    end
    if ig.is_key_pressed(ig.key.E) and not io.key_ctrl then
        if doc.mesh and doc.selected_face then
            doc.mutate(function() mesh.extrude_face(doc.mesh, doc.selected_face, 1.0) end, "Extrude")
        end
    end

    autosave.tick()
    panels.render()
    theme.frame_end()
end
