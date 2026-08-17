// math3d.cpp — 3D Vector/Matrix math, raycasting, and primitive mesh builders
#include "editor.h"
#include <cmath>
#include <cstring>

static constexpr float PI = 3.14159265358979323846f;

Vec3 vec3_add(Vec3 a, Vec3 b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
Vec3 vec3_sub(Vec3 a, Vec3 b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
Vec3 vec3_mul(Vec3 a, float s) { return { a.x * s, a.y * s, a.z * s }; }
Vec3 vec3_cross(Vec3 a, Vec3 b) {
    return {
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    };
}
float vec3_dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
float vec3_length(Vec3 a) { return std::sqrt(vec3_dot(a, a)); }
Vec3 vec3_normalize(Vec3 a) {
    float len = vec3_length(a);
    if (len > 1e-6f) return vec3_mul(a, 1.0f / len);
    return { 0, 0, 0 };
}
Vec3 vec3_lerp(Vec3 a, Vec3 b, float t) {
    return { a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t };
}

Mat4 mat4_identity() {
    Mat4 res = {};
    res.m[0] = 1; res.m[5] = 1; res.m[10] = 1; res.m[15] = 1;
    return res;
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
    Vec3 f = vec3_normalize(vec3_sub(target, eye));
    Vec3 s = vec3_normalize(vec3_cross(f, up));
    Vec3 u = vec3_cross(s, f);

    Mat4 res = {};
    res.m[0] = s.x;  res.m[4] = s.y;  res.m[8]  = s.z;  res.m[12] = -vec3_dot(s, eye);
    res.m[1] = u.x;  res.m[5] = u.y;  res.m[9]  = u.z;  res.m[13] = -vec3_dot(u, eye);
    res.m[2] = -f.x; res.m[6] = -f.y; res.m[10] = -f.z; res.m[14] = vec3_dot(f, eye);
    res.m[3] = 0;    res.m[7] = 0;    res.m[11] = 0;    res.m[15] = 1.0f;
    return res;
}

Mat4 mat4_mul(const Mat4& a, const Mat4& b) {
    Mat4 res = {};
    for (int c = 0; c < 4; c++) {
        for (int r = 0; r < 4; r++) {
            res.m[c * 4 + r] =
                a.m[0 * 4 + r] * b.m[c * 4 + 0] +
                a.m[1 * 4 + r] * b.m[c * 4 + 1] +
                a.m[2 * 4 + r] * b.m[c * 4 + 2] +
                a.m[3 * 4 + r] * b.m[c * 4 + 3];
        }
    }
    return res;
}

Vec3 mat4_transform_point(const Mat4& m, Vec3 p) {
    float x = m.m[0] * p.x + m.m[4] * p.y + m.m[8]  * p.z + m.m[12];
    float y = m.m[1] * p.x + m.m[5] * p.y + m.m[9]  * p.y + m.m[13];
    float z = m.m[2] * p.x + m.m[6] * p.y + m.m[10] * p.z + m.m[14];
    float w = m.m[3] * p.x + m.m[7] * p.y + m.m[11] * p.z + m.m[15];
    if (std::abs(w) > 1e-6f) {
        float inv = 1.0f / w;
        return { x * inv, y * inv, z * inv };
    }
    return { x, y, z };
}

bool ray_intersect_plane(Ray ray, Vec3 plane_p, Vec3 plane_n, Vec3* hit_p, float* hit_t) {
    float denom = vec3_dot(plane_n, ray.dir);
    if (std::abs(denom) > 1e-6f) {
        Vec3 diff = vec3_sub(plane_p, ray.origin);
        float t = vec3_dot(diff, plane_n) / denom;
        if (t >= 0.0f) {
            if (hit_t) *hit_t = t;
            if (hit_p) *hit_p = vec3_add(ray.origin, vec3_mul(ray.dir, t));
            return true;
        }
    }
    return false;
}

bool ray_intersect_aabb(Ray ray, AABB box, float* hit_t) {
    float tmin = -1e9f, tmax = 1e9f;
    for (int i = 0; i < 3; i++) {
        float origin = (i == 0) ? ray.origin.x : ((i == 1) ? ray.origin.y : ray.origin.z);
        float dir = (i == 0) ? ray.dir.x : ((i == 1) ? ray.dir.y : ray.dir.z);
        float bmin = (i == 0) ? box.min.x : ((i == 1) ? box.min.y : box.min.z);
        float bmax = (i == 0) ? box.max.x : ((i == 1) ? box.max.y : box.max.z);

        if (std::abs(dir) < 1e-6f) {
            if (origin < bmin || origin > bmax) return false;
        } else {
            float ood = 1.0f / dir;
            float t1 = (bmin - origin) * ood;
            float t2 = (bmax - origin) * ood;
            if (t1 > t2) std::swap(t1, t2);
            tmin = std::max(tmin, t1);
            tmax = std::min(tmax, t2);
            if (tmin > tmax) return false;
        }
    }
    if (tmax < 0.0f) return false;
    if (hit_t) *hit_t = (tmin > 0.0f) ? tmin : tmax;
    return true;
}

Mesh mesh_create_box(Vec3 size) {
    Mesh mesh;
    float hx = size.x * 0.5f, hy = size.y * 0.5f, hz = size.z * 0.5f;

    // 6 faces * 4 vertices = 24 vertices
    static const Vec3 normals[6] = {
        {  0,  0,  1 }, // front
        {  0,  0, -1 }, // back
        { -1,  0,  0 }, // left
        {  1,  0,  0 }, // right
        {  0,  1,  0 }, // top
        {  0, -1,  0 }  // bottom
    };

    static const Vec3 faces[6][4] = {
        // front
        { { -1, -1,  1 }, {  1, -1,  1 }, {  1,  1,  1 }, { -1,  1,  1 } },
        // back
        { {  1, -1, -1 }, { -1, -1, -1 }, { -1,  1, -1 }, {  1,  1, -1 } },
        // left
        { { -1, -1, -1 }, { -1, -1,  1 }, { -1,  1,  1 }, { -1,  1, -1 } },
        // right
        { {  1, -1,  1 }, {  1, -1, -1 }, {  1,  1, -1 }, {  1,  1,  1 } },
        // top
        { { -1,  1,  1 }, {  1,  1,  1 }, {  1,  1, -1 }, { -1,  1, -1 } },
        // bottom
        { { -1, -1, -1 }, {  1, -1, -1 }, {  1, -1,  1 }, { -1, -1,  1 } }
    };

    for (int f = 0; f < 6; f++) {
        uint32_t base = (uint32_t)mesh.vertices.size();
        for (int v = 0; v < 4; v++) {
            Vertex vert;
            vert.pos = { faces[f][v].x * hx, faces[f][v].y * hy, faces[f][v].z * hz };
            vert.normal = normals[f];
            vert.uv = { (v == 1 || v == 2) ? 1.0f : 0.0f, (v >= 2) ? 1.0f : 0.0f };
            mesh.vertices.push_back(vert);
        }
        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 1);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 3);
    }

    return mesh;
}

Mesh mesh_create_cylinder(float radius, float height, int segments) {
    Mesh mesh;
    if (segments < 3) segments = 16;
    float hh = height * 0.5f;

    // Generate circle rings
    for (int i = 0; i < segments; i++) {
        float a0 = (float)i / segments * 2.0f * PI;
        float a1 = (float)(i + 1) / segments * 2.0f * PI;
        float x0 = std::cos(a0) * radius, z0 = std::sin(a0) * radius;
        float x1 = std::cos(a1) * radius, z1 = std::sin(a1) * radius;

        // Side quad
        uint32_t base = (uint32_t)mesh.vertices.size();
        Vertex v0 = { { x0, -hh, z0 }, { x0/radius, 0, z0/radius }, { (float)i/segments, 0 } };
        Vertex v1 = { { x1, -hh, z1 }, { x1/radius, 0, z1/radius }, { (float)(i+1)/segments, 0 } };
        Vertex v2 = { { x1,  hh, z1 }, { x1/radius, 0, z1/radius }, { (float)(i+1)/segments, 1 } };
        Vertex v3 = { { x0,  hh, z0 }, { x0/radius, 0, z0/radius }, { (float)i/segments, 1 } };
        mesh.vertices.push_back(v0);
        mesh.vertices.push_back(v1);
        mesh.vertices.push_back(v2);
        mesh.vertices.push_back(v3);
        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 1);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 0);
        mesh.indices.push_back(base + 2);
        mesh.indices.push_back(base + 3);

        // Top cap
        uint32_t t_base = (uint32_t)mesh.vertices.size();
        Vertex tv0 = { { 0, hh, 0 }, { 0, 1, 0 }, { 0.5f, 0.5f } };
        Vertex tv1 = { { x0, hh, z0 }, { 0, 1, 0 }, { 0.5f + x0/(2*radius), 0.5f + z0/(2*radius) } };
        Vertex tv2 = { { x1, hh, z1 }, { 0, 1, 0 }, { 0.5f + x1/(2*radius), 0.5f + z1/(2*radius) } };
        mesh.vertices.push_back(tv0);
        mesh.vertices.push_back(tv1);
        mesh.vertices.push_back(tv2);
        mesh.indices.push_back(t_base + 0);
        mesh.indices.push_back(t_base + 1);
        mesh.indices.push_back(t_base + 2);

        // Bottom cap
        uint32_t b_base = (uint32_t)mesh.vertices.size();
        Vertex bv0 = { { 0, -hh, 0 }, { 0, -1, 0 }, { 0.5f, 0.5f } };
        Vertex bv1 = { { x1, -hh, z1 }, { 0, -1, 0 }, { 0.5f + x1/(2*radius), 0.5f + z1/(2*radius) } };
        Vertex bv2 = { { x0, -hh, z0 }, { 0, -1, 0 }, { 0.5f + x0/(2*radius), 0.5f + z0/(2*radius) } };
        mesh.vertices.push_back(bv0);
        mesh.vertices.push_back(bv1);
        mesh.vertices.push_back(bv2);
        mesh.indices.push_back(b_base + 0);
        mesh.indices.push_back(b_base + 1);
        mesh.indices.push_back(b_base + 2);
    }
    return mesh;
}

Mesh mesh_create_wedge(Vec3 size) {
    Mesh mesh;
    float hx = size.x * 0.5f, hy = size.y * 0.5f, hz = size.z * 0.5f;

    // Bottom face
    uint32_t b_base = (uint32_t)mesh.vertices.size();
    mesh.vertices.push_back({ { -hx, -hy, -hz }, { 0, -1, 0 }, { 0, 0 } });
    mesh.vertices.push_back({ {  hx, -hy, -hz }, { 0, -1, 0 }, { 1, 0 } });
    mesh.vertices.push_back({ {  hx, -hy,  hz }, { 0, -1, 0 }, { 1, 1 } });
    mesh.vertices.push_back({ { -hx, -hy,  hz }, { 0, -1, 0 }, { 0, 1 } });
    mesh.indices.push_back(b_base + 0); mesh.indices.push_back(b_base + 1); mesh.indices.push_back(b_base + 2);
    mesh.indices.push_back(b_base + 0); mesh.indices.push_back(b_base + 2); mesh.indices.push_back(b_base + 3);

    // Back face (vertical)
    uint32_t k_base = (uint32_t)mesh.vertices.size();
    mesh.vertices.push_back({ {  hx, -hy, -hz }, { 0, 0, -1 }, { 0, 0 } });
    mesh.vertices.push_back({ { -hx, -hy, -hz }, { 0, 0, -1 }, { 1, 0 } });
    mesh.vertices.push_back({ { -hx,  hy, -hz }, { 0, 0, -1 }, { 1, 1 } });
    mesh.vertices.push_back({ {  hx,  hy, -hz }, { 0, 0, -1 }, { 0, 1 } });
    mesh.indices.push_back(k_base + 0); mesh.indices.push_back(k_base + 1); mesh.indices.push_back(k_base + 2);
    mesh.indices.push_back(k_base + 0); mesh.indices.push_back(k_base + 2); mesh.indices.push_back(k_base + 3);

    // Slope face
    Vec3 slope_normal = vec3_normalize({ 0, hz, hy });
    uint32_t s_base = (uint32_t)mesh.vertices.size();
    mesh.vertices.push_back({ { -hx, -hy,  hz }, slope_normal, { 0, 0 } });
    mesh.vertices.push_back({ {  hx, -hy,  hz }, slope_normal, { 1, 0 } });
    mesh.vertices.push_back({ {  hx,  hy, -hz }, slope_normal, { 1, 1 } });
    mesh.vertices.push_back({ { -hx,  hy, -hz }, slope_normal, { 0, 1 } });
    mesh.indices.push_back(s_base + 0); mesh.indices.push_back(s_base + 1); mesh.indices.push_back(s_base + 2);
    mesh.indices.push_back(s_base + 0); mesh.indices.push_back(s_base + 2); mesh.indices.push_back(s_base + 3);

    return mesh;
}

Mesh mesh_create_stairs(Vec3 size, int steps) {
    if (steps < 1) steps = 4;
    Mesh mesh;
    float step_h = size.y / steps;
    float step_d = size.z / steps;
    float hx = size.x * 0.5f;

    for (int i = 0; i < steps; i++) {
        float y0 = -size.y * 0.5f + i * step_h;
        float y1 = y0 + step_h;
        float z0 = size.z * 0.5f - (i + 1) * step_d;
        float z1 = z0 + step_d;

        // Riser (vertical)
        uint32_t r_base = (uint32_t)mesh.vertices.size();
        mesh.vertices.push_back({ { -hx, y0, z1 }, { 0, 0, 1 }, { 0, 0 } });
        mesh.vertices.push_back({ {  hx, y0, z1 }, { 0, 0, 1 }, { 1, 0 } });
        mesh.vertices.push_back({ {  hx, y1, z1 }, { 0, 0, 1 }, { 1, 1 } });
        mesh.vertices.push_back({ { -hx, y1, z1 }, { 0, 0, 1 }, { 0, 1 } });
        mesh.indices.push_back(r_base + 0); mesh.indices.push_back(r_base + 1); mesh.indices.push_back(r_base + 2);
        mesh.indices.push_back(r_base + 0); mesh.indices.push_back(r_base + 2); mesh.indices.push_back(r_base + 3);

        // Tread (horizontal)
        uint32_t t_base = (uint32_t)mesh.vertices.size();
        mesh.vertices.push_back({ { -hx, y1, z1 }, { 0, 1, 0 }, { 0, 0 } });
        mesh.vertices.push_back({ {  hx, y1, z1 }, { 0, 1, 0 }, { 1, 0 } });
        mesh.vertices.push_back({ {  hx, y1, z0 }, { 0, 1, 0 }, { 1, 1 } });
        mesh.vertices.push_back({ { -hx, y1, z0 }, { 0, 1, 0 }, { 0, 1 } });
        mesh.indices.push_back(t_base + 0); mesh.indices.push_back(t_base + 1); mesh.indices.push_back(t_base + 2);
        mesh.indices.push_back(t_base + 0); mesh.indices.push_back(t_base + 2); mesh.indices.push_back(t_base + 3);
    }
    return mesh;
}
