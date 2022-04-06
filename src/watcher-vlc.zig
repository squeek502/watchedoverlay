const std = @import("std");
const Db = @import("db.zig").Db;
const zuri = @import("zuri");
const windows_extra = @import("windows_extra.zig");

var cached_last_modified: ?i128 = null;
var cached_path: ?[]const u8 = null;
const sqlite_db_name = "watched.sqlite";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == false);
    const allocator = gpa.allocator();

    defer if (cached_path != null) allocator.free(cached_path.?);

    var ini_file_path = ini_file_path: {
        const appdata_path = try std.process.getEnvVarOwned(allocator, "APPDATA");
        defer allocator.free(appdata_path);

        break :ini_file_path try std.fs.path.join(allocator, &.{ appdata_path, "vlc\\vlc-qt-interface.ini" });
    };
    defer allocator.free(ini_file_path);

    var db = db: {
        var exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(exe_dir);

        const sqlite_file_path = try std.fs.path.joinZ(allocator, &.{ exe_dir, sqlite_db_name });
        defer allocator.free(sqlite_file_path);

        break :db try Db.init(sqlite_file_path);
    };
    defer db.deinit();

    while (true) {
        {
            var ini_file = try std.fs.cwd().openFile(ini_file_path, .{});
            defer ini_file.close();
            try updateFromIni(allocator, ini_file, &db);
        }

        std.time.sleep(1 * std.time.ns_per_s);
    }
}

fn updateFromIni(_allocator: std.mem.Allocator, file: std.fs.File, db: *Db) !void {
    var stat = try file.stat();
    // if modified time hasn't changed, then there's nothing to update
    if (cached_last_modified != null and stat.mtime == cached_last_modified.?) {
        std.debug.print("unchanged\n", .{});
        return;
    }
    cached_last_modified = stat.mtime;

    // use an arena to simplify cleanup since all the allocations can be thrown away at
    // the end of this function
    var arena_allocator = std.heap.ArenaAllocator.init(_allocator);
    defer arena_allocator.deinit();
    var arena = arena_allocator.allocator();

    var contents = try file.readToEndAlloc(arena, std.math.maxInt(usize));

    var recents_header_pos = std.mem.indexOf(u8, contents, "[RecentsMRL]");
    if (recents_header_pos == null) {
        return error.UnexpectedIniContents;
    }
    var end_of_recents_section = std.mem.indexOfPos(u8, contents, recents_header_pos.?, "\n[") orelse contents.len;
    var recents_slice = contents[(recents_header_pos.?)..end_of_recents_section];

    var list = list: {
        var line_iterator = std.mem.tokenize(u8, recents_slice, "\r\n");
        while (line_iterator.next()) |line| {
            const prefix = "list=";
            if (std.mem.startsWith(u8, line, prefix)) {
                break :list line[prefix.len..];
            }
        }
        return error.UnexpectedIniContents;
    };

    var paths = try parseList(arena, list);
    for (paths) |path| {
        // for now, we just add the first item and only if its different than
        // the last path we saw in order to allow the context menu toggling to have
        // an affect on things that are in the recent items but we want to mark as unwatched
        if (cached_path == null or !std.mem.eql(u8, path, cached_path.?)) {
            if (!db.isWatched(path)) {
                std.debug.print("Marking as watched: {s}\n", .{path});
                var path_w = try std.unicode.utf8ToUtf16LeWithNull(arena, path);
                try db.setWatchedW(path_w, true);

                // need to notify the shell that the file was upated
                windows_extra.SHChangeNotify(windows_extra.SHCNE_UPDATEITEM, windows_extra.SHCNF_PATHW, path_w.ptr, null);
            }
        }
        if (cached_path == null or !std.mem.eql(u8, path, cached_path.?)) {
            if (cached_path != null) {
                _allocator.free(cached_path.?);
            }
            cached_path = try _allocator.dupe(u8, path);
        }
        break;
    }
}

const ParseState = enum {
    initial,
    double_quoted,
    unquoted,
};

fn parseList(arena: std.mem.Allocator, list_str: []const u8) ![][]const u8 {
    var index: usize = 0;
    var state: ParseState = .initial;
    var start_index: usize = 0;
    var paths = std.ArrayList([]const u8).init(arena);

    while (index < list_str.len) : (index += 1) {
        const c = list_str[index];
        switch (state) {
            .initial => switch (c) {
                '"' => {
                    state = .double_quoted;
                    start_index = index + 1;
                },
                ',', ' ' => {},
                else => {
                    state = .unquoted;
                    start_index = index;
                },
            },
            .double_quoted => switch (c) {
                '"' => {
                    const uri = list_str[start_index..index];
                    try paths.append(uri);
                    state = .initial;
                },
                else => {},
            },
            .unquoted => switch (c) {
                ',' => {
                    const uri = list_str[start_index..index];
                    try paths.append(uri);
                    state = .initial;
                },
                else => {},
            },
        }
    }

    for (paths.items) |uri, i| {
        const parsed = try zuri.Uri.parse(uri, false);
        const trimmed_path = std.mem.trimLeft(u8, parsed.path, "/");
        var decoded_path = try zuri.Uri.decode(arena, trimmed_path);
        var path = decoded_path orelse trimmed_path;
        // just dupe the memory here to avoid const madness
        var path_dupe = try arena.dupe(u8, path);
        var normalized_path_len = try std.os.windows.normalizePath(u8, path_dupe);
        paths.items[i] = path_dupe[0..normalized_path_len];
    }

    return paths.toOwnedSlice();
}
