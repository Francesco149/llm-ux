-- undo.lua — Snapshot undo/redo journal for lowpoly-painter
local doc = require("doc")

local undo = {
    stack = {},
    redo_stack = {},
    max_depth = 100,
}

function undo.push(desc)
    undo.stack[#undo.stack + 1] = {
        desc = desc or "Edit",
        state = doc.snapshot(),
    }
    if #undo.stack > undo.max_depth then
        table.remove(undo.stack, 1)
    end
    undo.redo_stack = {}
end

function undo.do_undo()
    if #undo.stack == 0 then return end
    local entry = table.remove(undo.stack)
    undo.redo_stack[#undo.redo_stack + 1] = {
        desc = entry.desc,
        state = doc.snapshot(),
    }
    doc.restore(entry.state)
end

function undo.do_redo()
    if #undo.redo_stack == 0 then return end
    local entry = table.remove(undo.redo_stack)
    undo.stack[#undo.stack + 1] = {
        desc = entry.desc,
        state = doc.snapshot(),
    }
    doc.restore(entry.state)
end

doc.init(undo)
return undo
