const std = @import("std");
const verify_text = @import("verify_text.zig");

export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    _ = argc;
    _ = argv;

    const report = verify_text.run(std.heap.c_allocator) catch return 1;
    if (report.draw_vertices == 0) return 1;
    return 0;
}
