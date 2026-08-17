-- test_ui_smoke.lua — Interactive UI smoke test gate for texturewrangler
local t = require("testlib")
local doc = require("doc")
local undo = require("undo")
local panels = require("panels")
local preview = require("preview")
local ig = tw.ig

local M = {}

function M.test_ui_smoke()
    local io = ig.get_io()
    preview.state.zoom = "custom"
    preview.state.zoom_val = 1.5
    preview.state.ox = 20
    preview.state.oy = 15

    -- Verify zoom hotkeys work without assertion
    if ig.key then
        t.true_(ig.key.Equal > 500, "Equal key constant should be valid ImGuiKey")
        t.true_(ig.key.Minus > 500, "Minus key constant should be valid ImGuiKey")
        t.true_(ig.key.Space > 500, "Space key constant should be valid ImGuiKey")
    end

    -- Verify reset_mouse_drag_delta is callable
    t.eq(type(ig.reset_mouse_drag_delta), "function", "reset_mouse_drag_delta must be bound")
    ig.reset_mouse_drag_delta(0)
    ig.reset_mouse_drag_delta(2)
end

return M
