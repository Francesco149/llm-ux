-- doc.lua — Document model and CSG scene tree for godot-blockout
local doc = {
    name = "Untitled_Blockout",
    brushes = {},
    selected_id = nil,
    snap_grid = 0.5,
    dirty = false,
    dirty_time = 0,
    _next_id = 1,
}

local undo = nil -- assigned below

function doc.init(undo_module)
    undo = undo_module
end

function doc.new_brush(type, name, pos, size, op, color)
    local id = "b_" .. doc._next_id
    doc._next_id = doc._next_id + 1
    return {
        id = id,
        name = name or (type:sub(1,1):upper() .. type:sub(2) .. "_" .. id),
        type = type or "box", -- "box", "cylinder", "wedge", "stairs"
        op = op or "union",   -- "union", "subtract", "intersect"
        pos = pos or { 0, 0, 0 },
        rot = { 0, 0, 0 },
        size = size or { 2, 2, 2 },
        color = color or { 0.7, 0.72, 0.78 },
        visible = true,
    }
end

function doc.add_brush(b)
    doc.brushes[#doc.brushes + 1] = b
    doc.selected_id = b.id
    doc.mark_dirty()
end

function doc.remove_brush(id)
    for i, b in ipairs(doc.brushes) do
        if b.id == id then
            table.remove(doc.brushes, i)
            if doc.selected_id == id then
                doc.selected_id = doc.brushes[#doc.brushes] and doc.brushes[#doc.brushes].id or nil
            end
            doc.mark_dirty()
            break
        end
    end
end

function doc.duplicate_brush(id)
    local src = doc.get_brush(id)
    if not src then return nil end
    local copy = doc.new_brush(src.type, src.name .. "_copy",
        { src.pos[1] + doc.snap_grid, src.pos[2], src.pos[3] + doc.snap_grid },
        { src.size[1], src.size[2], src.size[3] },
        src.op,
        { src.color[1], src.color[2], src.color[3] }
    )
    doc.add_brush(copy)
    return copy
end

function doc.get_brush(id)
    for _, b in ipairs(doc.brushes) do
        if b.id == id then return b end
    end
    return nil
end

function doc.mark_dirty()
    doc.dirty = true
    doc.dirty_time = os.clock()
end

function doc.snapshot()
    local snap = {
        name = doc.name,
        selected_id = doc.selected_id,
        snap_grid = doc.snap_grid,
        _next_id = doc._next_id,
        brushes = {},
    }
    for i, b in ipairs(doc.brushes) do
        snap.brushes[i] = {
            id = b.id,
            name = b.name,
            type = b.type,
            op = b.op,
            pos = { b.pos[1], b.pos[2], b.pos[3] },
            rot = { b.rot[1], b.rot[2], b.rot[3] },
            size = { b.size[1], b.size[2], b.size[3] },
            color = { b.color[1], b.color[2], b.color[3] },
            visible = b.visible,
        }
    end
    return snap
end

function doc.restore(snap)
    doc.name = snap.name
    doc.selected_id = snap.selected_id
    doc.snap_grid = snap.snap_grid or 0.5
    doc._next_id = snap._next_id or (#snap.brushes + 1)
    doc.brushes = {}
    for i, b in ipairs(snap.brushes) do
        doc.brushes[i] = {
            id = b.id,
            name = b.name,
            type = b.type,
            op = b.op,
            pos = { b.pos[1], b.pos[2], b.pos[3] },
            rot = { b.rot[1], b.rot[2], b.rot[3] },
            size = { b.size[1], b.size[2], b.size[3] },
            color = { b.color[1], b.color[2], b.color[3] },
            visible = b.visible,
        }
    end
    doc.mark_dirty()
end

function doc.mutate(fn, desc)
    if undo then undo.push(desc or "Edit") end
    fn()
    doc.mark_dirty()
end

return doc
