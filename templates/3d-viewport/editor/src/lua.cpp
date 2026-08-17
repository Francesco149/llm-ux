// lua.cpp — Embedded Lua 5.4 VM, gb.* module registration, and error handling
#include "editor.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

#include <imgui.h>

static lua_State* L_global = nullptr;
static char lua_dir_path[2048] = { 0 };

lua_State* lua_state() { return L_global; }

// ── Math3D Lua Bindings ──────────────────────────────────────────────────────
static int l_math3d_perspective(lua_State* L) {
    float fov = (float)luaL_checknumber(L, 1);
    float aspect = (float)luaL_checknumber(L, 2);
    float near_z = (float)luaL_checknumber(L, 3);
    float far_z = (float)luaL_checknumber(L, 4);

    Mat4 m = mat4_perspective(fov, aspect, near_z, far_z);
    lua_createtable(L, 16, 0);
    for (int i = 0; i < 16; i++) {
        lua_pushnumber(L, m.m[i]);
        lua_rawseti(L, -2, i + 1);
    }
    return 1;
}

static int l_math3d_lookat(lua_State* L) {
    Vec3 eye = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    Vec3 target = { (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) };
    Vec3 up = { (float)luaL_checknumber(L, 7), (float)luaL_checknumber(L, 8), (float)luaL_checknumber(L, 9) };

    Mat4 m = mat4_lookat(eye, target, up);
    lua_createtable(L, 16, 0);
    for (int i = 0; i < 16; i++) {
        lua_pushnumber(L, m.m[i]);
        lua_rawseti(L, -2, i + 1);
    }
    return 1;
}

static Mat4 table_to_mat4(lua_State* L, int idx) {
    Mat4 m = {};
    for (int i = 0; i < 16; i++) {
        lua_rawgeti(L, idx, i + 1);
        m.m[i] = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
    return m;
}

static int l_math3d_project(lua_State* L) {
    Vec3 p = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    Mat4 view = table_to_mat4(L, 4);
    Mat4 proj = table_to_mat4(L, 5);
    float vp_w = (float)luaL_checknumber(L, 6);
    float vp_h = (float)luaL_checknumber(L, 7);

    Mat4 vp = mat4_mul(proj, view);
    Vec3 clip = mat4_transform_point(vp, p);

    // NDC [-1, 1] to screen [0, w], [0, h]
    float sx = (clip.x * 0.5f + 0.5f) * vp_w;
    float sy = (1.0f - (clip.y * 0.5f + 0.5f)) * vp_h;
    float sz = clip.z;

    lua_pushnumber(L, sx);
    lua_pushnumber(L, sy);
    lua_pushnumber(L, sz);
    return 3;
}

static int l_math3d_ray_plane(lua_State* L) {
    Ray ray;
    ray.origin = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    ray.dir = vec3_normalize({ (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) });
    Vec3 plane_p = { (float)luaL_checknumber(L, 7), (float)luaL_checknumber(L, 8), (float)luaL_checknumber(L, 9) };
    Vec3 plane_n = { (float)luaL_checknumber(L, 10), (float)luaL_checknumber(L, 11), (float)luaL_checknumber(L, 12) };

    Vec3 hit_p;
    float hit_t;
    if (ray_intersect_plane(ray, plane_p, plane_n, &hit_p, &hit_t)) {
        lua_pushboolean(L, 1);
        lua_pushnumber(L, hit_p.x);
        lua_pushnumber(L, hit_p.y);
        lua_pushnumber(L, hit_p.z);
        lua_pushnumber(L, hit_t);
        return 5;
    }
    lua_pushboolean(L, 0);
    return 1;
}

static int l_math3d_ray_aabb(lua_State* L) {
    Ray ray;
    ray.origin = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    ray.dir = vec3_normalize({ (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) });
    AABB box;
    box.min = { (float)luaL_checknumber(L, 7), (float)luaL_checknumber(L, 8), (float)luaL_checknumber(L, 9) };
    box.max = { (float)luaL_checknumber(L, 10), (float)luaL_checknumber(L, 11), (float)luaL_checknumber(L, 12) };

    float hit_t;
    if (ray_intersect_aabb(ray, box, &hit_t)) {
        lua_pushboolean(L, 1);
        lua_pushnumber(L, hit_t);
        return 2;
    }
    lua_pushboolean(L, 0);
    return 1;
}

// ── File IO Lua Bindings ─────────────────────────────────────────────────────
static int l_file_exists(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    lua_pushboolean(L, file_exists(path));
    return 1;
}

static int l_file_read(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    size_t len = 0;
    char* data = file_read_all(path, &len);
    if (data) {
        lua_pushlstring(L, data, len);
        free(data);
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

static int l_file_write(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    lua_pushboolean(L, file_write_all(path, data, len) == 0);
    return 1;
}

// ── App Logging & Control ────────────────────────────────────────────────────
static int l_app_log(lua_State* L) {
    const char* msg = luaL_checkstring(L, 1);
    app_log("%s", msg);
    return 0;
}

static int l_app_quit(lua_State* L) {
    int code = (int)luaL_optinteger(L, 1, 0);
    app_quit(code);
    return 0;
}

void register_ig_bindings(lua_State* L);

void lua_init(const char* root_dir, int argc, char** argv) {
    snprintf(lua_dir_path, sizeof(lua_dir_path), "%s", root_dir);
    L_global = luaL_newstate();
    luaL_openlibs(L_global);

    // Add lua_dir to package.path
    lua_getglobal(L_global, "package");
    lua_getfield(L_global, -1, "path");
    const char* cur_path = lua_tostring(L_global, -1);
    char new_path[4096];
    snprintf(new_path, sizeof(new_path), "%s/?.lua;%s/?/init.lua;%s/../tests/?.lua;%s/../tests/?/init.lua;%s", root_dir, root_dir, root_dir, root_dir, cur_path ? cur_path : "");
    lua_pop(L_global, 1);
    lua_pushstring(L_global, new_path);
    lua_setfield(L_global, -2, "path");
    lua_pop(L_global, 1);

    // Create gb global table
    lua_newtable(L_global);

    // gb.math3d
    lua_newtable(L_global);
    lua_pushcfunction(L_global, l_math3d_perspective); lua_setfield(L_global, -2, "perspective");
    lua_pushcfunction(L_global, l_math3d_lookat); lua_setfield(L_global, -2, "lookat");
    lua_pushcfunction(L_global, l_math3d_project); lua_setfield(L_global, -2, "project");
    lua_pushcfunction(L_global, l_math3d_ray_plane); lua_setfield(L_global, -2, "ray_plane");
    lua_pushcfunction(L_global, l_math3d_ray_aabb); lua_setfield(L_global, -2, "ray_aabb");
    lua_setfield(L_global, -2, "math3d");

    // gb.file
    lua_newtable(L_global);
    lua_pushcfunction(L_global, l_file_exists); lua_setfield(L_global, -2, "exists");
    lua_pushcfunction(L_global, l_file_read); lua_setfield(L_global, -2, "read");
    lua_pushcfunction(L_global, l_file_write); lua_setfield(L_global, -2, "write");
    lua_setfield(L_global, -2, "file");

    // gb.app
    lua_newtable(L_global);
    lua_pushcfunction(L_global, l_app_log); lua_setfield(L_global, -2, "log");
    lua_pushcfunction(L_global, l_app_quit); lua_setfield(L_global, -2, "quit");
    lua_setfield(L_global, -2, "app");

    // Register gb.ig (ImGui)
    register_ig_bindings(L_global);

    lua_setglobal(L_global, "gb");

    // Pass CLI arguments table
    lua_createtable(L_global, argc, 0);
    for (int i = 0; i < argc; i++) {
        lua_pushstring(L_global, argv[i]);
        lua_rawseti(L_global, -2, i + 1);
    }
    lua_setglobal(L_global, "arg");

    // Run tests if requested
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--test") == 0) {
            char test_file[2048];
            snprintf(test_file, sizeof(test_file), "%s/../tests/testmain.lua", root_dir);
            if (luaL_dofile(L_global, test_file) != LUA_OK) {
                fprintf(stderr, "[LUA ERROR] %s\n", lua_tostring(L_global, -1));
                exit(1);
            }
            exit(0);
        }
    }

    // Load main.lua
    char main_file[2048];
    snprintf(main_file, sizeof(main_file), "%s/main.lua", root_dir);
    if (luaL_dofile(L_global, main_file) != LUA_OK) {
        fprintf(stderr, "[LUA INIT ERROR] %s\n", lua_tostring(L_global, -1));
    }
}

void lua_frame() {
    if (!L_global) return;
    lua_getglobal(L_global, "gb_frame");
    if (lua_isfunction(L_global, -1)) {
        if (lua_pcall(L_global, 0, 0, 0) != LUA_OK) {
            app_log("[LUA RUNTIME ERROR] %s", lua_tostring(L_global, -1));
            lua_pop(L_global, 1);
        }
    } else {
        lua_pop(L_global, 1);
    }
}

void lua_shutdown() {
    if (L_global) {
        lua_close(L_global);
        L_global = nullptr;
    }
}
