const std = @import("std");
const ast = @import("ast.zig");

pub const Diagnostic = struct {
    message: []const u8,
    span: ast.Span,

    pub fn render(self: Diagnostic, source: []const u8, writer: *std.Io.Writer) !void {
        const location = locate(source, self.span.start);
        try writer.print(
            "error: {s} at {d}:{d}\n",
            .{ self.message, location.line, location.column },
        );

        const line_text = source[location.line_start..location.line_end];
        try writer.print("{s}\n", .{line_text});

        var column_padding: usize = 1;
        var i = location.line_start;
        while (i < self.span.start and i < source.len) : (i += 1) {
            column_padding += if (source[i] == '\t') 4 else 1;
        }

        var pad: usize = 0;
        while (pad < column_padding - 1) : (pad += 1) {
            try writer.writeByte(' ');
        }
        try writer.writeAll("^\n");
    }

    const Location = struct {
        line: usize,
        column: usize,
        line_start: usize,
        line_end: usize,
    };

    fn locate(source: []const u8, offset: usize) Location {
        var line: usize = 1;
        var column: usize = 1;
        var line_start: usize = 0;
        var i: usize = 0;
        const clamped = @min(offset, source.len);
        while (i < clamped) : (i += 1) {
            if (source[i] == '\n') {
                line += 1;
                column = 1;
                line_start = i + 1;
            } else {
                column += 1;
            }
        }

        var line_end = source.len;
        i = line_start;
        while (i < source.len) : (i += 1) {
            if (source[i] == '\n') {
                line_end = i;
                break;
            }
        }

        return .{
            .line = line,
            .column = column,
            .line_start = line_start,
            .line_end = line_end,
        };
    }
};
