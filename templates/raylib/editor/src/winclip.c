// winclip.c — Win32 clipboard helpers (Windows cross only).
// Kept OUT of main.cpp because <windows.h> clashes with raylib's
// Rectangle/ShowCursor/CloseWindow declarations. Includes windows.h freely.
#ifdef _WIN32

#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

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

#endif // _WIN32
