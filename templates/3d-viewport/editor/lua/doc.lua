-- doc.lua — Low-poly model and texture document state with direct manipulation modes
local doc = {
    name = "Character_Model",
    mesh = nil,
    texture = nil,
    tex_w = 256,
    tex_h = 256,
    sel_mode = "face", -- "face", "vertex", "edge"
    selected_face = 5,
    selected_vert = nil,
    selected_edge = nil,
    action = nil, -- nil, "move", "extrude", "scale"
    action_orig = nil,
    action_delta = 0.0,
    brush_radius = 16.0,
    brush_hardness = 0.85,
    brush_color = { 0.85, 0.35, 0.25 },
    dirty = false,
    dirty_time = 0,
}

local undo = nil

if lp and lp.tex then
    doc.texture = lp.tex.alloc(doc.tex_w, doc.tex_h)
    lp.tex.clear(doc.texture, 0x444A54FF)
end

function doc.init(undo_mod)
    undo = undo_mod
    if not doc.texture and lp and lp.tex then
        doc.texture = lp.tex.alloc(doc.tex_w, doc.tex_h)
        lp.tex.clear(doc.texture, 0x444A54FF)
    end
end

function doc.mark_dirty()
    doc.dirty = true
    doc.dirty_time = os.clock()
end

function doc.snapshot()
    local snap = {
        name = doc.name,
        sel_mode = doc.sel_mode,
        selected_face = doc.selected_face,
        selected_vert = doc.selected_vert,
        mesh = { vertices = {}, faces = {} }
    }
    if doc.mesh then
        for i, v in ipairs(doc.mesh.vertices) do
            snap.mesh.vertices[i] = {
                pos = { v.pos[1], v.pos[2], v.pos[3] },
                normal = { v.normal[1], v.normal[2], v.normal[3] },
                uv = { v.uv[1], v.uv[2] }
            }
        end
        for i, f in ipairs(doc.mesh.faces) do
            local verts = {}
            for j, vi in ipairs(f.verts) do verts[j] = vi end
            snap.mesh.faces[i] = { verts = verts, normal = { f.normal[1], f.normal[2], f.normal[3] } }
        end
    end
    return snap
end

function doc.restore(snap)
    doc.name = snap.name
    doc.sel_mode = snap.sel_mode or "face"
    doc.selected_face = snap.selected_face
    doc.selected_vert = snap.selected_vert
    doc.action = nil
    doc.mesh = { vertices = {}, faces = {} }
    for i, v in ipairs(snap.mesh.vertices) do
        doc.mesh.vertices[i] = {
            pos = { v.pos[1], v.pos[2], v.pos[3] },
            normal = { v.normal[1], v.normal[2], v.normal[3] },
            uv = { v.uv[1], v.uv[2] }
        }
    end
    for i, f in ipairs(snap.mesh.faces) do
        local verts = {}
        for j, vi in ipairs(f.verts) do verts[j] = vi end
        doc.mesh.faces[i] = { verts = verts, normal = { f.normal[1], f.normal[2], f.normal[3] } }
    end
    doc.mark_dirty()
end

-- ── JSON serialization (pure Lua, no external deps) ─────────────────────────
local json_esc = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function json_escape(s)
    return s:gsub('[%c"\\]', function(c)
        return json_esc[c] or string.format("\\u%04x", c:byte())
    end)
end

local function json_encode(value)
    local function enc(v, seen)
        local t = type(v)
        if t == "nil" then
            return "null"
        elseif t == "boolean" then
            return v and "true" or "false"
        elseif t == "number" then
            if v ~= v or v == math.huge or v == -math.huge then return "null" end
            return string.format("%.17g", v)
        elseif t == "string" then
            return '"' .. json_escape(v) .. '"'
        elseif t == "table" then
            if seen[v] then return "null" end
            seen[v] = true
            local n = #v
            local parts = {}
            if n > 0 then
                for i = 1, n do parts[i] = enc(v[i], seen) end
            else
                for k, val in pairs(v) do
                    parts[#parts + 1] = '"' .. json_escape(tostring(k)) .. '":' .. enc(val, seen)
                end
            end
            seen[v] = nil
            return (n > 0 and "[" or "{") .. table.concat(parts, ",") .. (n > 0 and "]" or "}")
        end
        return "null"
    end
    return enc(value, {})
end

-- doc.save — persist the document as a JSON project file in the working directory
function doc.save()
    if not lp or not lp.file then return false end
    return lp.file.write(doc.name .. ".json", json_encode(doc.snapshot()))
end

function doc.mutate(fn, desc)
    if undo then undo.push(desc or "Model Edit") end
    fn()
    doc.mark_dirty()
end

return doc
