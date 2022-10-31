const std = @import("std");
const windows = std.os.windows;
const windows_extra = @import("windows_extra.zig");
const testing = std.testing;

pub const IUnknown = extern struct {
    vtable: *VTable(IUnknown),

    const IID_Value = windows.GUID.parse("{00000000-0000-0000-c000-000000000046}");
    pub const IID = &IID_Value;

    pub fn VTable(comptime T: type) type {
        return extern struct {
            QueryInterface: std.meta.FnPtr(fn (
                self: *T,
                riid: ?*const windows.GUID,
                ppvObject: ?*?*anyopaque,
            ) callconv(windows.WINAPI) windows.HRESULT),
            AddRef: std.meta.FnPtr(fn (
                self: *T,
            ) callconv(windows.WINAPI) u32),
            Release: std.meta.FnPtr(fn (
                self: *T,
            ) callconv(windows.WINAPI) u32),
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
            IsMemberOf: std.meta.FnPtr(fn (
                self: *T,
                pwszPath: windows.LPCWSTR, // [in]
                dwAttrib: windows.DWORD,
            ) callconv(windows.WINAPI) windows.HRESULT),
            GetInfoOverlay: std.meta.FnPtr(fn (
                self: *T,
                pwszIconFile: ?windows.LPWSTR, // [out]
                cchMax: c_int,
                pIndex: ?*c_int, // [out]
                pdwFlags: ?*windows.DWORD, // [out]
            ) callconv(windows.WINAPI) windows.HRESULT),
            GetPriority: std.meta.FnPtr(fn (
                self: *T,
                pPriority: ?*c_int, // [out]
            ) callconv(windows.WINAPI) windows.HRESULT),
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
            CreateInstance: std.meta.FnPtr(fn (
                self: *T,
                pUnkOuter: ?*IUnknown,
                riid: ?*const windows.GUID,
                ppvObject: ?*?*anyopaque,
            ) callconv(windows.WINAPI) windows.HRESULT),
            LockServer: std.meta.FnPtr(fn (
                self: *T,
                fLock: windows.BOOL,
            ) callconv(windows.WINAPI) windows.HRESULT),
        };
    }
};

pub const IShellExtInit = extern struct {
    vtable: *extern struct {
        unknown: IUnknown.VTable(IShellExtInit),
        shell_ext: VTable(IShellExtInit),
    },

    const IID_Value = windows.GUID.parse("{000214e8-0000-0000-c000-000000000046}");
    pub const IID = &IID_Value;

    pub fn VTable(comptime T: type) type {
        return extern struct {
            Initialize: std.meta.FnPtr(fn (
                self: *T,
                pidlFolder: windows_extra.PCIDLIST_ABSOLUTE,
                pdtobj: ?*IDataObject,
                hkeyProgID: windows.HKEY,
            ) callconv(windows.WINAPI) windows.HRESULT),
        };
    }
};

pub const IContextMenu = extern struct {
    vtable: *extern struct {
        unknown: IUnknown.VTable(IContextMenu),
        context_menu: VTable(IContextMenu),
    },

    const IID_Value = windows.GUID.parse("{000214e4-0000-0000-c000-000000000046}");
    pub const IID = &IID_Value;

    pub fn VTable(comptime T: type) type {
        return extern struct {
            QueryContextMenu: std.meta.FnPtr(fn (
                self: *T,
                hmenu: ?windows.HMENU,
                indexMenu: windows.UINT,
                idCmdFirst: windows.UINT,
                idCmdLast: windows.UINT,
                uFlags: windows.UINT,
            ) callconv(windows.WINAPI) windows.HRESULT),
            InvokeCommand: std.meta.FnPtr(fn (
                self: *T,
                pici: ?*CMINVOKECOMMANDINFO,
            ) callconv(windows.WINAPI) windows.HRESULT),
            GetCommandString: std.meta.FnPtr(fn (
                self: *T,
                idCmd: windows_extra.UINT_PTR,
                uType: GCS,
                pReserved: ?*windows.UINT,
                pszName: ?[*]windows.CHAR,
                cchMax: windows.UINT,
            ) callconv(windows.WINAPI) windows.HRESULT),
        };
    }
};

// QueryContextMenu uFlags
pub const CMF_NORMAL: windows.UINT = 0x00000000;
pub const CMF_DEFAULTONLY: windows.UINT = 0x00000001;
pub const CMF_VERBSONLY: windows.UINT = 0x00000002;
pub const CMF_EXPLORE: windows.UINT = 0x00000004;
pub const CMF_NOVERBS: windows.UINT = 0x00000008;
pub const CMF_CANRENAME: windows.UINT = 0x00000010;
pub const CMF_NODEFAULT: windows.UINT = 0x00000020;
pub const CMF_INCLUDESTATIC: windows.UINT = 0x00000040;
pub const CMF_ITEMMENU: windows.UINT = 0x00000080;
pub const CMF_EXTENDEDVERBS: windows.UINT = 0x00000100;
pub const CMF_DISABLEDVERBS: windows.UINT = 0x00000200;
pub const CMF_ASYNCVERBSTATE: windows.UINT = 0x00000400;
pub const CMF_OPTIMIZEFORINVOKE: windows.UINT = 0x00000800;
pub const CMF_SYNCCASCADEMENU: windows.UINT = 0x00001000;
pub const CMF_DONOTPICKDEFAULT: windows.UINT = 0x00002000;
pub const CMF_RESERVED: windows.UINT = 0xffff0000;

// GetCommandString uType
pub const GCS = enum(windows.UINT) {
    VERBA = 0x00000000,
    HELPTEXTA = 0x00000001,
    VALIDATEA = 0x00000002,
    VERBW = 0x00000004,
    HELPTEXTW = 0x00000005,
    VALIDATEW = 0x00000006,
    VERBICONW = 0x00000014,
};
pub const GCS_VERBA = GCS.VERBA;
pub const GCS_HELPTEXTA = GCS.HELPTEXTA;
pub const GCS_VALIDATEA = GCS.VALIDATEA;
pub const GCS_VERBW = GCS.VERBW;
pub const GCS_HELPTEXTW = GCS.HELPTEXTW;
pub const GCS_VALIDATEW = GCS.VALIDATEW;
pub const GCS_VERBICONW = GCS.VERBICONW;

pub const CMINVOKECOMMANDINFO = extern struct {
    cbSize: windows.DWORD,
    fMask: windows.DWORD,
    hwnd: ?windows.HWND,
    lpVerb: ?windows.LPCSTR,
    lpParameters: ?windows.LPCSTR,
    lpDirectory: ?windows.LPCSTR,
    nShow: c_int,
    dwHotKey: windows.DWORD,
    hIcon: ?windows.HANDLE,
};

pub const IDataObject = extern struct {
    vtable: *extern struct {
        unknown: IUnknown.VTable(IDataObject),
        data_object: VTable(IDataObject),
    },

    const IID_Value = windows.GUID.parse("{0000010e-0000-0000-C000-000000000046}");
    pub const IID = &IID_Value;

    pub fn VTable(comptime T: type) type {
        return extern struct {
            GetData: std.meta.FnPtr(fn (
                self: *T,
                pformatetcIn: ?*FORMATETC,
                pmedium: ?*STGMEDIUM,
            ) callconv(windows.WINAPI) windows.HRESULT),
            GetDataHere: *anyopaque,
            QueryGetData: *anyopaque,
            GetCanonicalFormatEtc: *anyopaque,
            SetData: *anyopaque,
            EnumFormatEtc: *anyopaque,
            DAdvise: *anyopaque,
            DUnadvise: *anyopaque,
            EnumDAdvise: *anyopaque,
        };
    }
};

pub const TYMED = enum(u32) {
    HGLOBAL = 1,
    FILE = 2,
    ISTREAM = 4,
    ISTORAGE = 8,
    GDI = 16,
    MFPICT = 32,
    ENHMF = 64,
    NULL = 0,
};
pub const TYMED_HGLOBAL = TYMED.HGLOBAL;
pub const TYMED_FILE = TYMED.FILE;
pub const TYMED_ISTREAM = TYMED.ISTREAM;
pub const TYMED_ISTORAGE = TYMED.ISTORAGE;
pub const TYMED_GDI = TYMED.GDI;
pub const TYMED_MFPICT = TYMED.MFPICT;
pub const TYMED_ENHMF = TYMED.ENHMF;
pub const TYMED_NULL = TYMED.NULL;

pub const STGMEDIUM = extern struct {
    tymed: TYMED,
    Anonymous: extern union {
        hBitmap: ?*anyopaque,
        hMetaFilePict: ?*anyopaque,
        hEnhMetaFile: ?*anyopaque,
        hGlobal: ?windows_extra.HGLOBAL,
        lpszFileName: ?windows.PWSTR,
        pstm: ?*anyopaque,
        pstg: ?*anyopaque,
    },
    pUnkForRelease: ?*IUnknown,
};
pub extern "ole32" fn ReleaseStgMedium(stg: ?*STGMEDIUM) callconv(windows.WINAPI) void;

pub const DVTARGETDEVICE = extern struct {
    tdSize: u32,
    tdDriverNameOffset: u16,
    tdDeviceNameOffset: u16,
    tdPortNameOffset: u16,
    tdExtDevmodeOffset: u16,
    tdData: [1]u8,
};

pub const FORMATETC = extern struct {
    cfFormat: windows_extra.CLIPBOARD_FORMATS,
    ptd: ?*DVTARGETDEVICE,
    dwAspect: DVASPECT,
    lindex: i32,
    tymed: TYMED,
};

pub const DVASPECT = enum(u32) {
    CONTENT = 1,
    THUMBNAIL = 2,
    ICON = 4,
    DOCPRINT = 8,
};
pub const DVASPECT_CONTENT = DVASPECT.CONTENT;
pub const DVASPECT_THUMBNAIL = DVASPECT.THUMBNAIL;
pub const DVASPECT_ICON = DVASPECT.ICON;
pub const DVASPECT_DOCPRINT = DVASPECT.DOCPRINT;

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
