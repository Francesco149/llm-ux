-- test_lua54_compat.lua — Verify no removed Lua 5.4 APIs are used in project Lua files
-- This test scans all .lua files under editor/lua/ for usage of APIs that were
-- removed in Lua 5.4 (present in 5.1/5.2/5.3). Catches math.pow, unpack(),
-- loadstring(), etc. before they crash at runtime.

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

-- Find all Lua files in the project's lua/ directory
local lua_dir = "editor/lua"
local files = {}

-- Use lp.file.list if available, otherwise try io.popen with ls (safely via pcall)
if lp and lp.file and lp.file.list then
    files = lp.file.list(lua_dir, "*.lua")
else
    local ok, h = pcall(io.popen, "ls " .. lua_dir .. "/*.lua 2>/dev/null")
    if ok and h then
        for line in h:lines() do
            files[#files + 1] = line
        end
        h:close()
    end
end

if #files == 0 then
    -- Fallback list for environments without popen
    local candidates = {
        "doc.lua", "preview.lua", "autosave.lua", "bake.lua", "export.lua",
        "main.lua", "mesh.lua", "paint.lua", "panels.lua", "theme.lua",
        "ui.lua", "undo.lua", "uv.lua"
    }
    for _, name in ipairs(candidates) do
        local p1 = lua_dir .. "/" .. name
        local f = io.open(p1, "r")
        if f then
            f:close()
            files[#files + 1] = p1
        else
            local p2 = "lua/" .. name
            local f2 = io.open(p2, "r")
            if f2 then
                f2:close()
                files[#files + 1] = p2
            end
        end
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
            -- Skip comment lines
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
