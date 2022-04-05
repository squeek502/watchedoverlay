const std = @import("std");
const com = @import("com.zig");
const windows = std.os.windows;
const windows_extra = @import("windows_extra.zig");
const main = @import("dllmain.zig");

// The method used here to emulate multiple inheritance is to have two vtables,
// and then in QueryInterface we have different functionality depending on which
// type is being requested:
// - For IShellExtInit, we return the base pointer of the struct
//   since it'll work normally (its vtable is first)
// - For IContextMenu we return a pointer to the vtable_icontextmenu field and then
//   use some wrapper functions to get back to a *WatchedContextMenu before calling
//   the normal methods (see the _IContextMenu suffixed functions towards the
//   end of this struct definition).
// There's probably a better way to do this, but this seems to work.

pub const WatchedContextMenu = extern struct {
    const Self = @This();
    const VTable_IShellExtInit = extern struct {
        unknown: com.IUnknown.VTable(Self),
        shell_ext: com.IShellExtInit.VTable(Self),
    };
    const VTable_IContextMenu = extern struct {
        unknown: com.IUnknown.VTable(*VTable_IContextMenu),
        context_menu: com.IContextMenu.VTable(*VTable_IContextMenu),
    };

    vtable_ishellextinit: *const Self.VTable_IShellExtInit,
    vtable_icontextmenu: *const Self.VTable_IContextMenu,
    ref: u32,
    paths: ?[*][:0]const u16 = null,
    num_paths: usize = 0,

    pub const CLSID_String = "{1a2ffb08-53c2-4976-b10f-d2160b25373b}";
    const CLSID_Value = windows.GUID.parse(CLSID_String);
    pub const CLSID = &CLSID_Value;

    pub const IID_String = "{c44d7456-aed1-4a97-9c09-be5b1d434611}";
    const IID_Value = windows.GUID.parse(IID_String);
    pub const IID = &IID_Value;

    pub fn QueryInterface(
        self: *Self,
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        if (com.IsEqualIID(riid.?, Self.IID) or com.IsEqualIID(riid.?, com.IShellExtInit.IID)) {
            ppvObject.?.* = self;
        } else if (com.IsEqualIID(riid.?, com.IContextMenu.IID)) {
            ppvObject.?.* = @intToPtr(?*anyopaque, @ptrToInt(&self.vtable_icontextmenu));
        } else {
            ppvObject.?.* = null;
            return windows.E_NOINTERFACE;
        }

        _ = self.vtable_ishellextinit.unknown.AddRef(self);

        return windows.S_OK;
    }

    pub fn AddRef(self: *Self) callconv(windows.WINAPI) u32 {
        self.ref += 1;
        return self.ref;
    }

    pub fn Release(self: *Self) callconv(windows.WINAPI) u32 {
        self.ref -= 1;

        if (self.ref == 0) {
            self.destroy(main.global_allocator);
            _ = @atomicRmw(windows.LONG, &main.obj_count, .Sub, 1, .Monotonic);
            return 0;
        }

        return self.ref;
    }

    pub fn Initialize(
        self: *Self,
        pidlFolder: windows_extra.PCIDLIST_ABSOLUTE,
        pdtobj: ?*com.IDataObject,
        hkeyProgID: windows.HKEY,
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = pidlFolder;
        _ = hkeyProgID;

        if (pdtobj == null) {
            return windows.E_INVALIDARG;
        }

        const pDataObj = pdtobj.?;
        var etc = com.FORMATETC{
            .cfFormat = windows_extra.CF_HDROP,
            .ptd = null,
            .dwAspect = com.DVASPECT_CONTENT,
            .lindex = -1,
            .tymed = com.TYMED_HGLOBAL,
        };
        var stg = com.STGMEDIUM{
            .tymed = com.TYMED_HGLOBAL,
            .Anonymous = .{ .hGlobal = null },
            .pUnkForRelease = null,
        };

        const data_result = pDataObj.vtable.data_object.GetData(pDataObj, &etc, &stg);
        if (data_result != windows.S_OK) {
            return windows.E_INVALIDARG;
        }
        defer com.ReleaseStgMedium(&stg);

        const hdrop: ?windows_extra.HDROP = @ptrCast(?windows_extra.HDROP, windows_extra.GlobalLock(stg.Anonymous.hGlobal.?));
        if (hdrop == null) {
            return windows.E_INVALIDARG;
        }
        defer _ = windows_extra.GlobalUnlock(stg.Anonymous.hGlobal.?);

        const paths = getPathsAlloc(main.global_allocator, hdrop.?) catch |err| switch (err) {
            error.OutOfMemory => return windows.E_OUTOFMEMORY,
            error.DragQueryFileError => return windows.E_INVALIDARG,
        };
        self.paths = paths.ptr;
        self.num_paths = paths.len;

        return if (self.num_paths > 0) windows.S_OK else windows.E_INVALIDARG;
    }

    fn pathsSlice(self: *Self) [][:0]const u16 {
        if (self.paths) |paths_ptr| {
            return paths_ptr[0..self.num_paths];
        } else {
            return &[_][:0]const u16{};
        }
    }

    fn getPathsAlloc(allocator: std.mem.Allocator, hdrop: windows_extra.HDROP) ![][:0]const u16 {
        const num_paths = windows_extra.DragQueryFileW(hdrop, windows_extra.DragQueryFile_GetCount, null, 0);
        if (num_paths == 0) {
            return &[_][:0]const u16{};
        }
        var paths = try allocator.alloc([:0]const u16, num_paths);
        errdefer allocator.free(paths);
        // initialize all the elements to 0-sized slices so we can unconditionally free in an errdefer
        for (paths) |*path| {
            path.* = &[_:0]u16{};
        }
        errdefer {
            for (paths) |path| {
                allocator.free(path);
            }
        }

        var path_buf: [windows.PATH_MAX_WIDE]u16 = undefined;
        var index: windows.UINT = 0;
        while (index < num_paths) : (index += 1) {
            const len = windows_extra.DragQueryFileW(hdrop, index, &path_buf, path_buf.len);
            if (len == 0) {
                return error.DragQueryFileError;
            }

            var path = try allocator.allocSentinel(u16, len, 0);
            std.mem.copy(u16, path[0..len], path_buf[0..len]);

            paths[index] = path;
        }

        return paths;
    }

    pub fn QueryContextMenu(
        self: *Self,
        hmenu: ?windows.HMENU,
        indexMenu: windows.UINT,
        idCmdFirst: windows.UINT,
        idCmdLast: windows.UINT,
        uFlags: windows.UINT,
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;
        _ = idCmdLast;

        if (uFlags & com.CMF_DEFAULTONLY != 0) {
            return windows_extra.MAKE_HRESULT(windows_extra.SEVERITY_SUCCESS, windows_extra.FACILITY_NULL, 0);
        }

        const menu_string = std.unicode.utf8ToUtf16LeStringLiteral("Toggle watched");
        const ok = windows_extra.InsertMenuW(hmenu, indexMenu, windows_extra.MF_BYPOSITION, idCmdFirst, menu_string);
        if (ok == 0) {
            return windows_extra.HRESULT_FROM_WIN32(windows.kernel32.GetLastError());
        }

        // last param being 1 signifies that we added 1 menu item
        return windows_extra.MAKE_HRESULT(windows_extra.SEVERITY_SUCCESS, windows_extra.FACILITY_NULL, 1);
    }

    pub fn InvokeCommand(
        self: *Self,
        pici: ?*com.CMINVOKECOMMANDINFO,
    ) callconv(windows.WINAPI) windows.HRESULT {
        if (pici == null) {
            return windows.E_INVALIDARG;
        }
        const id = @intCast(windows.DWORD, @ptrToInt(pici.?.lpVerb));
        if (windows_extra.HIWORD(id) != 0) {
            return windows.E_INVALIDARG;
        }

        switch (id) {
            0 => {
                for (self.pathsSlice()) |path| {
                    main.db.setWatchedW(path, !main.db.isWatchedW(path)) catch {
                        return windows.E_FAIL;
                    };
                    // notify the shell of the change
                    windows_extra.SHChangeNotify(windows_extra.SHCNE_UPDATEITEM, windows_extra.SHCNF_PATHW, path.ptr, null);
                }
            },
            else => return windows.E_INVALIDARG,
        }

        return windows.S_OK;
    }

    pub fn GetCommandString(
        self: *Self,
        idCmd: windows_extra.UINT_PTR,
        uType: com.GCS,
        pReserved: ?*windows.UINT,
        pszName: ?[*]windows.CHAR,
        cchMax: windows.UINT,
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;
        _ = pReserved;

        // we only added one menu item, so the id must be 0
        if (idCmd != 0) {
            return windows.E_INVALIDARG;
        }

        const help_text = "Toggle the watched status of the selected file(s)";
        const help_text_w = std.unicode.utf8ToUtf16LeStringLiteral(help_text);
        switch (uType) {
            .HELPTEXTA => {
                std.mem.copy(u8, (pszName.?)[0..cchMax], help_text[0..help_text.len]);
                (pszName.?)[help_text.len] = 0;
            },
            .HELPTEXTW => {
                std.mem.copy(u8, (pszName.?)[0..cchMax], std.mem.sliceAsBytes(help_text_w[0 .. help_text_w.len + 1]));
            },
            else => return windows.E_INVALIDARG,
        }

        return windows.S_OK;
    }

    pub fn create(
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        var obj = main.global_allocator.create(WatchedContextMenu) catch {
            return windows.E_OUTOFMEMORY;
        };

        obj.* = .{
            .vtable_ishellextinit = &WatchedContextMenu.vtable_ishellextinit_impl,
            .vtable_icontextmenu = &WatchedContextMenu.vtable_icontextmenu_impl,
            .ref = 1,
        };

        const result = obj.vtable_ishellextinit.unknown.QueryInterface(obj, riid, ppvObject);
        // since we set everything up before this call, any error is a failure on our part
        std.debug.assert(result == windows.S_OK);
        // Release to decrement reference count after it was incremented in the
        // QueryInterface call
        _ = obj.vtable_ishellextinit.unknown.Release(obj);

        _ = @atomicRmw(windows.LONG, &main.obj_count, .Add, 1, .Monotonic);

        return result;
    }

    fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        const paths = self.pathsSlice();
        for (paths) |path| {
            allocator.free(path);
        }
        allocator.free(paths);
        allocator.destroy(self);
    }

    pub const vtable_ishellextinit_impl: Self.VTable_IShellExtInit = .{
        .unknown = .{
            .QueryInterface = QueryInterface,
            .AddRef = AddRef,
            .Release = Release,
        },
        .shell_ext = .{
            .Initialize = Initialize,
        },
    };

    pub fn QueryInterface_IContextMenu(
        field_ptr: **VTable_IContextMenu,
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        var self = @fieldParentPtr(Self, "vtable_icontextmenu", field_ptr);
        return QueryInterface(self, riid, ppvObject);
    }

    pub fn AddRef_IContextMenu(field_ptr: **VTable_IContextMenu) callconv(windows.WINAPI) u32 {
        var self = @fieldParentPtr(Self, "vtable_icontextmenu", field_ptr);
        return AddRef(self);
    }

    pub fn Release_IContextMenu(field_ptr: **VTable_IContextMenu) callconv(windows.WINAPI) u32 {
        var self = @fieldParentPtr(Self, "vtable_icontextmenu", field_ptr);
        return Release(self);
    }

    pub fn QueryContextMenu_IContextMenu(
        field_ptr: **VTable_IContextMenu,
        hmenu: ?windows.HMENU,
        indexMenu: windows.UINT,
        idCmdFirst: windows.UINT,
        idCmdLast: windows.UINT,
        uFlags: windows.UINT,
    ) callconv(windows.WINAPI) windows.HRESULT {
        var self = @fieldParentPtr(Self, "vtable_icontextmenu", field_ptr);
        return QueryContextMenu(self, hmenu, indexMenu, idCmdFirst, idCmdLast, uFlags);
    }

    pub fn InvokeCommand_IContextMenu(
        field_ptr: **VTable_IContextMenu,
        pici: ?*com.CMINVOKECOMMANDINFO,
    ) callconv(windows.WINAPI) windows.HRESULT {
        var self = @fieldParentPtr(Self, "vtable_icontextmenu", field_ptr);
        return InvokeCommand(self, pici);
    }

    pub fn GetCommandString_IContextMenu(
        field_ptr: **VTable_IContextMenu,
        idCmd: windows_extra.UINT_PTR,
        uType: com.GCS,
        pReserved: ?*windows.UINT,
        pszName: ?[*]windows.CHAR,
        cchMax: windows.UINT,
    ) callconv(windows.WINAPI) windows.HRESULT {
        var self = @fieldParentPtr(Self, "vtable_icontextmenu", field_ptr);
        return GetCommandString(self, idCmd, uType, pReserved, pszName, cchMax);
    }

    pub const vtable_icontextmenu_impl: Self.VTable_IContextMenu = .{
        .unknown = .{
            .QueryInterface = QueryInterface_IContextMenu,
            .AddRef = AddRef_IContextMenu,
            .Release = Release_IContextMenu,
        },
        .context_menu = .{
            .QueryContextMenu = QueryContextMenu_IContextMenu,
            .InvokeCommand = InvokeCommand_IContextMenu,
            .GetCommandString = GetCommandString_IContextMenu,
        },
    };
};
