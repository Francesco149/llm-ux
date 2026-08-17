// lua.cpp — Lua 5.4 VM host and lp.* bindings for lowpoly-painter
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

static lua_State* L_global = nullptr;
static char lua_dir_path[2048] = { 0 };

lua_State* lua_state() { return L_global; }

// ── Math3D / Projection Lua Bindings ─────────────────────────────────────────
static Mat4 table_to_mat4(lua_State* L, int idx) {
    Mat4 m = {};
    for (int i = 0; i < 16; i++) {
        lua_rawgeti(L, idx, i + 1);
        m.m[i] = (float)lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
    return m;
}

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

static int l_math3d_project(lua_State* L) {
    Vec3 p = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    Mat4 view = table_to_mat4(L, 4);
    Mat4 proj = table_to_mat4(L, 5);
    float vp_w = (float)luaL_checknumber(L, 6);
    float vp_h = (float)luaL_checknumber(L, 7);

    Mat4 vp = {};
    for (int c = 0; c < 4; c++) {
        for (int r = 0; r < 4; r++) {
            vp.m[c * 4 + r] =
                proj.m[0 * 4 + r] * view.m[c * 4 + 0] +
                proj.m[1 * 4 + r] * view.m[c * 4 + 1] +
                proj.m[2 * 4 + r] * view.m[c * 4 + 2] +
                proj.m[3 * 4 + r] * view.m[c * 4 + 3];
        }
    }

    Vec3 clip = mat4_transform_point(vp, p);
    float sx = (clip.x * 0.5f + 0.5f) * vp_w;
    float sy = (1.0f - (clip.y * 0.5f + 0.5f)) * vp_h;
    float sz = clip.z;

    lua_pushnumber(L, sx);
    lua_pushnumber(L, sy);
    lua_pushnumber(L, sz);
    return 3;
}

static int l_math3d_ray_triangle(lua_State* L) {
    Ray ray;
    ray.origin = { (float)luaL_checknumber(L, 1), (float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3) };
    ray.dir = { (float)luaL_checknumber(L, 4), (float)luaL_checknumber(L, 5), (float)luaL_checknumber(L, 6) };
    Vec3 v0 = { (float)luaL_checknumber(L, 7), (float)luaL_checknumber(L, 8), (float)luaL_checknumber(L, 9) };
    Vec3 v1 = { (float)luaL_checknumber(L, 10), (float)luaL_checknumber(L, 11), (float)luaL_checknumber(L, 12) };
    Vec3 v2 = { (float)luaL_checknumber(L, 13), (float)luaL_checknumber(L, 14), (float)luaL_checknumber(L, 15) };

    Vec3 hit_p;
    Vec2 hit_bary;
    float hit_t;
    if (ray_intersect_triangle(ray, v0, v1, v2, &hit_p, &hit_bary, &hit_t)) {
        lua_pushboolean(L, 1);
        lua_pushnumber(L, hit_p.x);
        lua_pushnumber(L, hit_p.y);
        lua_pushnumber(L, hit_p.z);
        lua_pushnumber(L, hit_bary.x);
        lua_pushnumber(L, hit_bary.y);
        lua_pushnumber(L, hit_t);
        return 7;
    }
    lua_pushboolean(L, 0);
    return 1;
}

// ── Texture Lua Bindings ─────────────────────────────────────────────────────
static int l_tex_alloc(lua_State* L) {
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    Image* img = tex_alloc(w, h);
    lua_pushlightuserdata(L, img);
    return 1;
}

static int l_tex_free(lua_State* L) {
    Image* img = (Image*)lua_touserdata(L, 1);
    tex_free(img);
    return 0;
}

static int l_tex_clear(lua_State* L) {
    Image* img = (Image*)lua_touserdata(L, 1);
    uint32_t col = (uint32_t)luaL_checkinteger(L, 2);
    tex_clear(img, col);
    return 0;
}

static int l_tex_stamp(lua_State* L) {
    Image* img = (Image*)lua_touserdata(L, 1);
    float u = (float)luaL_checknumber(L, 2);
    float v = (float)luaL_checknumber(L, 3);
    float radius = (float)luaL_checknumber(L, 4);
    float hardness = (float)luaL_optnumber(L, 5, 0.8f);
    uint32_t col = (uint32_t)luaL_checkinteger(L, 6);

    tex_stamp(img, u, v, radius, hardness, col);
    return 0;
}
static int l_tex_get(lua_State* L) {
    Image* img = (Image*)lua_touserdata(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    lua_pushinteger(L, tex_get(img, x, y));
    return 1;
}

static int l_tex_set(lua_State* L) {
    Image* img = (Image*)lua_touserdata(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    uint32_t col = (uint32_t)luaL_checkinteger(L, 4);
    tex_set(img, x, y, col);
    return 0;
}


// ── File & App Bindings ──────────────────────────────────────────────────────
static int l_file_write(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    lua_pushboolean(L, file_write_all(path, data, len) == 0);
    return 1;
}

static int l_app_log(lua_State* L) {
    const char* msg = luaL_checkstring(L, 1);
    app_log("%s", msg);
    return 0;
}
void ig_register(lua_State* L);
void register_ig_bindings(lua_State* L);

void lua_init(const char* root_dir, int argc, char** argv) {
    snprintf(lua_dir_path, sizeof(lua_dir_path), "%s", root_dir);
    L_global = luaL_newstate();
    luaL_openlibs(L_global);

    // Package path
    lua_getglobal(L_global, "package");
    lua_getfield(L_global, -1, "path");
    const char* cur_path = lua_tostring(L_global, -1);
    char new_path[4096];
    snprintf(new_path, sizeof(new_path), "%s/?.lua;%s/?/init.lua;%s/../tests/?.lua;%s/../tests/?/init.lua;%s",
        root_dir, root_dir, root_dir, root_dir, cur_path ? cur_path : "");
    lua_pop(L_global, 1);
    lua_pushstring(L_global, new_path);
    lua_setfield(L_global, -2, "path");
    lua_pop(L_global, 1);

    // Global lp table
    lua_newtable(L_global);

    // lp.math3d
    lua_newtable(L_global);
    lua_pushcfunction(L_global, l_math3d_perspective); lua_setfield(L_global, -2, "perspective");
    lua_pushcfunction(L_global, l_math3d_lookat); lua_setfield(L_global, -2, "lookat");
    lua_pushcfunction(L_global, l_math3d_project); lua_setfield(L_global, -2, "project");
    lua_pushcfunction(L_global, l_math3d_ray_triangle); lua_setfield(L_global, -2, "ray_triangle");
    lua_setfield(L_global, -2, "math3d");

    // lp.tex
    lua_newtable(L_global);
    lua_pushcfunction(L_global, l_tex_alloc); lua_setfield(L_global, -2, "alloc");
    lua_pushcfunction(L_global, l_tex_free); lua_setfield(L_global, -2, "free");
    lua_pushcfunction(L_global, l_tex_clear); lua_setfield(L_global, -2, "clear");
    lua_pushcfunction(L_global, l_tex_stamp); lua_setfield(L_global, -2, "stamp");
    lua_pushcfunction(L_global, l_tex_get); lua_setfield(L_global, -2, "get");
    lua_pushcfunction(L_global, l_tex_set); lua_setfield(L_global, -2, "set");
    lua_setfield(L_global, -2, "tex");

    // lp.file
    lua_newtable(L_global);
    lua_pushcfunction(L_global, l_file_write); lua_setfield(L_global, -2, "write");
    lua_setfield(L_global, -2, "file");

    // lp.app
    lua_newtable(L_global);
    lua_pushcfunction(L_global, l_app_log); lua_setfield(L_global, -2, "log");
    lua_setfield(L_global, -2, "app");

    lua_setglobal(L_global, "lp");
    ig_register(L_global);

    // Check --test
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
    lua_getglobal(L_global, "lp_frame");
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
