const std = @import("std");
const windows = std.os.windows;

pub const HGLOBAL = windows.HANDLE;

pub extern "kernel32" fn GlobalLock(hMem: HGLOBAL) callconv(windows.WINAPI) ?windows.LPVOID;
pub extern "kernel32" fn GlobalUnlock(hMem: HGLOBAL) callconv(windows.WINAPI) windows.BOOL;

pub const HDROP = *opaque {};

pub extern "shell32" fn DragQueryFileW(
    hDrop: HDROP,
    iFile: windows.UINT,
    // NOTE: This is windows.LPWSTR but without the sentinel, since this is an input so the sentinel
    //       isn't relevant and we pass the length of the buffer in `cch`
    // TODO: Is this Zig defining LPWSTR incorrectly?
    //       > LPWSTR type is a 32-bit pointer to a string of 16-bit Unicode characters, which MAY be null-terminated
    //       From https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-dtyp/50e9ef83-d6fd-4e22-a34a-2c6b4e3c24f3
    lpszFile: ?[*]windows.WCHAR,
    cch: windows.UINT,
) callconv(windows.WINAPI) windows.UINT;
// https://docs.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-dragqueryfilew
// If the value of this parameter is 0xFFFFFFFF, DragQueryFile returns a count of the files dropped.
pub const DragQueryFile_GetCount: windows.UINT = 0xFFFFFFFF;

pub extern "shell32" fn SHChangeNotify(
    wEventId: windows.LONG,
    uFlags: windows.UINT,
    dwItem1: ?windows.LPCVOID,
    dwItem2: ?windows.LPCVOID,
) callconv(windows.WINAPI) void;

pub const SHCNE_UPDATEITEM: windows.LONG = 0x00002000;
pub const SHCNF_PATHW: windows.UINT = 0x0005;

const UnsignedHRESULT = std.meta.Int(.unsigned, @typeInfo(windows.HRESULT).Int.bits);
pub fn MAKE_HRESULT(severity: u1, facility: u16, code: u16) windows.HRESULT {
    var hr: UnsignedHRESULT = (@as(UnsignedHRESULT, severity) << 31) | (@as(UnsignedHRESULT, facility) << 16) | code;
    return @bitCast(hr);
}
pub fn HRESULT_CODE(hr: windows.HRESULT) u16 {
    return @intCast(@as(UnsignedHRESULT, @bitCast(hr)) & 0xFFFF);
}
pub fn HRESULT_FACILITY(hr: windows.HRESULT) u16 {
    return @intCast((@as(UnsignedHRESULT, @bitCast(hr)) >> 16) & 0x1FFF);
}
pub fn HRESULT_SEVERITY(hr: windows.HRESULT) u1 {
    return @intCast((@as(UnsignedHRESULT, @bitCast(hr)) >> 31) & 0x1);
}
pub fn HRESULT_FROM_WIN32(err: windows.Win32Error) windows.HRESULT {
    var hr: UnsignedHRESULT = (@as(UnsignedHRESULT, @intFromEnum(err)) & 0x0000FFFF) | (@as(UnsignedHRESULT, FACILITY_WIN32) << 16) | @as(UnsignedHRESULT, 0x80000000);
    return @bitCast(hr);
}

test "HRESULT" {
    const hr = MAKE_HRESULT(SEVERITY_ERROR, FACILITY_NULL, 5);
    try std.testing.expectEqual(SEVERITY_ERROR, HRESULT_SEVERITY(hr));
    try std.testing.expectEqual(FACILITY_NULL, HRESULT_FACILITY(hr));
    try std.testing.expectEqual(@as(u16, 5), HRESULT_CODE(hr));
}

pub const SEVERITY_SUCCESS: u1 = 0;
pub const SEVERITY_ERROR: u1 = 1;

pub const FACILITY_NULL: u16 = 0;
pub const FACILITY_WIN32: u16 = 7;

pub fn HIWORD(x: windows.DWORD) windows.WORD {
    return @intCast((x >> 16) & 0xFFFF);
}

pub fn LOWORD(x: windows.DWORD) windows.WORD {
    return @intCast(x & 0xFFFF);
}

// An unsigned integer, whose length is dependent on processor word size.
// https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-tsts/f959534d-51f2-4103-8fb5-812620efe49b
pub const UINT_PTR = usize;

pub extern "user32" fn InsertMenuW(
    hMenu: ?windows.HMENU,
    uPosition: windows.UINT,
    uFlags: windows.UINT,
    uIDNewItem: UINT_PTR,
    lpNewItem: ?windows.LPCWSTR,
) callconv(windows.WINAPI) windows.BOOL;

pub const MF_BYPOSITION: windows.UINT = 0x00000400;

pub const ISIOI_ICONFILE: windows.DWORD = 0x1;
pub const ISIOI_ICONINDEX: windows.DWORD = 0x2;

pub const CLASS_E_NOAGGREGATION: windows.HRESULT = @bitCast(@as(c_ulong, 0x80040110));
pub const CLASS_E_CLASSNOTAVAILABLE: windows.HRESULT = @bitCast(@as(c_ulong, 80040111));

pub const S_FALSE: windows.HRESULT = 1;

pub const DLL_PROCESS_ATTACH: windows.DWORD = 1;
pub const DLL_PROCESS_DETACH: windows.DWORD = 0;
pub const DLL_THREAD_ATTACH: windows.DWORD = 2;
pub const DLL_THREAD_DETACH: windows.DWORD = 3;

pub const SHITEMID = extern struct {
    cb: windows.USHORT,
    abID: [1]u8,
};

pub const ITEMIDLIST = extern struct {
    mkid: SHITEMID,
};

pub const PCIDLIST_ABSOLUTE = ?*const ITEMIDLIST;

pub const CLIPBOARD_FORMATS = enum(u16) {
    TEXT = 1,
    BITMAP = 2,
    METAFILEPICT = 3,
    SYLK = 4,
    DIF = 5,
    TIFF = 6,
    OEMTEXT = 7,
    DIB = 8,
    PALETTE = 9,
    PENDATA = 10,
    RIFF = 11,
    WAVE = 12,
    UNICODETEXT = 13,
    ENHMETAFILE = 14,
    HDROP = 15,
    LOCALE = 16,
    DIBV5 = 17,
    MAX = 18,
    OWNERDISPLAY = 128,
    DSPTEXT = 129,
    DSPBITMAP = 130,
    DSPMETAFILEPICT = 131,
    DSPENHMETAFILE = 142,
    PRIVATEFIRST = 512,
    PRIVATELAST = 767,
    GDIOBJFIRST = 768,
    GDIOBJLAST = 1023,
};
pub const CF_TEXT = CLIPBOARD_FORMATS.TEXT;
pub const CF_BITMAP = CLIPBOARD_FORMATS.BITMAP;
pub const CF_METAFILEPICT = CLIPBOARD_FORMATS.METAFILEPICT;
pub const CF_SYLK = CLIPBOARD_FORMATS.SYLK;
pub const CF_DIF = CLIPBOARD_FORMATS.DIF;
pub const CF_TIFF = CLIPBOARD_FORMATS.TIFF;
pub const CF_OEMTEXT = CLIPBOARD_FORMATS.OEMTEXT;
pub const CF_DIB = CLIPBOARD_FORMATS.DIB;
pub const CF_PALETTE = CLIPBOARD_FORMATS.PALETTE;
pub const CF_PENDATA = CLIPBOARD_FORMATS.PENDATA;
pub const CF_RIFF = CLIPBOARD_FORMATS.RIFF;
pub const CF_WAVE = CLIPBOARD_FORMATS.WAVE;
pub const CF_UNICODETEXT = CLIPBOARD_FORMATS.UNICODETEXT;
pub const CF_ENHMETAFILE = CLIPBOARD_FORMATS.ENHMETAFILE;
pub const CF_HDROP = CLIPBOARD_FORMATS.HDROP;
pub const CF_LOCALE = CLIPBOARD_FORMATS.LOCALE;
pub const CF_DIBV5 = CLIPBOARD_FORMATS.DIBV5;
pub const CF_MAX = CLIPBOARD_FORMATS.MAX;
pub const CF_OWNERDISPLAY = CLIPBOARD_FORMATS.OWNERDISPLAY;
pub const CF_DSPTEXT = CLIPBOARD_FORMATS.DSPTEXT;
pub const CF_DSPBITMAP = CLIPBOARD_FORMATS.DSPBITMAP;
pub const CF_DSPMETAFILEPICT = CLIPBOARD_FORMATS.DSPMETAFILEPICT;
pub const CF_DSPENHMETAFILE = CLIPBOARD_FORMATS.DSPENHMETAFILE;
pub const CF_PRIVATEFIRST = CLIPBOARD_FORMATS.PRIVATEFIRST;
pub const CF_PRIVATELAST = CLIPBOARD_FORMATS.PRIVATELAST;
pub const CF_GDIOBJFIRST = CLIPBOARD_FORMATS.GDIOBJFIRST;
pub const CF_GDIOBJLAST = CLIPBOARD_FORMATS.GDIOBJLAST;
