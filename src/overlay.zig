const std = @import("std");
const com = @import("com.zig");
const windows = std.os.windows;
const windows_extra = @import("windows_extra.zig");
const main = @import("dllmain.zig");

pub const WatchedOverlay = extern struct {
    const Self = @This();
    const VTable = extern struct {
        unknown: com.IUnknown.VTable(Self),
        shell_overlay: com.IShellIconOverlayIdentifier.VTable(Self),
    };

    vtable: *const Self.VTable,
    ref: u32,

    pub const CLSID_String = "{0c781461-65a7-4d7a-8c33-bf0a9b9fd362}";
    const CLSID_Value = windows.GUID.parse(CLSID_String);
    pub const CLSID = &CLSID_Value;

    pub const IID_String = "{e85595ed-c37f-4498-86b8-115b0035e6fd}";
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
            main.global_allocator.destroy(self);
            _ = @atomicRmw(windows.LONG, &main.obj_count, .Sub, 1, .monotonic);
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
        if (main.db.isWatchedW(pathw)) {
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
        if (main.dll_file_name_w.len + 1 > cchMax) {
            return windows_extra.HRESULT_FROM_WIN32(.INSUFFICIENT_BUFFER);
        }

        @memcpy((pwszIconFile.?)[0 .. main.dll_file_name_w.len + 1], main.dll_file_name_w[0 .. main.dll_file_name_w.len + 1]);

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

    pub fn create(
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        var obj = main.global_allocator.create(WatchedOverlay) catch {
            return windows.E_OUTOFMEMORY;
        };

        obj.* = .{
            .vtable = &WatchedOverlay.vtable_impl,
            .ref = 1,
        };

        const result = obj.vtable.unknown.QueryInterface(obj, riid, ppvObject);
        // since we set everything up before this call, any error is a failure on our part
        std.debug.assert(result == windows.S_OK);
        // Release to decrement reference count after it was incremented in the
        // QueryInterface call
        _ = obj.vtable.unknown.Release(obj);

        _ = @atomicRmw(windows.LONG, &main.obj_count, .Add, 1, .monotonic);

        return result;
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
