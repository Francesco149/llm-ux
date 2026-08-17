// editor.h — godot-blockout native core.
// 3D CSG blockout editor with Godot-grade viewport controls and 1-click export.
#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

struct lua_State;

// ── 3D Math Types ────────────────────────────────────────────────────────────
struct Vec3 {
    float x = 0, y = 0, z = 0;
};

struct Vec2 {
    float x = 0, y = 0;
};

struct Mat4 {
    float m[16]; // column-major
};

struct Ray {
    Vec3 origin;
    Vec3 dir;
};

struct AABB {
    Vec3 min;
    Vec3 max;
};

struct Vertex {
    Vec3 pos;
    Vec3 normal;
    Vec2 uv;
    uint32_t color = 0xFFFFFFFF;
};

struct Mesh {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
};

// ── Math3D / CSG Functions ───────────────────────────────────────────────────
Vec3 vec3_add(Vec3 a, Vec3 b);
Vec3 vec3_sub(Vec3 a, Vec3 b);
Vec3 vec3_mul(Vec3 a, float s);
Vec3 vec3_cross(Vec3 a, Vec3 b);
float vec3_dot(Vec3 a, Vec3 b);
float vec3_length(Vec3 a);
Vec3 vec3_normalize(Vec3 a);
Vec3 vec3_lerp(Vec3 a, Vec3 b, float t);

Mat4 mat4_identity();
Mat4 mat4_perspective(float fov_rad, float aspect, float near_z, float far_z);
Mat4 mat4_lookat(Vec3 eye, Vec3 target, Vec3 up);
Mat4 mat4_mul(const Mat4& a, const Mat4& b);
Vec3 mat4_transform_point(const Mat4& m, Vec3 p);
Vec3 mat4_transform_vector(const Mat4& m, Vec3 v);

bool ray_intersect_plane(Ray ray, Vec3 plane_p, Vec3 plane_n, Vec3* hit_p, float* hit_t);
bool ray_intersect_aabb(Ray ray, AABB box, float* hit_t);

// Primitive Mesh Generators
Mesh mesh_create_box(Vec3 size);
Mesh mesh_create_cylinder(float radius, float height, int segments);
Mesh mesh_create_wedge(Vec3 size);
Mesh mesh_create_stairs(Vec3 size, int steps);

// ── Lua VM Host ──────────────────────────────────────────────────────────────
void lua_init(const char* root_dir, int argc, char** argv);
void lua_frame();
void lua_shutdown();
lua_State* lua_state();
int lua_run_string(const char* code, char* err, size_t errsz);

// ── App Platform Host ────────────────────────────────────────────────────────
int app_main(int argc, char** argv);
void app_log(const char* fmt, ...);
void app_quit(int code);

// ── File IO Helpers ──────────────────────────────────────────────────────────
int file_write_all(const char* path, const void* data, size_t len);
char* file_read_all(const char* path, size_t* len);
int file_exists(const char* path);
int file_mkdirs(const char* path);
const char* path_dirname(const char* p);
const char* path_join(const char* a, const char* b);
const char* path_basename(const char* p);
