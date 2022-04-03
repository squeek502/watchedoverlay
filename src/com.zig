const std = @import("std");
const windows = std.os.windows;
const testing = std.testing;

pub const IUnknown = extern struct {
    vtable: *VTable(IUnknown),

    const IID_Value = windows.GUID.parse("{00000000-0000-0000-c000-000000000046}");
    pub const IID = &IID_Value;

    pub fn VTable(comptime T: type) type {
        return extern struct {
            QueryInterface: fn (
                self: *T,
                riid: ?*const windows.GUID,
                ppvObject: ?*?*anyopaque,
            ) callconv(windows.WINAPI) windows.HRESULT,
            AddRef: fn (
                self: *T,
            ) callconv(windows.WINAPI) u32,
            Release: fn (
                self: *T,
            ) callconv(windows.WINAPI) u32,
        };
    }
};

pub const IShellIconOverlayIdentifier = extern struct {
    vtable: *extern struct {
        unknown: IUnknown.VTable(IShellIconOverlayIdentifier),
        shell_overlay: VTable(IShellIconOverlayIdentifier),
    },

    const IID_Value = windows.GUID.parse("{0c6c4200-c589-11d0-999a-00c04fd655e1}");
    pub const IID = &IID_Value;

    pub fn VTable(comptime T: type) type {
        return extern struct {
            IsMemberOf: fn (
                self: *T,
                pwszPath: windows.LPCWSTR, // [in]
                dwAttrib: windows.DWORD,
            ) callconv(windows.WINAPI) windows.HRESULT,
            GetInfoOverlay: fn (
                self: *T,
                pwszIconFile: ?windows.LPWSTR, // [out]
                cchMax: c_int,
                pIndex: ?*c_int, // [out]
                pdwFlags: ?*windows.DWORD, // [out]
            ) callconv(windows.WINAPI) windows.HRESULT,
            GetPriority: fn (
                self: *T,
                pPriority: ?*c_int, // [out]
            ) callconv(windows.WINAPI) windows.HRESULT,
        };
    }
};

pub const IClassFactory = extern struct {
    vtable: *extern struct {
        unknown: IUnknown.VTable(IClassFactory),
        class_factory: VTable(IClassFactory),
    },

    const IID_Value = windows.GUID.parse("{00000001-0000-0000-c000-000000000046}");
    pub const IID = &IID_Value;

    pub fn VTable(comptime T: type) type {
        return extern struct {
            CreateInstance: fn (
                self: *T,
                pUnkOuter: ?*IUnknown,
                riid: ?*const windows.GUID,
                ppvObject: ?*?*anyopaque,
            ) callconv(windows.WINAPI) windows.HRESULT,
            LockServer: fn (
                self: *T,
                fLock: windows.BOOL,
            ) callconv(windows.WINAPI) windows.HRESULT,
        };
    }
};

pub fn IsEqualGUID(a: *const windows.GUID, b: *const windows.GUID) bool {
    return std.meta.eql(a.*, b.*);
}
pub const IsEqualIID = IsEqualGUID;
pub const IsEqualCLSID = IsEqualGUID;

test "IsEqualGUID" {
    const a = windows.GUID.parse("{01234567-89AB-EF10-3254-7698badcfe91}");
    const b = windows.GUID.parse("{01234567-89AB-EF10-3254-7698badcfe91}");
    const c = windows.GUID.parse("{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}");

    try testing.expect(IsEqualGUID(&a, &b));
    try testing.expect(!IsEqualGUID(&a, &c));

    const a_ptr: ?*const windows.GUID = &a;
    const b_ptr = &b;
    try testing.expect(IsEqualGUID(a_ptr.?, b_ptr));
}
