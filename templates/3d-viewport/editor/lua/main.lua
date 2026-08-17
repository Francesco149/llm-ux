-- main.lua — Bootstrap, global shortcuts, and frame orchestration for godot-blockout
local doc = require("doc")
local undo = require("undo")
local autosave = require("autosave")
local panels = require("panels")
local export_godot = require("export_godot")
local ig = gb.ig

-- Create a sample level blockout on startup if empty
if #doc.brushes == 0 then
    -- Room Floor / Walls
    local floor = doc.new_brush("box", "Floor", { 0, -0.25, 0 }, { 12, 0.5, 12 }, "union", { 0.35, 0.37, 0.42 })
    doc.add_brush(floor)

    local wall1 = doc.new_brush("box", "Wall_North", { 0, 1.5, -5.75 }, { 12, 3, 0.5 }, "union", { 0.55, 0.58, 0.65 })
    doc.add_brush(wall1)

    local pillar = doc.new_brush("cylinder", "Pillar_Center", { -2, 1.5, -2 }, { 1, 3, 1 }, "union", { 0.75, 0.65, 0.45 })
    doc.add_brush(pillar)

    local door_carve = doc.new_brush("box", "Door_Carve", { 0, 1.1, -5.75 }, { 1.6, 2.2, 1.2 }, "subtract", { 0.9, 0.2, 0.2 })
    doc.add_brush(door_carve)

    doc.selected_id = pillar.id
end

function gb_frame()
    local io = ig.get_io()

    -- Global Shortcuts
    if io.key_ctrl and ig.is_key_pressed(ig.Key.Z) then
        undo.do_undo()
    end
    if io.key_ctrl and ig.is_key_pressed(ig.Key.Y) then
        undo.do_redo()
    end
    if io.key_ctrl and ig.is_key_pressed(ig.Key.E) then
        export_godot.save_tscn("build/" .. doc.name .. ".tscn")
    end
    if io.key_ctrl and ig.is_key_pressed(ig.Key.D) then
        if doc.selected_id then doc.duplicate_brush(doc.selected_id) end
    end
    if ig.is_key_pressed(ig.Key.Delete) then
        if doc.selected_id then doc.remove_brush(doc.selected_id) end
    end

    -- Autosave tick
    autosave.tick()

    -- Render UI Panels
    panels.render()
end
