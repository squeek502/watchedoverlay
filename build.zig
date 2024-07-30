const std = @import("std");

pub fn build(b: *std.Build) void {
    const mode = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const single_threaded = b.option(bool, "single-threaded", "build in single threaded mode") orelse false;

    const zig_sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = mode,
    });
    const sqlite = zig_sqlite.artifact("sqlite");

    const watched = b.addSharedLibrary(.{
        .name = "watched",
        .root_source_file = b.path("src/dllmain.zig"),
        .target = target,
        .optimize = mode,
        .single_threaded = single_threaded,
    });
    watched.linkLibC();
    watched.linkLibrary(sqlite);
    watched.addIncludePath(zig_sqlite.path("c"));
    watched.addWin32ResourceFile(.{ .file = b.path("res/resource.rc") });
    watched.root_module.addImport("sqlite", zig_sqlite.module("sqlite"));
    b.installArtifact(watched);

    const zuri = b.dependency("zuri", .{
        .target = target,
        .optimize = mode,
    });

    const watcher_vlc = b.addExecutable(.{
        .name = "watcher-vlc",
        .root_source_file = b.path("src/watcher-vlc.zig"),
        .target = target,
        .optimize = mode,
        .single_threaded = single_threaded,
    });
    watcher_vlc.linkLibC();
    watcher_vlc.linkLibrary(sqlite);
    watcher_vlc.addIncludePath(zig_sqlite.path("c"));
    watcher_vlc.root_module.addImport("sqlite", zig_sqlite.module("sqlite"));
    watcher_vlc.root_module.addImport("zuri", zuri.module("zuri"));
    b.installArtifact(watcher_vlc);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/dllmain.zig"),
        .optimize = mode,
        .target = target,
    });
    main_tests.linkLibC();
    main_tests.linkLibrary(sqlite);
    main_tests.addIncludePath(zig_sqlite.path("c"));
    main_tests.root_module.addImport("sqlite", zig_sqlite.module("sqlite"));
    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    // dist
    const dist_watched = b.addInstallFileWithDir(
        watched.getEmittedBin(),
        .{ .custom = "dist" },
        watched.out_filename,
    );
    dist_watched.step.dependOn(b.getInstallStep());

    const dist_watcher = b.addInstallFileWithDir(
        watcher_vlc.getEmittedBin(),
        .{ .custom = "dist" },
        watcher_vlc.out_filename,
    );
    dist_watcher.step.dependOn(b.getInstallStep());

    const dist_scripts = b.addInstallDirectory(.{
        .source_dir = b.path("dist"),
        .install_dir = .{ .custom = "dist" },
        .install_subdir = "",
    });
    dist_scripts.step.dependOn(b.getInstallStep());

    const dist = b.step("dist", "Package for distribution");
    dist.dependOn(&dist_watcher.step);
    dist.dependOn(&dist_watched.step);
    dist.dependOn(&dist_scripts.step);
}
