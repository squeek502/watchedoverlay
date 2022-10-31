const std = @import("std");
const windows = std.os.windows;

pub extern "advapi32" fn RegCreateKeyExW(
    hKey: windows.HKEY,
    lpSubKey: ?windows.LPCWSTR,
    Reserved: windows.DWORD,
    lpClass: ?windows.LPWSTR,
    dwOptions: windows.DWORD,
    samDesired: windows.REGSAM,
    lpSecurityAttributes: ?*anyopaque, // pointer to a SECURITY_ATTRIBUTES struct, we won't need to use it
    phkResult: *windows.HKEY,
    lpdwDisposition: ?*windows.DWORD,
) callconv(windows.WINAPI) windows.LSTATUS;

pub extern "advapi32" fn RegSetValueExW(
    hKey: windows.HKEY,
    lpValueName: ?windows.LPCWSTR,
    Reserved: windows.DWORD,
    dwType: windows.DWORD,
    lpData: [*]const windows.BYTE,
    cbData: windows.DWORD,
) callconv(windows.WINAPI) windows.LSTATUS;

pub extern "advapi32" fn RegCloseKey(hKey: windows.HKEY) callconv(windows.WINAPI) windows.LSTATUS;

pub extern "shlwapi" fn SHDeleteKeyW(hKey: windows.HKEY, pszSubKey: ?windows.LPCWSTR) callconv(windows.WINAPI) windows.LSTATUS;

pub const REG_OPTION_NON_VOLATILE = 0;
pub const KEY_WRITE = 0x20006; // Combines the STANDARD_RIGHTS_WRITE, KEY_SET_VALUE, and KEY_CREATE_SUB_KEY access rights.
pub const REG_SZ = 1;
pub const HKEY_CLASSES_ROOT: windows.HKEY = @intToPtr(windows.HKEY, @as(usize, 0x80000000));
pub const HKEY_LOCAL_MACHINE: windows.HKEY = @intToPtr(windows.HKEY, @as(usize, 0x80000002));

pub fn createAndSetStringValue(hkey: windows.HKEY, sub_key: [:0]const u16, name: ?[:0]const u16, value: [:0]const u16) !void {
    var write_key: windows.HKEY = undefined;
    const create_status = RegCreateKeyExW(hkey, sub_key.ptr, 0, null, REG_OPTION_NON_VOLATILE, KEY_WRITE, null, &write_key, null);
    if (create_status != @enumToInt(windows.Win32Error.SUCCESS)) {
        const err = @intToEnum(windows.Win32Error, create_status);
        switch (err) {
            .ACCESS_DENIED => return error.AccessDenied,
            else => return windows.unexpectedError(err),
        }
    }
    defer _ = RegCloseKey(write_key);

    // If the data is of type REG_SZ, REG_EXPAND_SZ, or REG_MULTI_SZ, cbData must include the size of the terminating null character or characters.
    // https://docs.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsetvalueexw
    const data_size_in_bytes = @intCast(u32, (value.len + 1) * @sizeOf(u16));
    const name_ptr: ?windows.LPCWSTR = if (name != null) name.?.ptr else null;
    const set_status = RegSetValueExW(write_key, name_ptr, 0, REG_SZ, @alignCast(1, std.mem.sliceAsBytes(value).ptr), data_size_in_bytes);
    if (set_status != @enumToInt(windows.Win32Error.SUCCESS)) {
        const err = @intToEnum(windows.Win32Error, set_status);
        switch (err) {
            .ACCESS_DENIED => return error.AccessDenied,
            else => return windows.unexpectedError(err),
        }
    }
}

/// Wrapper over SHDeleteKeyW that doesn't error if the key is not found
pub fn deleteTree(hkey: windows.HKEY, sub_key: [:0]const u16) !void {
    const status = SHDeleteKeyW(hkey, sub_key);
    if (status != @enumToInt(windows.Win32Error.SUCCESS)) {
        const err = @intToEnum(windows.Win32Error, status);
        switch (err) {
            .FILE_NOT_FOUND => {}, // no problem
            .ACCESS_DENIED => return error.AccessDenied,
            else => return std.os.windows.unexpectedError(err),
        }
    }
}

pub fn registerInprocServer(comptime clsid: []const u8, dll_path: [:0]const u16, name: [:0]const u16) !void {
    const clsid_key = std.unicode.utf8ToUtf16LeStringLiteral("CLSID\\" ++ clsid);
    const inproc_key = std.unicode.utf8ToUtf16LeStringLiteral("CLSID\\" ++ clsid ++ "\\" ++ "InprocServer32");
    try createAndSetStringValue(HKEY_CLASSES_ROOT, clsid_key, null, name);
    try createAndSetStringValue(HKEY_CLASSES_ROOT, inproc_key, null, dll_path);
    // TODO: Investigate other threading models and if they are worth using/supporting
    const threading_model_name = std.unicode.utf8ToUtf16LeStringLiteral("ThreadingModel");
    const threading_model_value = std.unicode.utf8ToUtf16LeStringLiteral("Apartment");
    try createAndSetStringValue(HKEY_CLASSES_ROOT, inproc_key, threading_model_name, threading_model_value);
}

pub fn unregisterInprocServer(comptime clsid: []const u8) !void {
    const clsid_key = std.unicode.utf8ToUtf16LeStringLiteral("CLSID\\" ++ clsid);
    try deleteTree(HKEY_CLASSES_ROOT, clsid_key);
}

const context_menu_key_infix = "\\shellex\\ContextMenuHandlers\\";

pub fn registerContextMenu(comptime target_type: []const u8, comptime name: []const u8, comptime clsid: []const u8) !void {
    const key = std.unicode.utf8ToUtf16LeStringLiteral(target_type ++ context_menu_key_infix ++ name);
    const clsid_w = std.unicode.utf8ToUtf16LeStringLiteral(clsid);
    try createAndSetStringValue(HKEY_CLASSES_ROOT, key, null, clsid_w);
}

pub fn unregisterContextMenu(comptime target_type: []const u8, comptime name: []const u8) !void {
    const key = std.unicode.utf8ToUtf16LeStringLiteral(target_type ++ context_menu_key_infix ++ name);
    try deleteTree(HKEY_CLASSES_ROOT, key);
}

const overlay_key_prefix = "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ShellIconOverlayIdentifiers\\";

pub fn registerOverlay(comptime name: []const u8, comptime clsid: []const u8) !void {
    const key = std.unicode.utf8ToUtf16LeStringLiteral(overlay_key_prefix ++ name);
    const clsid_w = std.unicode.utf8ToUtf16LeStringLiteral(clsid);
    try createAndSetStringValue(HKEY_LOCAL_MACHINE, key, null, clsid_w);
}

pub fn unregisterOverlay(comptime name: []const u8) !void {
    const key = std.unicode.utf8ToUtf16LeStringLiteral(overlay_key_prefix ++ name);
    try deleteTree(HKEY_LOCAL_MACHINE, key);
}
