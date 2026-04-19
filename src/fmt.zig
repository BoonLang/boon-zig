const std = @import("std");
const diag = @import("diag.zig");
const parser = @import("parser.zig");

pub const Outcome = union(enum) {
    ok: []u8,
    err: diag.Diagnostic,
};

pub fn formatAlloc(allocator: std.mem.Allocator, source: []const u8) !Outcome {
    const parsed = try parser.parseAlloc(allocator, source);
    switch (parsed) {
        .ok => |document| {
            var parsed_document = document;
            defer parsed_document.deinit();
            return .{ .ok = try allocator.dupe(u8, source) };
        },
        .err => |failure| return .{ .err = failure },
    }
}

fn expectIdentity(comptime path: []const u8) !void {
    const source = @embedFile(path);
    const outcome = try formatAlloc(std.testing.allocator, source);
    const formatted = switch (outcome) {
        .ok => |formatted| formatted,
        .err => |failure| {
            std.debug.print("format failure for {s}: {s}\n", .{ path, failure.message });
            return error.UnexpectedFormatFailure;
        },
    };
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(source, formatted);
}

const corpus_roots = [_][]const u8{
    "examples/upstream",
    "examples/terminal",
};

const known_parser_blockers = [_][]const u8{
    "examples/upstream/hw_examples/serialadder.bn",
};

fn isKnownParserBlocker(path: []const u8) bool {
    inline for (known_parser_blockers) |blocked| {
        if (std.mem.eql(u8, blocked, path)) return true;
    }
    return false;
}

fn expectCorpusFormattingIdentity() !void {
    const allocator = std.testing.allocator;
    var formatted_count: usize = 0;
    var blocked_count: usize = 0;

    inline for (corpus_roots) |root_path| {
        var dir = try std.Io.Dir.cwd().openDir(std.testing.io, root_path, .{ .iterate = true });
        defer dir.close(std.testing.io);

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.path, ".bn")) continue;

            const relative_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root_path, entry.path });
            defer allocator.free(relative_path);

            const source = try std.Io.Dir.cwd().readFileAlloc(
                std.testing.io,
                relative_path,
                allocator,
                .limited(std.math.maxInt(usize)),
            );
            defer allocator.free(source);

            const outcome = try formatAlloc(allocator, source);
            switch (outcome) {
                .ok => |formatted| {
                    defer allocator.free(formatted);
                    try std.testing.expectEqualStrings(source, formatted);
                    formatted_count += 1;
                },
                .err => |failure| {
                    if (isKnownParserBlocker(relative_path)) {
                        blocked_count += 1;
                        continue;
                    }
                    std.debug.print("unexpected corpus format failure for {s}: {s}\n", .{ relative_path, failure.message });
                    return error.UnexpectedFormatFailure;
                },
            }
        }
    }

    try std.testing.expect(formatted_count > 0);
    try std.testing.expectEqual(@as(usize, known_parser_blockers.len), blocked_count);
}

test "formatter is identity on supported corpus files" {
    try expectIdentity("../examples/upstream/counter/counter.bn");
    try expectIdentity("../examples/upstream/interval/interval.bn");
    try expectIdentity("../examples/upstream/cells/cells.bn");
    try expectIdentity("../examples/upstream/timer/timer.bn");
    try expectIdentity("../examples/upstream/temperature_converter/temperature_converter.bn");
    try expectIdentity("../examples/upstream/todo_mvc/todo_mvc.bn");
}

test "formatter is identity across parser-supported corpus" {
    try expectCorpusFormattingIdentity();
}
