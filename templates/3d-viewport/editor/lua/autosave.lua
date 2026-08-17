-- autosave.lua — Debounced autosave
local doc = require("doc")
local autosave = {}

function autosave.tick()
    if doc.dirty and (os.clock() - doc.dirty_time) >= 0.300 then
        doc.dirty = false
    end
end

return autosave
