const std = @import("std");
const com = @import("com.zig");
const windows = std.os.windows;
const windows_extra = @import("windows_extra.zig");

var global_allocator_inst = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = global_allocator_inst.allocator();

var obj_count: windows.LONG = 0;
var lock_count: windows.LONG = 0;

pub fn DllMain(hModule: windows.HINSTANCE, dwReason: windows.DWORD, lpReserved: windows.LPVOID) callconv(windows.WINAPI) windows.BOOL {
    _ = hModule;
    _ = dwReason;
    _ = lpReserved;
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
        // need to prefix the path with \??\ to be a valid input to Zig's OpenFile interface
        const prefixed_path = windows.wToPrefixedFileW(std.mem.span(pwszPath)) catch {
            return windows.E_FAIL;
        };

        // need to call OpenFile directly to be able to call it on files OR directories, AFAICT Zig's
        // fs only offers one or the other currently.
        const handle = windows.OpenFile(prefixed_path.span(), .{
            .access_mask = windows.GENERIC_READ | windows.FILE_READ_ATTRIBUTES | windows.SYNCHRONIZE,
            .creation = windows.FILE_OPEN,
            .io_mode = .blocking,
            .filter = .any,
        }) catch {
            return windows.E_FAIL;
        };
        const file = std.fs.File{ .handle = handle };
        defer file.close();

        const stat = file.stat() catch {
            return windows.E_FAIL;
        };
        if (stat.size < 2) {
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

        // TODO embed an icon in the dll, get it from there
        const ico_path_utf16 = std.unicode.utf8ToUtf16LeStringLiteral("C:\\Windows\\SystemApps\\Microsoft.Windows.SecHealthUI_cw5n1h2txyewy\\Assets\\Threat.contrast-white.ico");
        std.mem.copy(u16, (pwszIconFile.?)[0..@intCast(usize, cchMax)], ico_path_utf16[0 .. ico_path_utf16.len + 1]);

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
