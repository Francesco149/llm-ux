// winclip.c — Win32 helpers (Windows cross only).
// Kept OUT of main.cpp because <windows.h> clashes with raylib's
// Rectangle/ShowCursor/CloseWindow declarations. Includes windows.h freely.
#ifdef _WIN32

#include <windows.h>
#include <commdlg.h>
#include <shellapi.h>
#include <wchar.h>

// raylib's GetWindowHandle (GLFWwindow*) — declared manually because
// including raylib.h here clashes with windows.h (Rectangle/ShowCursor...).
extern void *GetWindowHandle(void);

// ── GLFW function pointers (resolved at runtime from glfw3.dll) ─────────────
typedef HWND (*GlfwGetWin32WindowFn)(void*);
static GlfwGetWin32WindowFn pfn_glfwGetWin32Window = NULL;
static int glfw_resolved = 0;

static void resolve_glfw(void) {
    if (glfw_resolved) return;
    glfw_resolved = 1;
    // raylib links glfw3.dll dynamically — look it up by module handle.
    HMODULE glfw = GetModuleHandleA("glfw3.dll");
    if (!glfw) glfw = GetModuleHandleA("glfw3");
    if (!glfw) glfw = GetModuleHandleA("libglfw3.dll");
    if (!glfw) return;
    pfn_glfwGetWin32Window = (GlfwGetWin32WindowFn)
        GetProcAddress(glfw, "glfwGetWin32Window");
}
// Resolve HWND from GLFW window handle.
static HWND get_app_hwnd(void) {
    resolve_glfw();
    void *gw = GetWindowHandle();
    if (gw && pfn_glfwGetWin32Window)
        return pfn_glfwGetWin32Window(gw);
    return NULL;
}

// ── Clipboard ───────────────────────────────────────────────────────────────

// Returns the first file path from the clipboard (CF_HDROP, i.e. files copied
// in Explorer), UTF-8 encoded, or NULL when the clipboard holds no files.
// Caller must NOT free; buffer is static (next call overwrites).
// Using CF_HDROP directly avoids GLFW's "Failed to convert clipboard to
// string" error, which fires when the clipboard has files or is empty.
const char* win_clipboard_file_path(void) {
    static char out[4096];
    out[0] = '\0';

    if (!IsClipboardFormatAvailable(CF_HDROP)) return NULL;
    if (!OpenClipboard(NULL)) return NULL;

    HANDLE h = GetClipboardData(CF_HDROP);
    if (!h) { CloseClipboard(); return NULL; }

    HDROP drop = (HDROP)h;
    UINT count = DragQueryFileW(drop, 0xFFFFFFFF, NULL, 0);
    if (count == 0) { CloseClipboard(); return NULL; }

    wchar_t buf[2048];
    if (DragQueryFileW(drop, 0, buf, 2048) == 0) { CloseClipboard(); return NULL; }
    CloseClipboard();

    int len = WideCharToMultiByte(CP_UTF8, 0, buf, -1, NULL, 0, NULL, NULL);
    if (len <= 1) return NULL;
    if (len > (int)sizeof(out)) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, buf, -1, out, (int)sizeof(out), NULL, NULL);
    return out;
}

// Returns clipboard text (UTF-8) ONLY when a text format is actually present,
// or NULL. Avoids GLFW's clipboard-string error on empty/non-text clipboards.
const char* win_clipboard_text(void) {
    static char out[4096];
    out[0] = '\0';

    if (!IsClipboardFormatAvailable(CF_UNICODETEXT) && !IsClipboardFormatAvailable(CF_TEXT))
        return NULL;
    if (!OpenClipboard(NULL)) return NULL;

    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    if (!h) { CloseClipboard(); return NULL; }

    const wchar_t* w = (const wchar_t*)GlobalLock(h);
    if (!w) { CloseClipboard(); return NULL; }

    int len = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (len > 1 && len <= (int)sizeof(out))
        WideCharToMultiByte(CP_UTF8, 0, w, -1, out, (int)sizeof(out), NULL, NULL);

    GlobalUnlock(h);
    CloseClipboard();
    return (out[0] != '\0') ? out : NULL;
}

// ── Native file dialog (direct Win32 GetOpenFileNameW) ──────────────────────
// Bypasses tinyfiledialogs entirely; uses the Win32 common dialog with the app
// window as owner so it always opens in front.  Returns UTF-8 path or NULL.
const char* win_open_file_dialog(void) {
    static char result[4096];
    result[0] = '\0';

    HWND hwnd = get_app_hwnd();

    // Initialize COM on the UI thread for the modern shell dialog
    HRESULT hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    // Filter: double-null terminated, description\0patterns\0 pairs.
    static const wchar_t filter[] =
        L"Image files (*.png;*.jpg;*.bmp;*.tga;*.gif;*.qoi;*.ico)\0"
        L"*.png;*.jpg;*.jpeg;*.bmp;*.tga;*.gif;*.qoi;*.ico\0"
        L"All files (*.*)\0*.*\0\0";

    wchar_t file_buf[2048];
    file_buf[0] = L'\0';

    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize     = sizeof(ofn);
    ofn.hwndOwner       = hwnd;
    ofn.lpstrFilter     = filter;
    ofn.nFilterIndex    = 1;
    ofn.lpstrFile       = file_buf;
    ofn.nMaxFile        = sizeof(file_buf) / sizeof(file_buf[0]);
    ofn.lpstrTitle      = L"Open Texture";
    ofn.Flags           = OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

    BOOL ok = GetOpenFileNameW(&ofn);

    if (SUCCEEDED(hr)) {
        CoUninitialize();
    }

    if (!ok) return NULL;

    int len = WideCharToMultiByte(CP_UTF8, 0, file_buf, -1, result, (int)sizeof(result), NULL, NULL);
    if (len <= 1) return NULL;
    return result;
}

// ── Workarea & screen metrics ───────────────────────────────────────────────
void win_get_workarea(int* out_w, int* out_h) {
    RECT rc;
    if (SystemParametersInfoA(SPI_GETWORKAREA, 0, &rc, 0)) {
        if (out_w) *out_w = (int)(rc.right - rc.left);
        if (out_h) *out_h = (int)(rc.bottom - rc.top);
    } else {
        if (out_w) *out_w = (int)GetSystemMetrics(SM_CXSCREEN);
        if (out_h) *out_h = (int)GetSystemMetrics(SM_CYSCREEN);
    }
}

// ── Win32 live continuous resize hook ───────────────────────────────────────
// Subclasses the window procedure so frames render live during the DefWindowProc
// modal sizing loop when the user drags the window edge (eliminates stretching/freeze).
extern void app_on_live_resize(void);

static WNDPROC g_orig_wndproc = NULL;
static HWND    g_hooked_hwnd = NULL;
static int     g_in_sizemove = 0;

static LRESULT CALLBACK subclass_wndproc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_ENTERSIZEMOVE:
            g_in_sizemove = 1;
            break;

        case WM_EXITSIZEMOVE:
            g_in_sizemove = 0;
            app_on_live_resize();
            break;

        case WM_SIZING:
            app_on_live_resize();
            break;

        case WM_SIZE:
            if (wParam != SIZE_MINIMIZED && g_in_sizemove) {
                app_on_live_resize();
            }
            break;

        case WM_PAINT:
            if (g_in_sizemove) {
                app_on_live_resize();
            }
            break;
    }

    if (g_orig_wndproc) {
        return CallWindowProc(g_orig_wndproc, hwnd, msg, wParam, lParam);
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

void win_install_resize_hook(void) {
    HWND hwnd = get_app_hwnd();
    if (hwnd && hwnd != g_hooked_hwnd) {
        g_hooked_hwnd = hwnd;
        g_orig_wndproc = (WNDPROC)SetWindowLongPtr(hwnd, GWLP_WNDPROC, (LONG_PTR)subclass_wndproc);
    }
}

#endif // _WIN32
