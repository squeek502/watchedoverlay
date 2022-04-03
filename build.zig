const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = b.addSharedLibrary("IWatchedShellOverlayIdentifer", "src/main.zig", .{ .unversioned = {} });
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.linkSystemLibrary("kernel32");
    lib.single_threaded = true;
    lib.install();
}
