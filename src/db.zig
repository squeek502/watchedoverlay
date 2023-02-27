const std = @import("std");
const sqlite = @import("sqlite");
const Cache = @import("cache.zig").Cache;
const Allocator = std.mem.Allocator;

pub const Db = struct {
    db: sqlite.Db,
    cache: Cache,

    pub fn init(allocator: Allocator, path: [:0]const u8) !Db {
        var self = Db{
            .db = try sqlite.Db.init(.{
                .mode = sqlite.Db.Mode{ .File = path },
                .open_flags = .{
                    .write = true,
                    .create = true,
                },
            }),
            .cache = Cache.init(allocator),
        };
        errdefer self.deinit();

        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS watched (
            \\    path TEXT PRIMARY KEY,
            \\    pathw BLOB UNIQUE,
            \\    watched INTEGER DEFAULT 1
            \\);
        , .{}, .{});

        try self.initCache();

        return self;
    }

    pub fn deinit(self: *Db) void {
        self.db.deinit();
        self.cache.deinit();
    }

    pub fn setWatchedW(self: *Db, pathw: []const u16, watched: bool) !void {
        const bytes = std.mem.sliceAsBytes(pathw);
        const blob = sqlite.Blob{ .data = bytes };

        while (true) {
            if (watched) {
                var stmt = self.db.prepare(
                    "INSERT OR REPLACE INTO watched(path, pathw, watched) VALUES(?, ?, ?)",
                ) catch |err| switch (err) {
                    error.SQLiteBusy, error.SQLiteLocked => continue, // retry
                    else => |e| return e,
                };
                defer stmt.deinit();

                var path_utf8_buf: [std.os.windows.PATH_MAX_WIDE]u8 = undefined;
                const utf8_len = try std.unicode.utf16leToUtf8(&path_utf8_buf, pathw);
                const path_utf8 = path_utf8_buf[0..utf8_len];

                stmt.exec(.{}, .{
                    .path = path_utf8,
                    .pathw = blob,
                    .watched = watched,
                }) catch |err| switch (err) {
                    error.SQLiteBusy, error.SQLiteLocked => continue, // retry
                    else => |e| return e,
                };

                try self.cache.update(pathw);
                break;
            } else {
                self.db.exec("DELETE FROM watched WHERE pathw=?", .{}, .{
                    .pathw = blob,
                }) catch |err| switch (err) {
                    error.SQLiteBusy, error.SQLiteLocked => continue, // retry
                    else => |e| return e,
                };
                break;
            }
        }
    }

    pub fn isWatchedW(self: *Db, pathw: []const u16) bool {
        if (!self.cache.contains(pathw)) return false;

        const bytes = std.mem.sliceAsBytes(pathw);
        const blob = sqlite.Blob{ .data = bytes };
        const watched = self.db.one(u8, "SELECT watched FROM watched WHERE pathw=?", .{}, .{
            .pathw = blob,
        }) catch {
            return false;
        };
        return watched != null and watched.? != 0;
    }

    pub fn setWatched(self: *Db, path: []const u8, watched: bool) !void {
        while (true) {
            if (watched) {
                var stmt = self.db.prepare(
                    "INSERT OR REPLACE INTO watched(path, pathw, watched) VALUES(?, ?, ?)",
                ) catch |err| switch (err) {
                    error.SQLiteBusy, error.SQLiteLocked => continue, // retry
                    else => |e| return e,
                };
                defer stmt.deinit();

                var pathw_buf: [std.os.windows.PATH_MAX_WIDE]u16 = undefined;
                const pathw_len = try std.unicode.utf8ToUtf16Le(&pathw_buf, path);
                const pathw = pathw_buf[0..pathw_len];
                const bytes = std.mem.sliceAsBytes(pathw);
                const blob = sqlite.Blob{ .data = bytes };

                stmt.exec(.{}, .{
                    .path = path,
                    .pathw = blob,
                    .watched = watched,
                }) catch |err| switch (err) {
                    error.SQLiteBusy, error.SQLiteLocked => continue, // retry
                    else => |e| return e,
                };

                try self.cache.update(pathw);
                break;
            } else {
                self.db.exec("DELETE FROM watched WHERE path=?", .{}, .{
                    .path = path,
                }) catch |err| switch (err) {
                    error.SQLiteBusy, error.SQLiteLocked => continue, // retry
                    else => |e| return e,
                };
                break;
            }
        }
    }

    pub fn isWatched(self: *Db, path: []const u8) bool {
        // It's not worth checking self.cache here since it would need a conversion
        // to UTF-16. Or, more accurately, I'm too lazy to make that change and the W
        // version is the only verison that's actually called in the critical path
        // (only vlc-watcher calls this function).

        const watched = self.db.one(u8, "SELECT watched FROM watched WHERE path=?", .{}, .{ .path = path }) catch {
            return false;
        };
        return watched != null and watched.? != 0;
    }

    fn initCache(self: *Db) !void {
        var stmt = try self.db.prepare("SELECT pathw FROM watched");
        defer stmt.deinit();

        var iter = try stmt.iterator([]const u8, .{});
        while (try iter.nextAlloc(self.cache.allocator, .{})) |path_bytes| {
            defer self.cache.allocator.free(path_bytes);
            const path_w = std.mem.bytesAsSlice(u16, @alignCast(@alignOf(u16), path_bytes));
            try self.cache.update(path_w);
        }
    }
};

test "init" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try std.fs.path.joinZ(std.testing.allocator, &.{ "zig-cache", "tmp", &tmp.sub_path, "test.sqlite" });
    defer std.testing.allocator.free(db_path);

    var db = try Db.init(std.testing.allocator, db_path);
    defer db.deinit();

    const path = "C:\\Some\\Path\\file.mp4";
    const pathw = std.unicode.utf8ToUtf16LeStringLiteral(path);
    try std.testing.expect(!db.isWatched(path));
    try std.testing.expect(!db.isWatchedW(pathw));

    try db.setWatched(path, true);
    try std.testing.expect(db.isWatched(path));
    try std.testing.expect(db.isWatchedW(pathw));

    try db.setWatched(path, false);
    try std.testing.expect(!db.isWatched(path));
    try std.testing.expect(!db.isWatchedW(pathw));

    try db.setWatchedW(pathw, true);
    try std.testing.expect(db.isWatched(path));
    try std.testing.expect(db.isWatchedW(pathw));

    try db.setWatchedW(pathw, false);
    try std.testing.expect(!db.isWatched(path));
    try std.testing.expect(!db.isWatchedW(pathw));
}

test "cache" {
    const utf16Literal = std.unicode.utf8ToUtf16LeStringLiteral;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try std.fs.path.joinZ(std.testing.allocator, &.{ "zig-cache", "tmp", &tmp.sub_path, "test.sqlite" });
    defer std.testing.allocator.free(db_path);

    var db = try Db.init(std.testing.allocator, db_path);
    defer db.deinit();

    try db.setWatched("C:\\Some\\Path\\file.mp4", true);
    try db.setWatched("C:\\Some\\Other\\file.mp4", true);
    try db.setWatched("D:\\Yet\\Another\\file.mp4", true);

    try db.initCache();

    try std.testing.expect(db.cache.contains(utf16Literal("C:\\Some\\Path\\file.mp4")));
    try std.testing.expect(db.cache.contains(utf16Literal("C:\\Some\\Other\\file.mp4")));
    try std.testing.expect(db.cache.contains(utf16Literal("D:\\Yet\\Another\\file.mp4")));
    try std.testing.expect(!db.cache.contains(utf16Literal("C:\\Some")));
    try std.testing.expect(!db.cache.contains(utf16Literal("C:\\SomePathThatIsClose.mp4")));
    try std.testing.expect(!db.cache.contains(utf16Literal("E:\\Yet\\Another\\file.mp4")));

    try db.setWatched("C:\\Another\\Path\\file.mp4", true);

    try std.testing.expect(db.cache.contains(utf16Literal("C:\\Some")));
    try std.testing.expect(db.cache.contains(utf16Literal("C:\\SomePathThatIsClose.mp4")));
}
