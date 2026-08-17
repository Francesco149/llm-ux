-- autosave.lua — Debounced autosave
local doc = require("doc")
local autosave = {}

function autosave.tick()
    if doc.dirty and doc.dirty_time and (os.clock() - doc.dirty_time) >= 0.300 then
        doc.save()
        doc.dirty = false
    end
end

return autosave
