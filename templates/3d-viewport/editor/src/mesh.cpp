// mesh.cpp — Low-poly mesh geometry, automatic UV unwrapper, and 3D raycast painting
#include "editor.h"
#include <cmath>
#include <cstring>
#include <algorithm>

static constexpr float PI = 3.14159265358979323846f;

static Vec3 v_add(Vec3 a, Vec3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
static Vec3 v_sub(Vec3 a, Vec3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
static Vec3 v_mul(Vec3 a, float s) { return { a.x * s, a.y * s, a.z * s }; }
static float v_dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static Vec3 v_cross(Vec3 a, Vec3 b) {
    return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x };
}
static float v_len(Vec3 a) { return std::sqrt(v_dot(a, a)); }
static Vec3 v_norm(Vec3 a) {
    float l = v_len(a);
    return (l > 1e-6f) ? v_mul(a, 1.0f / l) : Vec3{ 0, 0, 0 };
}

Mat4 mat4_perspective(float fov_rad, float aspect, float near_z, float far_z) {
    Mat4 res = {};
    float tan_half_fov = std::tan(fov_rad * 0.5f);
    res.m[0] = 1.0f / (aspect * tan_half_fov);
    res.m[5] = 1.0f / tan_half_fov;
    res.m[10] = -(far_z + near_z) / (far_z - near_z);
    res.m[11] = -1.0f;
    res.m[14] = -(2.0f * far_z * near_z) / (far_z - near_z);
    return res;
}

Mat4 mat4_lookat(Vec3 eye, Vec3 target, Vec3 up) {
    Vec3 f = v_norm(v_sub(target, eye));
    Vec3 s = v_norm(v_cross(f, up));
    Vec3 u = v_cross(s, f);

    Mat4 res = {};
    res.m[0] = s.x;  res.m[4] = s.y;  res.m[8]  = s.z;  res.m[12] = -v_dot(s, eye);
    res.m[1] = u.x;  res.m[5] = u.y;  res.m[9]  = u.z;  res.m[13] = -v_dot(u, eye);
    res.m[2] = -f.x; res.m[6] = -f.y; res.m[10] = -f.z; res.m[14] = v_dot(f, eye);
    res.m[3] = 0;    res.m[7] = 0;    res.m[11] = 0;    res.m[15] = 1.0f;
    return res;
}

Vec3 mat4_transform_point(const Mat4& m, Vec3 p) {
    float x = m.m[0] * p.x + m.m[4] * p.y + m.m[8]  * p.z + m.m[12];
    float y = m.m[1] * p.x + m.m[5] * p.y + m.m[9]  * p.z + m.m[13];
    float z = m.m[2] * p.x + m.m[6] * p.y + m.m[10] * p.z + m.m[14];
    float w = m.m[3] * p.x + m.m[7] * p.y + m.m[11] * p.z + m.m[15];
    if (std::abs(w) > 1e-6f) {
        float inv = 1.0f / w;
        return { x * inv, y * inv, z * inv };
    }
    return { x, y, z };
}

// Möller–Trumbore Ray-Triangle intersection with barycentric UV interpolation
bool ray_intersect_triangle(Ray ray, Vec3 v0, Vec3 v1, Vec3 v2, Vec3* hit_p, Vec2* hit_bary, float* hit_t) {
    Vec3 edge1 = v_sub(v1, v0);
    Vec3 edge2 = v_sub(v2, v0);
    Vec3 h = v_cross(ray.dir, edge2);
    float a = v_dot(edge1, h);
    if (std::abs(a) < 1e-7f) return false;

    float f = 1.0f / a;
    Vec3 s = v_sub(ray.origin, v0);
    float u = f * v_dot(s, h);
    if (u < 0.0f || u > 1.0f) return false;

    Vec3 q = v_cross(s, edge1);
    float v = f * v_dot(ray.dir, q);
    if (v < 0.0f || u + v > 1.0f) return false;

    float t = f * v_dot(edge2, q);
    if (t > 1e-5f) {
        if (hit_t) *hit_t = t;
        if (hit_p) *hit_p = v_add(ray.origin, v_mul(ray.dir, t));
        if (hit_bary) *hit_bary = { u, v };
        return true;
    }
    return false;
}

// ── Automatic UV Unwrapping ──────────────────────────────────────────────────
// Automatically projects faces into a packed atlas grid with margin padding
void mesh_auto_unwrap_box(PolyMesh* mesh, int texture_size, float padding) {
    if (!mesh || mesh->faces.empty()) return;

    int num_faces = (int)mesh->faces.size();
    int grid_cols = (int)std::ceil(std::sqrt((float)num_faces));
    int grid_rows = (int)std::ceil((float)num_faces / grid_cols);

    float cell_w = 1.0f / grid_cols;
    float cell_h = 1.0f / grid_rows;
    float pad_u = (padding / (float)texture_size) * cell_w;
    float pad_v = (padding / (float)texture_size) * cell_h;

    for (int i = 0; i < num_faces; i++) {
        int gx = i % grid_cols;
        int gy = i / grid_cols;

        float u0 = gx * cell_w + pad_u;
        float v0 = gy * cell_h + pad_v;
        float u1 = (gx + 1) * cell_w - pad_u;
        float v1 = (gy + 1) * cell_h - pad_v;

        Face& f = mesh->faces[i];
        if (f.verts.size() == 4) {
            mesh->vertices[f.verts[0]].uv = { u0, v0 };
            mesh->vertices[f.verts[1]].uv = { u1, v0 };
            mesh->vertices[f.verts[2]].uv = { u1, v1 };
            mesh->vertices[f.verts[3]].uv = { u0, v1 };
        } else if (f.verts.size() == 3) {
            mesh->vertices[f.verts[0]].uv = { (u0 + u1) * 0.5f, v0 };
            mesh->vertices[f.verts[1]].uv = { u1, v1 };
            mesh->vertices[f.verts[2]].uv = { u0, v1 };
        }
    }
}

// ── Low-Poly Primitive Builders ──────────────────────────────────────────────
PolyMesh mesh_create_cube(Vec3 size) {
    PolyMesh m;
    float hx = size.x * 0.5f, hy = size.y * 0.5f, hz = size.z * 0.5f;

    // 8 Vertices
    m.vertices.push_back({ { -hx, -hy, -hz }, { 0, 0, 0 }, { 0, 0 } }); // 0
    m.vertices.push_back({ {  hx, -hy, -hz }, { 0, 0, 0 }, { 1, 0 } }); // 1
    m.vertices.push_back({ {  hx,  hy, -hz }, { 0, 0, 0 }, { 1, 1 } }); // 2
    m.vertices.push_back({ { -hx,  hy, -hz }, { 0, 0, 0 }, { 0, 1 } }); // 3
    m.vertices.push_back({ { -hx, -hy,  hz }, { 0, 0, 0 }, { 0, 0 } }); // 4
    m.vertices.push_back({ {  hx, -hy,  hz }, { 0, 0, 0 }, { 1, 0 } }); // 5
    m.vertices.push_back({ {  hx,  hy,  hz }, { 0, 0, 0 }, { 1, 1 } }); // 6
    m.vertices.push_back({ { -hx,  hy,  hz }, { 0, 0, 0 }, { 0, 1 } }); // 7

    // 6 Quad Faces
    m.faces.push_back({ { 0, 3, 2, 1 }, { 0, 0, -1 } }); // Back
    m.faces.push_back({ { 4, 5, 6, 7 }, { 0, 0,  1 } }); // Front
    m.faces.push_back({ { 0, 4, 7, 3 }, { -1, 0, 0 } }); // Left
    m.faces.push_back({ { 1, 2, 6, 5 }, {  1, 0, 0 } }); // Right
    m.faces.push_back({ { 3, 7, 6, 2 }, { 0, 1,  0 } }); // Top
    m.faces.push_back({ { 0, 1, 5, 4 }, { 0, -1, 0 } }); // Bottom

    mesh_auto_unwrap_box(&m, 256, 4.0f);
    return m;
}

PolyMesh mesh_create_cylinder(float radius, float height, int segments) {
    PolyMesh m;
    if (segments < 3) segments = 8; // low poly default
    float hh = height * 0.5f;

    for (int i = 0; i < segments; i++) {
        float a = (float)i / segments * 2.0f * PI;
        float x = std::cos(a) * radius, z = std::sin(a) * radius;
        m.vertices.push_back({ { x, -hh, z }, { x/radius, 0, z/radius }, { 0, 0 } }); // bottom: 0..seg-1
        m.vertices.push_back({ { x,  hh, z }, { x/radius, 0, z/radius }, { 0, 1 } }); // top: seg..2seg-1
    }

    for (int i = 0; i < segments; i++) {
        int next = (i + 1) % segments;
        int b0 = i * 2, t0 = i * 2 + 1;
        int b1 = next * 2, t1 = next * 2 + 1;
        m.faces.push_back({ { (uint32_t)b0, (uint32_t)b1, (uint32_t)t1, (uint32_t)t0 }, { 0, 0, 0 } });
    }

    mesh_auto_unwrap_box(&m, 256, 4.0f);
    return m;
}

// Face Extrusion along Face Normal
void mesh_extrude_face(PolyMesh* mesh, int face_idx, float length) {
    if (!mesh || face_idx < 0 || face_idx >= (int)mesh->faces.size()) return;
    Face orig_face = mesh->faces[face_idx];
    int nverts = (int)orig_face.verts.size();

    // Calculate normal
    Vec3 v0 = mesh->vertices[orig_face.verts[0]].pos;
    Vec3 v1 = mesh->vertices[orig_face.verts[1]].pos;
    Vec3 v2 = mesh->vertices[orig_face.verts[2]].pos;
    Vec3 norm = v_norm(v_cross(v_sub(v1, v0), v_sub(v2, v0)));

    std::vector<uint32_t> new_verts;
    for (int i = 0; i < nverts; i++) {
        Vertex v = mesh->vertices[orig_face.verts[i]];
        v.pos = v_add(v.pos, v_mul(norm, length));
        uint32_t idx = (uint32_t)mesh->vertices.size();
        mesh->vertices.push_back(v);
        new_verts.push_back(idx);
    }

    // Replace original face with top cap
    mesh->faces[face_idx].verts = new_verts;
    mesh->faces[face_idx].normal = norm;

    // Create side connecting quad faces
    for (int i = 0; i < nverts; i++) {
        int next = (i + 1) % nverts;
        uint32_t o0 = orig_face.verts[i];
        uint32_t o1 = orig_face.verts[next];
        uint32_t n1 = new_verts[next];
        uint32_t n0 = new_verts[i];
        mesh->faces.push_back({ { o0, o1, n1, n0 }, { 0, 0, 0 } });
    }

    mesh_auto_unwrap_box(mesh, 256, 4.0f);
}
