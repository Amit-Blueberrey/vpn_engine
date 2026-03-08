// wintun_fallback.cpp
//
// Module 3 (Windows): Wintun vs TAP-Windows Fallback Bridge.
//
// On older Windows 10 builds (before 1903/TH2), the modern Wintun.dll
// driver may fail to load. We detect this and silently fall back to the
// legacy TAP-Windows adapter (tap0901) which ships with OpenVPN or can
// be bundled separately.
//
// Build: Add to windows/runner/ CMakeLists.txt
//   target_sources(runner PRIVATE wintun_fallback.cpp)
//   target_link_libraries(runner PRIVATE Setupapi.lib)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <initguid.h>
#include <devguid.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

#pragma comment(lib, "setupapi.lib")

// ── TAP-Windows Constants ─────────────────────────────────────────────────────

// tap0901 component ID registered in HKLM\SYSTEM\CurrentControlSet\Control\Class
static const wchar_t* TAP_COMPONENT_ID   = L"tap0901";
static const wchar_t* TAP_ADAPTER_KEY    = L"SYSTEM\\CurrentControlSet\\Control\\Class"
                                           L"\\{4D36E972-E325-11CE-BFC1-08002BE10318}";

// ── Wintun detection ──────────────────────────────────────────────────────────

typedef void* WINTUN_ADAPTER_HANDLE;
typedef WINTUN_ADAPTER_HANDLE (WINAPI* WintunCreateAdapterFn)(
    LPCWSTR Name, LPCWSTR TunnelType, const GUID* RequestedGUID);

static HMODULE gWintunLib    = NULL;
static bool    gUsingWintun  = false;
static bool    gUsingTap     = false;

/**
 * TryLoadWintun
 *
 * Attempts to load wintun.dll from the executable directory.
 * Returns true if successful; false if the DLL is missing or fails to load
 * (e.g., kernel driver not signed for that Windows build).
 */
bool TryLoadWintun(const wchar_t* dllPath) {
    gWintunLib = LoadLibraryExW(dllPath, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (gWintunLib == NULL) {
        DWORD err = GetLastError();
        wprintf(L"[WintunFallback] LoadLibraryExW(%s) failed: error %lu\n", dllPath, err);
        return false;
    }

    // Minimal sanity check: make sure WintunCreateAdapter is exported.
    WintunCreateAdapterFn fnCreate =
        (WintunCreateAdapterFn)GetProcAddress(gWintunLib, "WintunCreateAdapter");
    if (fnCreate == NULL) {
        wprintf(L"[WintunFallback] WintunCreateAdapter not found in DLL\n");
        FreeLibrary(gWintunLib);
        gWintunLib = NULL;
        return false;
    }

    gUsingWintun = true;
    wprintf(L"[WintunFallback] Wintun loaded OK\n");
    return true;
}

// ── TAP-Windows detection and open ───────────────────────────────────────────

/**
 * FindTapAdapterGUID
 *
 * Enumerates the Windows device registry to find the first tap0901 adapter.
 * Writes the adapter GUID (e.g. "{12345678-...}") to `guidOut` (40 chars min).
 * Returns true if found.
 */
bool FindTapAdapterGUID(wchar_t* guidOut, DWORD guidOutLen) {
    HKEY hKey;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, TAP_ADAPTER_KEY,
                      0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        return false;
    }

    bool found = false;
    wchar_t subkeyName[MAX_PATH];
    DWORD subkeyLen = MAX_PATH;
    DWORD idx = 0;

    while (RegEnumKeyExW(hKey, idx++, subkeyName, &subkeyLen,
                          NULL, NULL, NULL, NULL) == ERROR_SUCCESS) {
        subkeyLen = MAX_PATH;
        HKEY hSubKey;
        if (RegOpenKeyExW(hKey, subkeyName, 0, KEY_READ, &hSubKey) != ERROR_SUCCESS) {
            continue;
        }

        wchar_t componentId[64];
        DWORD sz = sizeof(componentId);
        if (RegQueryValueExW(hSubKey, L"ComponentId", NULL, NULL,
                              (LPBYTE)componentId, &sz) == ERROR_SUCCESS) {
            if (_wcsicmp(componentId, TAP_COMPONENT_ID) == 0) {
                sz = guidOutLen * sizeof(wchar_t);
                if (RegQueryValueExW(hSubKey, L"NetCfgInstanceId", NULL, NULL,
                                      (LPBYTE)guidOut, &sz) == ERROR_SUCCESS) {
                    found = true;
                    RegCloseKey(hSubKey);
                    break;
                }
            }
        }
        RegCloseKey(hSubKey);
    }

    RegCloseKey(hKey);
    return found;
}

/**
 * OpenTapAdapter
 *
 * Opens a file handle to the TAP-Windows virtual network device.
 * The returned HANDLE can be used with ReadFile/WriteFile as a raw
 * layer-3 packet stream — equivalent to a TUN interface on Linux.
 */
HANDLE OpenTapAdapter(const wchar_t* guid) {
    wchar_t devicePath[256];
    _snwprintf_s(devicePath, 256, _TRUNCATE,
                 L"\\\\.\\Global\\%s.tap", guid);

    HANDLE hDev = CreateFileW(
        devicePath,
        GENERIC_READ | GENERIC_WRITE,
        0, NULL,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_SYSTEM | FILE_FLAG_OVERLAPPED,
        NULL
    );

    if (hDev == INVALID_HANDLE_VALUE) {
        wprintf(L"[WintunFallback] OpenTapAdapter(%s) failed: %lu\n",
                devicePath, GetLastError());
    } else {
        // Put into TUN mode (layer-3 only, no Ethernet header)
        DWORD tunMode = 1;
        DWORD bytesRet = 0;
        DeviceIoControl(hDev, 0x00120004 /*TAP_WIN_IOCTL_CONFIG_TUN*/,
                        &tunMode, sizeof(tunMode),
                        &tunMode, sizeof(tunMode),
                        &bytesRet, NULL);

        // Enable the adapter
        DWORD status = 1;
        DeviceIoControl(hDev, 0x00120018 /*TAP_WIN_IOCTL_SET_MEDIA_STATUS*/,
                        &status, sizeof(status),
                        &status, sizeof(status),
                        &bytesRet, NULL);

        wprintf(L"[WintunFallback] TAP adapter opened: %s\n", devicePath);
        gUsingTap = true;
    }
    return hDev;
}

// ── Main entry point (called by Dart FFI / Flutter Windows runner) ────────────

extern "C" {

/**
 * wg_open_tun_adapter
 *
 * Exported function called by Dart FFI (Windows only).
 * 1. Tries to load Wintun first.
 * 2. If that fails, falls back to TAP-Windows.
 * Returns:
 *   1  = success (Wintun)
 *   2  = success (TAP fallback)
 *   -1 = no suitable adapter found
 */
__declspec(dllexport)
int32_t wg_open_tun_adapter(const wchar_t* wintunDllPath, void** handleOut) {
    // Try Wintun first
    if (TryLoadWintun(wintunDllPath)) {
        *handleOut = (void*)gWintunLib;
        return 1;
    }

    // Fallback: locate TAP-Windows adapter
    wchar_t guid[40] = {};
    if (!FindTapAdapterGUID(guid, 40)) {
        wprintf(L"[WintunFallback] No TAP adapter found. Install Wintun or tap0901 driver.\n");
        *handleOut = NULL;
        return -1;
    }

    HANDLE tapHandle = OpenTapAdapter(guid);
    if (tapHandle == INVALID_HANDLE_VALUE) {
        *handleOut = NULL;
        return -1;
    }

    *handleOut = (void*)tapHandle;
    return 2; // TAP fallback in use
}

/**
 * wg_is_using_tap_fallback
 *
 * Returns 1 if we're running on the legacy TAP adapter, 0 for Wintun.
 */
__declspec(dllexport)
int32_t wg_is_using_tap_fallback() {
    return gUsingTap ? 1 : 0;
}

} // extern "C"
