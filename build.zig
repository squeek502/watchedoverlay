const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const sqlite = b.addStaticLibrary("sqlite", null);
    sqlite.addCSourceFile("lib/zig-sqlite/c/sqlite3.c", &[_][]const u8{"-std=c99"});
    sqlite.setBuildMode(mode);
    sqlite.setTarget(target);
    sqlite.addIncludeDir("lib/zig-sqlite/c");
    sqlite.linkLibC();

    const watched = b.addSharedLibrary("watched", "src/dllmain.zig", .{ .unversioned = {} });
    watched.setBuildMode(mode);
    watched.setTarget(target);
    watched.linkLibC();
    watched.linkLibrary(sqlite);
    watched.addIncludeDir("lib/zig-sqlite/c");
    watched.addObjectFile("res/resource.res.obj");
    watched.addPackage(.{ .name = "sqlite", .path = .{ .path = "lib/zig-sqlite/sqlite.zig" } });
    watched.install();

    const watcher_vlc = b.addExecutable("watcher-vlc", "src/watcher-vlc.zig");
    watcher_vlc.setBuildMode(mode);
    watcher_vlc.setTarget(target);
    watcher_vlc.linkLibC();
    watcher_vlc.linkLibrary(sqlite);
    watcher_vlc.addIncludeDir("lib/zig-sqlite/c");
    watcher_vlc.addPackage(.{ .name = "sqlite", .path = .{ .path = "lib/zig-sqlite/sqlite.zig" } });
    watcher_vlc.addPackage(.{ .name = "zuri", .path = .{ .path = "lib/zuri/src/zuri.zig" } });
    watcher_vlc.install();

    const main_tests = b.addTest("src/dllmain.zig");
    main_tests.linkLibC();
    main_tests.linkLibrary(sqlite);
    main_tests.addIncludeDir("lib/zig-sqlite/c");
    main_tests.addPackage(.{ .name = "sqlite", .path = .{ .path = "lib/zig-sqlite/sqlite.zig" } });
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    // dist
    const dist_watched = b.addInstallFileWithDir(
        watched.getOutputSource(),
        std.build.InstallDir{ .custom = "dist" },
        watched.out_filename,
    );
    dist_watched.step.dependOn(b.getInstallStep());

    const dist_watcher = b.addInstallFileWithDir(
        watcher_vlc.getOutputSource(),
        std.build.InstallDir{ .custom = "dist" },
        watcher_vlc.out_filename,
    );
    dist_watcher.step.dependOn(b.getInstallStep());

    const dist_scripts = b.addInstallDirectory(.{
        .source_dir = "dist",
        .install_dir = std.build.InstallDir{ .custom = "dist" },
        .install_subdir = "",
    });
    dist_scripts.step.dependOn(b.getInstallStep());

    const dist = b.step("dist", "Package for distribution");
    dist.dependOn(&dist_watcher.step);
    dist.dependOn(&dist_watched.step);
    dist.dependOn(&dist_scripts.step);
}
