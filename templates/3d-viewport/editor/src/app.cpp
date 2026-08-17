// app.cpp — SDL3 + SDL_Renderer (D3D11 on Windows, Vulkan/OpenGL on Linux) platform host
#include "editor.h"
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <cstring>
#include <chrono>
#include <thread>
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#endif

#include <SDL3/SDL.h>
#include <imgui.h>
#include <imgui_impl_sdl3.h>
#include <imgui_impl_sdlrenderer3.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "vendor/stb/stb_image_write.h"

static SDL_Window* g_window = nullptr;
static SDL_Renderer* g_renderer = nullptr;
static bool g_running = true;
static int g_exit_code = 0;

void app_log(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(stdout, fmt, args);
    fprintf(stdout, "\n");
    va_end(args);
    fflush(stdout);
}

void app_quit(int code) {
    g_exit_code = code;
    g_running = false;
}

// ── File IO ──────────────────────────────────────────────────────────────────
int file_write_all(const char* path, const void* data, size_t len) {
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    size_t w = fwrite(data, 1, len, f);
    fclose(f);
    return (w == len) ? 0 : -1;
}

char* file_read_all(const char* path, size_t* out_len) {
    FILE* f = fopen(path, "rb");
    if (!f) return nullptr;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return nullptr; }
    char* buf = (char*)malloc(sz + 1);
    if (!buf) { fclose(f); return nullptr; }
    size_t r = fread(buf, 1, sz, f);
    buf[r] = '\0';
    fclose(f);
    if (out_len) *out_len = r;
    return buf;
}

int file_exists(const char* path) {
    FILE* f = fopen(path, "rb");
    if (f) { fclose(f); return 1; }
    return 0;
}

int file_mkdirs(const char* path) {
    char tmp[2048];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char* p = tmp + 1; *p; p++) {
        if (*p == '/' || *p == '\\') {
            char c = *p;
            *p = '\0';
#ifdef _WIN32
            _mkdir(tmp);
#else
            mkdir(tmp, 0755);
#endif
            *p = c;
        }
    }
#ifdef _WIN32
    return _mkdir(tmp);
#else
    return mkdir(tmp, 0755);
#endif
}

const char* path_dirname(const char* p) {
    static char buf[2048];
    snprintf(buf, sizeof(buf), "%s", p);
    char* last = strrchr(buf, '/');
    if (!last) last = strrchr(buf, '\\');
    if (last) *last = '\0';
    else snprintf(buf, sizeof(buf), ".");
    return buf;
}

const char* path_join(const char* a, const char* b) {
    static char buf[2048];
    snprintf(buf, sizeof(buf), "%s/%s", a, b);
    return buf;
}

const char* path_basename(const char* p) {
    const char* last = strrchr(p, '/');
    if (!last) last = strrchr(p, '\\');
    return last ? last + 1 : p;
}

// ── Application Main Loop ────────────────────────────────────────────────────
int app_main(int argc, char** argv) {
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
        app_log("Failed to init SDL: %s", SDL_GetError());
        return 1;
    }

    int win_w = 1280, win_h = 800;
    const char* shot_path = nullptr;
    int shot_frames = 10;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--shot") == 0 && i + 1 < argc) {
            shot_path = argv[i + 1];
        }
        if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
            shot_frames = atoi(argv[i + 1]);
        }
    }

    uint32_t win_flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
    if (shot_path) {
        win_flags |= SDL_WINDOW_HIDDEN;
    }

    g_window = SDL_CreateWindow("lowpoly-painter", win_w, win_h, win_flags);
    if (!g_window) {
        app_log("Failed to create window: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    g_renderer = SDL_CreateRenderer(g_window, nullptr);
    if (!g_renderer) {
        app_log("Failed to create renderer: %s", SDL_GetError());
        SDL_DestroyWindow(g_window);
        SDL_Quit();
        return 1;
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui_ImplSDL3_InitForSDLRenderer(g_window, g_renderer);
    ImGui_ImplSDLRenderer3_Init(g_renderer);

    int frame_count = 0;
    while (g_running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            ImGui_ImplSDL3_ProcessEvent(&event);
            if (event.type == SDL_EVENT_QUIT) {
                g_running = false;
            }
        }

        ImGui_ImplSDLRenderer3_NewFrame();
        ImGui_ImplSDL3_NewFrame();
        ImGui::NewFrame();

        // Run Lua UI pass
        lua_frame();

        ImGui::Render();
        SDL_SetRenderDrawColor(g_renderer, 24, 24, 28, 255);
        SDL_RenderClear(g_renderer);
        ImGui_ImplSDLRenderer3_RenderDrawData(ImGui::GetDrawData(), g_renderer);
        SDL_RenderPresent(g_renderer);

        frame_count++;
        if (shot_path && frame_count >= shot_frames) {
            SDL_Surface* surf = SDL_RenderReadPixels(g_renderer, nullptr);
            if (surf) {
                stbi_write_png(shot_path, surf->w, surf->h, 4, surf->pixels, surf->pitch);
                app_log("Screenshot saved to %s", shot_path);
                SDL_DestroySurface(surf);
            }
            g_running = false;
        }
    }

    ImGui_ImplSDLRenderer3_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImGui::DestroyContext();

    if (g_renderer) SDL_DestroyRenderer(g_renderer);
    if (g_window) SDL_DestroyWindow(g_window);
    SDL_Quit();

    lua_shutdown();
    return g_exit_code;
}
