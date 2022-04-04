const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const sqlite = b.addStaticLibrary("sqlite", null);
    sqlite.addCSourceFile("lib/zig-sqlite/c/sqlite3.c", &[_][]const u8{"-std=c99"});
    sqlite.addIncludeDir("lib/zig-sqlite/c");
    sqlite.linkLibC();

    const lib = b.addSharedLibrary("IWatchedShellOverlayIdentifer", "src/main.zig", .{ .unversioned = {} });
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.linkLibC();
    lib.linkLibrary(sqlite);
    lib.addIncludeDir("lib/zig-sqlite/c");
    lib.addObjectFile("res/resource.res.obj");
    lib.addPackage(.{ .name = "sqlite", .path = .{ .path = "lib/zig-sqlite/sqlite.zig" } });
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.linkLibC();
    main_tests.linkLibrary(sqlite);
    main_tests.addIncludeDir("lib/zig-sqlite/c");
    main_tests.addPackage(.{ .name = "sqlite", .path = .{ .path = "lib/zig-sqlite/sqlite.zig" } });
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
