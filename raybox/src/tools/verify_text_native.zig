const std = @import("std");
const verify_text = @import("verify_text.zig");

pub fn main() !void {
    const report = try verify_text.run(std.heap.c_allocator);
    std.debug.print(
        "verify-text-native ok: czech={d:.2}x{d:.2} mono={d:.2} vertices={} atlas={}x{}\n",
        .{
            report.czech_width,
            report.czech_height,
            report.mono_width,
            report.draw_vertices,
            report.atlas_width,
            report.atlas_height,
        },
    );
}
