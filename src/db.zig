const std = @import("std");
const sqlite = @import("sqlite");

pub const Db = struct {
    db: sqlite.Db,

    pub fn init(path: [:0]const u8) !Db {
        var self = Db{
            .db = try sqlite.Db.init(.{
                .mode = sqlite.Db.Mode{ .File = path },
                .open_flags = .{
                    .write = true,
                    .create = true,
                },
            }),
        };
        errdefer self.deinit();

        try self.db.exec(
            \\CREATE TABLE IF NOT EXISTS watched (
            \\    path TEXT PRIMARY KEY,
            \\    pathw BLOB UNIQUE,
            \\    watched INTEGER DEFAULT 1
            \\);
        , .{}, .{});
        return self;
    }

    pub fn deinit(self: *Db) void {
        self.db.deinit();
    }

    pub fn setWatchedW(self: *Db, pathw: []const u16, watched: bool) !void {
        const bytes = std.mem.sliceAsBytes(pathw);
        const blob = sqlite.Blob{ .data = bytes };

        if (watched) {
            var stmt = try self.db.prepare("INSERT OR REPLACE INTO watched(path, pathw, watched) VALUES(?, ?, ?)");
            defer stmt.deinit();

            var path_utf8_buf: [std.os.windows.PATH_MAX_WIDE]u8 = undefined;
            const utf8_len = try std.unicode.utf16leToUtf8(&path_utf8_buf, pathw);
            const path_utf8 = path_utf8_buf[0..utf8_len];

            try stmt.exec(.{}, .{
                .path = path_utf8,
                .pathw = blob,
                .watched = watched,
            });
        } else {
            try self.db.exec("DELETE FROM watched WHERE pathw=?", .{}, .{
                .pathw = blob,
            });
        }
    }

    pub fn isWatchedW(self: *Db, pathw: []const u16) bool {
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
        if (watched) {
            var stmt = try self.db.prepare("INSERT OR REPLACE INTO watched(path, pathw, watched) VALUES(?, ?, ?)");
            defer stmt.deinit();

            var pathw_buf: [std.os.windows.PATH_MAX_WIDE]u16 = undefined;
            const pathw_len = try std.unicode.utf8ToUtf16Le(&pathw_buf, path);
            const pathw = pathw_buf[0..pathw_len];
            const bytes = std.mem.sliceAsBytes(pathw);
            const blob = sqlite.Blob{ .data = bytes };

            try stmt.exec(.{}, .{
                .path = path,
                .pathw = blob,
                .watched = watched,
            });
        } else {
            try self.db.exec("DELETE FROM watched WHERE path=?", .{}, .{
                .path = path,
            });
        }
    }

    pub fn isWatched(self: *Db, path: []const u8) bool {
        const watched = self.db.one(u8, "SELECT watched FROM watched WHERE path=?", .{}, .{ .path = path }) catch {
            return false;
        };
        return watched != null and watched.? != 0;
    }
};

test "init" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const db_path = try std.fs.path.joinZ(std.testing.allocator, &.{ "zig-cache", "tmp", &tmp.sub_path, "test.sqlite" });
    defer std.testing.allocator.free(db_path);

    var db = try Db.init(db_path);
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
