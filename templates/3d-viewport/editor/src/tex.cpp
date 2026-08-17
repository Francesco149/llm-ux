// tex.cpp — Texture canvas buffer, 2D/3D brush stamping, and image IO
#include "editor.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>

Image* tex_alloc(int w, int h) {
    Image* img = (Image*)calloc(1, sizeof(Image));
    img->w = w;
    img->h = h;
    img->px = (uint32_t*)calloc(w * h, sizeof(uint32_t));
    return img;
}

void tex_free(Image* img) {
    if (img) {
        if (img->px) free(img->px);
        free(img);
    }
}

void tex_clear(Image* img, uint32_t rgba) {
    if (!img || !img->px) return;
    int count = img->w * img->h;
    for (int i = 0; i < count; i++) {
        img->px[i] = rgba;
    }
}

uint32_t tex_get(const Image* img, int x, int y) {
    if (!img || !img->px || x < 0 || x >= img->w || y < 0 || y >= img->h) return 0;
    return img->px[y * img->w + x];
}

void tex_set(Image* img, int x, int y, uint32_t rgba) {
    if (!img || !img->px || x < 0 || x >= img->w || y < 0 || y >= img->h) return;
    img->px[y * img->w + x] = rgba;
}

// 3D/2D Paint Brush Stamp at normalized UV coordinate (u, v in [0, 1])
void tex_stamp(Image* img, float u, float v, float radius_px, float hardness, uint32_t rgba) {
    if (!img || !img->px) return;
    float cx = u * (img->w - 1);
    float cy = v * (img->h - 1);

    int min_x = std::max(0, (int)std::floor(cx - radius_px));
    int max_x = std::min(img->w - 1, (int)std::ceil(cx + radius_px));
    int min_y = std::max(0, (int)std::floor(cy - radius_px));
    int max_y = std::min(img->h - 1, (int)std::ceil(cy + radius_px));

    uint8_t src_r = (rgba >> 24) & 0xFF;
    uint8_t src_g = (rgba >> 16) & 0xFF;
    uint8_t src_b = (rgba >> 8) & 0xFF;
    uint8_t src_a = rgba & 0xFF;

    float r2 = radius_px * radius_px;

    for (int y = min_y; y <= max_y; y++) {
        float dy = (float)y - cy;
        for (int x = min_x; x <= max_x; x++) {
            float dx = (float)x - cx;
            float dist2 = dx * dx + dy * dy;
            if (dist2 <= r2) {
                float dist = std::sqrt(dist2) / radius_px; // [0, 1]
                float alpha_factor = 1.0f;
                if (dist > hardness) {
                    float t = (dist - hardness) / std::max(1e-4f, 1.0f - hardness);
                    alpha_factor = 1.0f - t;
                }

                uint32_t dst_col = img->px[y * img->w + x];
                uint8_t dst_r = (dst_col >> 24) & 0xFF;
                uint8_t dst_g = (dst_col >> 16) & 0xFF;
                uint8_t dst_b = (dst_col >> 8) & 0xFF;

                float blend_a = (src_a / 255.0f) * alpha_factor;
                uint8_t out_r = (uint8_t)(src_r * blend_a + dst_r * (1.0f - blend_a));
                uint8_t out_g = (uint8_t)(src_g * blend_a + dst_g * (1.0f - blend_a));
                uint8_t out_b = (uint8_t)(src_b * blend_a + dst_b * (1.0f - blend_a));

                img->px[y * img->w + x] = (out_r << 24) | (out_g << 16) | (out_b << 8) | 0xFF;
            }
        }
    }
}
