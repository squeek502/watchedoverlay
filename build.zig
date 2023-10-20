const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const single_threaded = b.option(bool, "single-threaded", "build in single threaded mode") orelse false;

    const sqlite = b.addStaticLibrary(.{
        .name = "sqlite",
        .target = target,
        .optimize = mode,
    });
    sqlite.addCSourceFile(.{ .file = .{ .path = "lib/zig-sqlite/c/sqlite3.c" }, .flags = &.{"-std=c99"} });
    sqlite.addIncludePath(.{ .path = "lib/zig-sqlite/c" });
    sqlite.linkLibC();

    const zig_sqlite = b.createModule(.{
        .source_file = .{ .path = "lib/zig-sqlite/sqlite.zig" },
    });

    const watched = b.addSharedLibrary(.{
        .name = "watched",
        .root_source_file = .{ .path = "src/dllmain.zig" },
        .target = target,
        .optimize = mode,
        .single_threaded = single_threaded,
    });
    watched.linkLibC();
    watched.linkLibrary(sqlite);
    watched.addIncludePath(.{ .path = "lib/zig-sqlite/c" });
    watched.addWin32ResourceFile(.{ .file = .{ .path = "res/resource.rc" } });
    watched.addModule("sqlite", zig_sqlite);
    b.installArtifact(watched);

    const zuri = b.createModule(.{
        .source_file = .{ .path = "lib/zuri/src/zuri.zig" },
    });

    const watcher_vlc = b.addExecutable(.{
        .name = "watcher-vlc",
        .root_source_file = .{ .path = "src/watcher-vlc.zig" },
        .target = target,
        .optimize = mode,
        .single_threaded = single_threaded,
    });
    watcher_vlc.linkLibC();
    watcher_vlc.linkLibrary(sqlite);
    watcher_vlc.addIncludePath(.{ .path = "lib/zig-sqlite/c" });
    watcher_vlc.addModule("sqlite", zig_sqlite);
    watcher_vlc.addModule("zuri", zuri);
    b.installArtifact(watcher_vlc);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/dllmain.zig" },
        .optimize = mode,
        .target = target,
    });
    main_tests.linkLibC();
    main_tests.linkLibrary(sqlite);
    main_tests.addIncludePath(.{ .path = "lib/zig-sqlite/c" });
    main_tests.addModule("sqlite", zig_sqlite);

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
        .source_dir = .{ .path = "dist" },
        .install_dir = std.build.InstallDir{ .custom = "dist" },
        .install_subdir = "",
    });
    dist_scripts.step.dependOn(b.getInstallStep());

    const dist = b.step("dist", "Package for distribution");
    dist.dependOn(&dist_watcher.step);
    dist.dependOn(&dist_watched.step);
    dist.dependOn(&dist_scripts.step);
}
