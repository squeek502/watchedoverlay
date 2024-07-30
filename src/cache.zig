const std = @import("std");
const Allocator = std.mem.Allocator;
const utf16Literal = std.unicode.utf8ToUtf16LeStringLiteral;
const RtlUpcaseUnicodeChar = std.os.windows.ntdll.RtlUpcaseUnicodeChar;

/// An in-memory quick lookup to be able to exclude paths
/// that we know can't have anything that we should draw an icon
/// for. Only stores a single longest common prefix for each
/// first character of the paths in the database, which typically
/// corresponds to the drive letter (so essentially the common
/// prefix for each drive letter).
pub const Cache = struct {
    /// Note: First char values should be run through RtlUpcaseUnicodeChar
    ///       and LCP should be compared using RtlEqualUnicodeString
    lcp_by_first_char: std.AutoHashMap(u16, []u16),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Cache {
        return .{
            .lcp_by_first_char = std.AutoHashMap(u16, []u16).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Cache) void {
        var it = self.lcp_by_first_char.valueIterator();
        while (it.next()) |v| {
            self.allocator.free(v.*);
        }
        self.lcp_by_first_char.deinit();
    }

    pub fn update(self: *Cache, path_w: []const u16) !void {
        if (path_w.len == 0) return;
        const first_char = RtlUpcaseUnicodeChar(path_w[0]);
        const result = try self.lcp_by_first_char.getOrPut(first_char);
        if (!result.found_existing) {
            result.value_ptr.* = try self.allocator.dupe(u16, path_w);
        } else {
            const lcp_len = longestCommonPrefix(result.value_ptr.*, path_w);
            result.value_ptr.* = try self.allocator.realloc(result.value_ptr.*, lcp_len);
        }
    }

    pub fn contains(self: *const Cache, path_w: []const u16) bool {
        if (path_w.len == 0) return false;
        const first_char = RtlUpcaseUnicodeChar(path_w[0]);
        if (self.lcp_by_first_char.get(first_char)) |prefix| {
            if (path_w.len < prefix.len) return false;
            const relevant_part = path_w[0..prefix.len];
            return std.os.windows.eqlIgnoreCaseWTF16(prefix, relevant_part);
        }
        return false;
    }

    fn longestCommonPrefix(a: []const u16, b: []const u16) usize {
        const min_len = @min(a.len, b.len);
        var i: usize = 0;
        while (i < min_len) : (i += 1) {
            if (RtlUpcaseUnicodeChar(a[i]) != RtlUpcaseUnicodeChar(b[i])) break;
        }
        return i;
    }
};

test {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.update(utf16Literal("C:\\Some\\Path"));
    try cache.update(utf16Literal("C:\\Some\\Path\\With\\More"));
    try cache.update(utf16Literal("C:\\Some\\path\\With"));
    try cache.update(utf16Literal("D:\\Another\\Drive"));

    try std.testing.expectEqualSlices(
        u16,
        utf16Literal("C:\\Some\\Path"),
        cache.lcp_by_first_char.get('C').?,
    );
    try std.testing.expectEqualSlices(
        u16,
        utf16Literal("D:\\Another\\Drive"),
        cache.lcp_by_first_char.get('D').?,
    );

    try cache.update(utf16Literal("D:\\Somwhere\\Else"));

    try std.testing.expectEqualSlices(
        u16,
        utf16Literal("D:\\"),
        cache.lcp_by_first_char.get('D').?,
    );

    try std.testing.expect(!cache.contains(utf16Literal("C:\\Somewhere\\Else")));
    try std.testing.expect(cache.contains(utf16Literal("C:\\SOME\\PATH\\CASE\\INSENSITIVE")));
}
