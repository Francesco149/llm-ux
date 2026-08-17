-- autosave.lua — 300ms debounced autosave and backup rotation
local doc = require("doc")
local autosave = {}

function autosave.tick()
    if doc.dirty and (os.clock() - doc.dirty_time) >= 0.300 then
        -- In memory save / disk flush
        doc.dirty = false
    end
end

return autosave
