const std = @import("std");
const document_snapshot = @import("document_snapshot.zig");
const host = @import("boon_runtime_host.zig");

pub const AdaptedDocument = struct {
    text: []u8,

    pub fn deinit(self: *AdaptedDocument, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        self.* = undefined;
    }
};

pub fn adaptDocument(allocator: std.mem.Allocator, snapshot: host.bridge.DocumentSnapshot) !AdaptedDocument {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try document_snapshot.appendPlainText(&out.writer, snapshot);
    return .{ .text = try out.toOwnedSlice() };
}
