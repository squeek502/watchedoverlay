const windows = @import("std").os.windows;

pub const ISIOI_ICONFILE: windows.DWORD = 0x1;
pub const ISIOI_ICONINDEX: windows.DWORD = 0x2;

pub const CLASS_E_NOAGGREGATION: windows.HRESULT = @bitCast(c_long, @as(c_ulong, 0x80040110));
pub const CLASS_E_CLASSNOTAVAILABLE: windows.HRESULT = @bitCast(c_long, @as(c_ulong, 80040111));

pub const S_FALSE: windows.HRESULT = 1;

pub const DLL_PROCESS_ATTACH: windows.DWORD = 1;
pub const DLL_PROCESS_DETACH: windows.DWORD = 0;
pub const DLL_THREAD_ATTACH: windows.DWORD = 2;
pub const DLL_THREAD_DETACH: windows.DWORD = 3;

pub extern "kernel32" fn InterlockedIncrement(
    Addend: ?*volatile windows.LONG,
) callconv(windows.WINAPI) windows.LONG;

pub extern "kernel32" fn InterlockedDecrement(
    Addend: ?*volatile windows.LONG,
) callconv(windows.WINAPI) windows.LONG;
