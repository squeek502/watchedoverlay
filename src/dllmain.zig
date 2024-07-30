const std = @import("std");
const com = @import("com.zig");
const windows = std.os.windows;
const windows_extra = @import("windows_extra.zig");
const Db = @import("db.zig").Db;
const WatchedClassFactory = @import("factory.zig").WatchedClassFactory;
const WatchedOverlay = @import("overlay.zig").WatchedOverlay;
const WatchedContextMenu = @import("context_menu.zig").WatchedContextMenu;
const registry = @import("registry.zig");

pub const global_allocator = std.heap.c_allocator;

pub var obj_count: windows.LONG = 0;
pub var lock_count: windows.LONG = 0;
var dll_file_name_w_buf: [windows.PATH_MAX_WIDE:0]u16 = undefined;
pub var dll_file_name_w: [:0]const u16 = &[_:0]u16{};
var dll_file_name_buf: [windows.PATH_MAX_WIDE]u8 = undefined;
pub var dll_file_name: []const u8 = &[_]u8{};
pub var db: Db = undefined;
var has_db: bool = false;

const sqlite_db_name = "watched.sqlite";

pub fn DllMain(hinstDLL: windows.HINSTANCE, dwReason: windows.DWORD, lpReserved: windows.LPVOID) callconv(windows.WINAPI) windows.BOOL {
    _ = lpReserved;
    switch (dwReason) {
        windows_extra.DLL_PROCESS_ATTACH => {
            const len_w = windows.kernel32.GetModuleFileNameW(@ptrCast(hinstDLL), &dll_file_name_w_buf, dll_file_name_w_buf.len);
            if (len_w == 0) return windows.FALSE;
            dll_file_name_w = dll_file_name_w_buf[0..len_w :0];

            const len = std.unicode.utf16LeToUtf8(&dll_file_name_buf, dll_file_name_w) catch {
                return windows.FALSE;
            };
            dll_file_name = dll_file_name_buf[0..len];

            const dll_dir = std.fs.path.dirname(dll_file_name).?;
            const sqlite_file_path = std.fs.path.joinZ(global_allocator, &.{ dll_dir, sqlite_db_name }) catch {
                return windows.FALSE;
            };
            defer global_allocator.free(sqlite_file_path);

            db = Db.init(global_allocator, sqlite_file_path) catch return windows.FALSE;
            has_db = true;
        },
        windows_extra.DLL_PROCESS_DETACH => {
            if (has_db) {
                db.deinit();
                has_db = false;
            }
        },

        windows_extra.DLL_THREAD_ATTACH, windows_extra.DLL_THREAD_DETACH => {},

        else => {},
    }
    return windows.TRUE;
}

export fn DllGetClassObject(rclsid: *const windows.GUID, riid: *const windows.GUID, ppv: ?*?*anyopaque) callconv(windows.WINAPI) windows.HRESULT {
    if (com.IsEqualCLSID(rclsid, WatchedOverlay.CLSID)) {
        WatchedClassFactory.create(global_allocator, WatchedOverlay.create, riid, ppv) catch {
            return windows.E_OUTOFMEMORY;
        };
        return windows.S_OK;
    } else if (com.IsEqualCLSID(rclsid, WatchedContextMenu.CLSID)) {
        WatchedClassFactory.create(global_allocator, WatchedContextMenu.create, riid, ppv) catch {
            return windows.E_OUTOFMEMORY;
        };
        return windows.S_OK;
    } else {
        ppv.?.* = null;
        return windows_extra.CLASS_E_CLASSNOTAVAILABLE;
    }
}

export fn DllCanUnloadNow() callconv(windows.WINAPI) windows.HRESULT {
    return if (obj_count > 0 or lock_count > 0) windows_extra.S_FALSE else windows.S_OK;
}

export fn DllRegisterServer() callconv(windows.WINAPI) windows.HRESULT {
    registry.registerInprocServer(
        WatchedOverlay.CLSID_String,
        dll_file_name_w,
        std.unicode.utf8ToUtf16LeStringLiteral("WatchedOverlay"),
    ) catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.registerInprocServer(
        WatchedContextMenu.CLSID_String,
        dll_file_name_w,
        std.unicode.utf8ToUtf16LeStringLiteral("WatchedContextMenu"),
    ) catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.registerOverlay("   WatchedOverlay", WatchedOverlay.CLSID_String) catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.registerContextMenu("*", "WatchedContextMenu", WatchedContextMenu.CLSID_String) catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.registerContextMenu("Directory", "WatchedContextMenu", WatchedContextMenu.CLSID_String) catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    return windows.S_OK;
}

export fn DllUnregisterServer() callconv(windows.WINAPI) windows.HRESULT {
    registry.unregisterInprocServer(WatchedOverlay.CLSID_String) catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.unregisterInprocServer(WatchedContextMenu.CLSID_String) catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.unregisterOverlay("   WatchedOverlay") catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.unregisterContextMenu("*", "WatchedContextMenu") catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    registry.unregisterContextMenu("Directory", "WatchedContextMenu") catch |err| switch (err) {
        error.AccessDenied => return windows.E_ACCESSDENIED,
        error.Unexpected => return windows.E_UNEXPECTED,
    };
    return windows.S_OK;
}

test {
    _ = std.testing.refAllDecls(@This());
}
