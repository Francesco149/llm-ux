-- test_lua54_compat.lua — Verify no removed Lua 5.4 APIs are used in project Lua files
print("== test_lua54_compat ==")

local removed_apis = {
    { pattern = "math%.pow%s*%(", name = "math.pow (use ^ operator)" },
    { pattern = "math%.atan2%s*%(", name = "math.atan2 (use math.atan(y,x))" },
    { pattern = "math%.ldexp%s*%(", name = "math.ldexp (use m * 2.0^e)" },
    { pattern = "math%.frexp%s*%(", name = "math.frexp (removed in 5.4)" },
    { pattern = "math%.cosh%s*%(", name = "math.cosh (removed in 5.4)" },
    { pattern = "math%.sinh%s*%(", name = "math.sinh (removed in 5.4)" },
    { pattern = "math%.tanh%s*%(", name = "math.tanh (removed in 5.4)" },
    { pattern = "math%.log10%s*%(", name = "math.log10 (use math.log(x,10))" },
    { pattern = "([^%.])unpack%s*%(", name = "unpack() (use table.unpack())" },
    { pattern = "^unpack%s*%(", name = "unpack() (use table.unpack())" },
    { pattern = "loadstring%s*%(", name = "loadstring() (use load())" },
    { pattern = "setfenv%s*%(", name = "setfenv() (removed in 5.2+)" },
    { pattern = "getfenv%s*%(", name = "getfenv() (removed in 5.2+)" },
}

local lua_dir = "editor/lua"
local candidate_dirs = { "editor/lua", "lua" }
local files = {}

local base_dir = "editor/lua"
if not io.open("editor/lua/doc.lua", "r") and io.open("lua/doc.lua", "r") then
    base_dir = "lua"
end

local candidates = {
    "autosave.lua", "colors.lua", "console.lua", "demo.lua", "doc.lua",
    "export.lua", "import.lua", "json.lua", "main.lua", "panel_export.lua",
    "panel_layers.lua", "panel_palette.lua", "panel_props.lua", "panels.lua",
    "perf.lua", "picker.lua", "preview.lua", "render.lua", "theme.lua",
    "ui.lua", "undo.lua", "words.lua",
    "layers/crop.lua", "layers/downscale.lua", "layers/export.lua",
    "layers/fill.lua", "layers/grade.lua", "layers/group.lua",
    "layers/image.lua", "layers/noise.lua", "layers/paint.lua",
    "layers/palette.lua", "layers/seamless.lua"
}
for _, name in ipairs(candidates) do
    local p = base_dir .. "/" .. name
    local f = io.open(p, "r")
    if f then
        f:close()
        files[#files + 1] = p
    end
end

local errors = {}
local files_checked = 0

for _, filepath in ipairs(files) do
    local f = io.open(filepath, "r")
    if f then
        files_checked = files_checked + 1
        local lineno = 0
        for line in f:lines() do
            lineno = lineno + 1
            if not line:match("^%s*%-%-") then
                for _, api in ipairs(removed_apis) do
                    if line:find(api.pattern) then
                        errors[#errors + 1] = string.format(
                            "  %s:%d: %s", filepath, lineno, api.name)
                    end
                end
            end
        end
        f:close()
    end
end

if #errors > 0 then
    print("FAIL: Found " .. #errors .. " uses of removed Lua 5.4 APIs:")
    for _, e in ipairs(errors) do
        print(e)
    end
    error("Lua 5.4 compatibility check failed")
end

print(string.format("  Checked %d files, 0 removed API usages found.", files_checked))
