// editor.h — lowpoly-painter native core
#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

struct lua_State;

struct Vec3 { float x = 0, y = 0, z = 0; };
struct Vec2 { float x = 0, y = 0; };
struct Mat4 { float m[16]; };
struct Ray { Vec3 origin; Vec3 dir; };
struct AABB { Vec3 min; Vec3 max; };

struct Vertex {
    Vec3 pos;
    Vec3 normal;
    Vec2 uv;
    uint32_t color = 0xFFFFFFFF;
};

struct Face {
    std::vector<uint32_t> verts;
    Vec3 normal;
};

struct PolyMesh {
    std::vector<Vertex> vertices;
    std::vector<Face> faces;
};

// ── Image / Texture ──────────────────────────────────────────────────────────
struct Image {
    int w = 0;
    int h = 0;
    uint32_t* px = nullptr; // 0xRRGGBBAA
};

Image* tex_alloc(int w, int h);
void tex_free(Image* img);
void tex_clear(Image* img, uint32_t rgba);
uint32_t tex_get(const Image* img, int x, int y);
void tex_set(Image* img, int x, int y, uint32_t rgba);
void tex_stamp(Image* img, float u, float v, float radius_px, float hardness, uint32_t rgba);

// ── Math3D / Projection ──────────────────────────────────────────────────────
Mat4 mat4_perspective(float fov_rad, float aspect, float near_z, float far_z);
Mat4 mat4_lookat(Vec3 eye, Vec3 target, Vec3 up);
Vec3 mat4_transform_point(const Mat4& m, Vec3 p);
bool ray_intersect_triangle(Ray ray, Vec3 v0, Vec3 v1, Vec3 v2, Vec3* hit_p, Vec2* hit_uv, float* hit_t);

// ── Automatic UV Unwrapping ──────────────────────────────────────────────────
void mesh_auto_unwrap_box(PolyMesh* mesh, int texture_size, float padding);
void mesh_auto_unwrap_conformal(PolyMesh* mesh, int texture_size, float padding);

// ── Mesh Primitives & Ops ────────────────────────────────────────────────────
PolyMesh mesh_create_cube(Vec3 size);
PolyMesh mesh_create_cylinder(float radius, float height, int segments);
PolyMesh mesh_create_plane(float w, float d);
void mesh_extrude_face(PolyMesh* mesh, int face_idx, float length);

// ── Lua VM Host ──────────────────────────────────────────────────────────────
void lua_init(const char* root_dir, int argc, char** argv);
void lua_frame();
void lua_shutdown();
lua_State* lua_state();

// ── App Host ─────────────────────────────────────────────────────────────────
int app_main(int argc, char** argv);
void app_log(const char* fmt, ...);
void app_quit(int code);

// ── File IO Helpers ──────────────────────────────────────────────────────────
int file_write_all(const char* path, const void* data, size_t len);
char* file_read_all(const char* path, size_t* len);
int file_exists(const char* path);
const char* path_dirname(const char* p);
const char* path_join(const char* a, const char* b);
const char* path_basename(const char* p);
