const std = @import("std");
const com = @import("com.zig");
const windows = std.os.windows;
const windows_extra = @import("windows_extra.zig");
const main = @import("main.zig");

pub const WatchedClassFactory = extern struct {
    const Self = @This();
    const VTable = extern struct {
        unknown: com.IUnknown.VTable(Self),
        class_factory: com.IClassFactory.VTable(Self),
    };
    const CreateFn = fn (
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT;

    vtable: *const Self.VTable,
    create_fn: CreateFn,
    ref: u32,

    pub fn QueryInterface(
        self: *Self,
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) callconv(windows.WINAPI) windows.HRESULT {
        if (!com.IsEqualIID(riid.?, com.IClassFactory.IID)) {
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
            _ = @atomicRmw(windows.LONG, &main.obj_count, .Sub, 1, .Monotonic);
            return 0;
        }

        return self.ref;
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

        return self.create_fn(riid, ppvObject);
    }

    pub fn LockServer(
        self: *Self,
        fLock: windows.BOOL,
    ) callconv(windows.WINAPI) windows.HRESULT {
        _ = self;

        if (fLock != 0) {
            _ = @atomicRmw(windows.LONG, &main.lock_count, .Add, 1, .Monotonic);
        } else {
            _ = @atomicRmw(windows.LONG, &main.lock_count, .Sub, 1, .Monotonic);
        }
        return windows.S_OK;
    }

    pub fn create(
        allocator: std.mem.Allocator,
        create_fn: CreateFn,
        riid: ?*const windows.GUID,
        ppvObject: ?*?*anyopaque,
    ) std.mem.Allocator.Error!void {
        var obj = try allocator.create(WatchedClassFactory);

        obj.vtable = &WatchedClassFactory.vtable_impl;
        obj.create_fn = create_fn;
        obj.ref = 1;

        const result = obj.vtable.unknown.QueryInterface(obj, riid, ppvObject);
        // since we set everything up before this call, any error is a failure on our part
        std.debug.assert(result == windows.S_OK);
        // Release to decrement reference count after it was incremented in the
        // QueryInterface call
        _ = obj.vtable.unknown.Release(obj);

        _ = @atomicRmw(windows.LONG, &main.obj_count, .Add, 1, .Monotonic);
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
};
