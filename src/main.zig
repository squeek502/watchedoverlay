const std = @import("std");
const com = @import("com.zig");
const windows = std.os.windows;
const windows_extra = @import("windows_extra.zig");
const Db = @import("db.zig").Db;

var global_allocator_inst = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = global_allocator_inst.allocator();

var obj_count: windows.LONG = 0;
var lock_count: windows.LONG = 0;
var dll_file_name_w_buf: [windows.PATH_MAX_WIDE:0]u16 = undefined;
var dll_file_name_w: [:0]const u16 = &[_:0]u16{};
var dll_file_name_buf: [windows.PATH_MAX_WIDE]u8 = undefined;
var dll_file_name: []const u8 = &[_]u8{};
var db: Db = undefined;
var has_db: bool = false;

const sqlite_db_name = "watched.sqlite";

const debug_log_name = "log.txt";
var debug_log_path: []const u8 = undefined;
var debug_log: std.fs.File = undefined;
var has_debug_log: bool = false;

pub fn DllMain(hinstDLL: windows.HINSTANCE, dwReason: windows.DWORD, lpReserved: windows.LPVOID) callconv(windows.WINAPI) windows.BOOL {
    _ = lpReserved;
    switch (dwReason) {
        windows_extra.DLL_PROCESS_ATTACH => {
            dll_file_name_w = windows.GetModuleFileNameW(
                @ptrCast(windows.HMODULE, hinstDLL),
                &dll_file_name_w_buf,
                dll_file_name_w_buf.len,
            ) catch {
                return windows.FALSE;
            };

            const len = std.unicode.utf16leToUtf8(&dll_file_name_buf, dll_file_name_w) catch {
                return windows.FALSE;
            };
            dll_file_name = dll_file_name_buf[0..len];

            const dll_dir = std.fs.path.dirname(dll_file_name).?;
            const sqlite_file_path = std.fs.path.joinZ(global_allocator, &.{ dll_dir, sqlite_db_name }) catch {
                return windows.FALSE;
            };
            defer global_allocator.free(sqlite_file_path);

            debug_log_path = std.fs.path.join(global_allocator, &.{ dll_dir, debug_log_name }) catch {
                return windows.FALSE;
            };
            debug_log = std.fs.cwd().createFile(debug_log_path, .{ .truncate = false }) catch return windows.FALSE;
            has_debug_log = true;
            debug_log.seekFromEnd(0) catch return windows.FALSE;

            db = Db.init(sqlite_file_path) catch return windows.FALSE;
            has_db = true;
        },
        windows_extra.DLL_PROCESS_DETACH => {
            if (has_db) {
                db.deinit();
                has_db = false;
            }
            if (has_debug_log) {
                debug_log.close();
                has_debug_log = false;
            }
        },

        windows_extra.DLL_THREAD_ATTACH, windows_extra.DLL_THREAD_DETACH => {},

        else => {},
    }
    return windows.TRUE;
}

export fn DllGetClassObject(rclsid: *const windows.GUID, riid: *const windows.GUID, ppv: ?*?*anyopaque) callconv(windows.WINAPI) windows.HRESULT {
    if (com.IsEqualCLSID(rclsid, IWatchedShellOverlayIdentifer.CLSID)) {
        const unconst_ptr = @intToPtr(*IWatchedClassFactory, @ptrToInt(&IWatchedClassFactory.inst));
        return IWatchedClassFactory.inst.vtable.unknown.QueryInterface(unconst_ptr, riid, ppv);
    } else {
        ppv.?.* = null;
        return windows_extra.CLASS_E_CLASSNOTAVAILABLE;
    }
}

export fn DllCanUnloadNow() callconv(windows.WINAPI) windows.HRESULT {
    return if (obj_count > 0 or lock_count > 0) windows_extra.S_FALSE else windows.S_OK;
}

export fn DllRegisterServer() callconv(windows.WINAPI) windows.HRESULT {
    return windows.S_OK;
}

export fn DllUnregisterServer() callconv(windows.WINAPI) windows.HRESULT {
    return windows.S_OK;
}

pub const IWatchedShellOverlayIdentifer = extern struct {
    const Self = @This();
    const VTable = extern struct {
        unknown: com.IUnknown.VTable(Self),
        shell_overlay: com.IShellIconOverlayIdentifier.VTable(Self),
    };

    vtable: *const Self.VTable,
    ref: u32,

    const CLSID_String = "{0c781461-65a7-4d7a-8c33-bf0a9b9fd362}";
    const CLSID_Value = windows.GUID.parse(CLSID_String);
    pub const CLSID = &CLSID_Value;

    const IID_String = "{e85595ed-c37f-4498-86b8-115b0035e6fd}";
    const IID_Value = windows.GUID.parse(IID_String);
    pub const IID = &IID_Value;

    pub fn QueryInterface(
        self: *Self,
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        if (!com.IsEqualIID(riid.?, Self.IID) and !com.IsEqualIID(riid.?, com.IShellIconOverlayIdentifier.IID)) {
            ppvObject.?.* = null;
            return windows.E_NOINTERFACE;
        }

        ppvObject.?.* = self;

        _ = self.vtable.unknown.AddRef(self);

        return windows.S_OK;
    }

    pub fn AddRef(self: *Self) callconv(windows.WINAPI) u32 {
        self.ref += 1;
        return self.ref;
    }

    pub fn Release(self: *Self) callconv(windows.WINAPI) u32 {
        self.ref -= 1;

        if (self.ref == 0) {
            global_allocator.destroy(self);
            obj_count -= 1;
            //_ = windows_extra.InterlockedDecrement(&obj_count);
            return 0;
        }

        return self.ref;
    }

    pub fn IsMemberOf(
        self: *Self,
        pwszPath: windows.LPCWSTR, // [in]
        dwAttrib: windows.DWORD,
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;
        _ = dwAttrib;

        const pathw = pwszPath[0..std.mem.len(pwszPath)];
        if (db.isWatchedW(pathw)) {
            return windows.S_OK;
        } else {
            return windows_extra.S_FALSE;
        }
    }

    pub fn GetInfoOverlay(
        self: *Self,
        pwszIconFile: ?windows.LPWSTR, // [out]
        cchMax: c_int,
        pIndex: ?*c_int, // [out]
        pdwFlags: ?*windows.DWORD, // [out]
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;

        if (pwszIconFile == null) {
            return windows.E_POINTER;
        }
        if (pIndex == null) {
            return windows.E_POINTER;
        }
        if (pdwFlags == null) {
            return windows.E_POINTER;
        }
        if (cchMax < 1) {
            return windows.E_INVALIDARG;
        }

        std.mem.copy(u16, (pwszIconFile.?)[0..@intCast(usize, cchMax)], dll_file_name_w[0 .. dll_file_name_w.len + 1]);

        pIndex.?.* = 0;
        pdwFlags.?.* = windows_extra.ISIOI_ICONFILE | windows_extra.ISIOI_ICONINDEX;

        return windows.S_OK;
    }

    pub fn GetPriority(
        self: *Self,
        pPriority: ?*c_int, // [out]
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;
        if (pPriority.?.* != 0) {
            return windows.E_INVALIDARG;
        }
        pPriority.?.* = 0;
        return windows.S_OK;
    }

    pub const vtable_impl: Self.VTable = .{
        .unknown = .{
            .QueryInterface = QueryInterface,
            .AddRef = AddRef,
            .Release = Release,
        },
        .shell_overlay = .{
            .GetInfoOverlay = GetInfoOverlay,
            .GetPriority = GetPriority,
            .IsMemberOf = IsMemberOf,
        },
    };
};

pub const IWatchedClassFactory = extern struct {
    const Self = @This();
    const VTable = extern struct {
        unknown: com.IUnknown.VTable(Self),
        class_factory: com.IClassFactory.VTable(Self),
    };

    vtable: *const Self.VTable,

    pub fn QueryInterface(
        self: *Self,
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        if (!com.IsEqualIID(riid.?, com.IUnknown.IID) and !com.IsEqualIID(riid.?, com.IClassFactory.IID)) {
            ppvObject.?.* = null;
            return windows.E_NOINTERFACE;
        }

        ppvObject.?.* = self;

        _ = self.vtable.unknown.AddRef(self);

        return windows.S_OK;
    }

    /// Don't need to count references since we statically allocate the
    /// only instance
    pub fn AddRef(self: *Self) callconv(windows.WINAPI) u32 {
        _ = self;
        return 1;
    }

    /// Don't need to count references since we statically allocate the
    /// only instance
    pub fn Release(self: *Self) callconv(windows.WINAPI) u32 {
        _ = self;
        return 1;
    }

    pub fn CreateInstance(
        self: *Self,
        pUnkOuter: ?*com.IUnknown,
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;

        if (pUnkOuter != null) {
            return windows_extra.CLASS_E_NOAGGREGATION;
        }

        var obj = global_allocator.create(IWatchedShellOverlayIdentifer) catch {
            return windows.E_OUTOFMEMORY;
        };

        obj.vtable = &IWatchedShellOverlayIdentifer.vtable_impl;
        obj.ref = 1;

        const result = obj.vtable.unknown.QueryInterface(obj, riid, ppvObject);
        // Release to decrement reference count after it was incremented in the
        // QueryInterface call
        _ = obj.vtable.unknown.Release(obj);

        obj_count += 1;
        //_ = windows_extra.InterlockedIncrement(&obj_count);

        return result;
    }

    pub fn LockServer(
        self: *Self,
        fLock: windows.BOOL,
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;

        if (fLock != 0) {
            lock_count += 1;
            //_ = windows_extra.InterlockedIncrement(&lock_count);
        } else {
            lock_count -= 1;
            //_ = windows_extra.InterlockedDecrement(&lock_count);
        }
        return windows.S_OK;
    }

    pub const vtable_impl: Self.VTable = .{
        .unknown = .{
            .QueryInterface = QueryInterface,
            .AddRef = AddRef,
            .Release = Release,
        },
        .class_factory = .{
            .CreateInstance = CreateInstance,
            .LockServer = LockServer,
        },
    };
    pub const inst = Self{ .vtable = &vtable_impl };
};

test {
    _ = std.testing.refAllDecls(@This());
}
