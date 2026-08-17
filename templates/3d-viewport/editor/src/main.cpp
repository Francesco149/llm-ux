// main.cpp — CLI argument parsing and mode dispatch for lowpoly-painter
#include "editor.h"
#include <imgui.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static bool has_arg(int argc, char** argv, const char* name) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], name) == 0) return true;
    }
    return false;
}

static const char* find_lua_dir(const char* argv0) {
    static char dir[2048];
    const char* exe = path_dirname(argv0);
    const char* cands[4] = {
        path_join(exe, "lua"),
        path_join(path_join(exe, ".."), "lua"),
        path_join(path_join(exe, ".."), "editor/lua"),
        path_join(path_join(path_join(exe, ".."), ".."), "editor/lua")
    };
    for (const char* c : cands) {
        snprintf(dir, sizeof(dir), "%s", c);
        if (file_exists(path_join(c, "main.lua"))) return dir;
    }
    const char* root = getenv("LP_ROOT");
    if (root) {
        snprintf(dir, sizeof(dir), "%s/editor/lua", root);
        if (file_exists(path_join(dir, "main.lua"))) return dir;
    }
    snprintf(dir, sizeof(dir), "%s", path_join("editor", "lua"));
    return dir;
}

int main(int argc, char** argv) {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(1280, 800);

    if (has_arg(argc, argv, "--test")) {
        lua_init(find_lua_dir(argv[0]), argc, argv);
        lua_shutdown();
        ImGui::DestroyContext();
        return 0;
    }

    if (has_arg(argc, argv, "--shot")) {
        // headless screenshot: offscreen SDL driver; LP_SHOT tells app.cpp to
        // skip vsync (offscreen drivers have no refresh to sync to).
#ifdef _WIN32
        _putenv("SDL_VIDEODRIVER=offscreen");
        _putenv("LP_SHOT=1");
#else
        setenv("SDL_VIDEODRIVER", "offscreen", 1);
        setenv("LP_SHOT", "1", 1);
#endif
    }

    lua_init(find_lua_dir(argv[0]), argc, argv);
    return app_main(argc, argv);
}
