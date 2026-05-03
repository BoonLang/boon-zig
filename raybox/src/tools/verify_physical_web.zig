const std = @import("std");
const verify_physical = @import("verify_physical.zig");

export fn main(argc: c_int, argv: [*c][*c]u8) c_int {
    const selected = if (argc > 1 and !std.mem.eql(u8, std.mem.span(argv[1]), "-")) std.mem.span(argv[1]) else null;
    const build_only = argc > 2 and std.mem.eql(u8, std.mem.span(argv[2]), "true");
    const ok = verify_physical.run(std.heap.c_allocator, .web, selected, build_only, "examples/upstream") catch |err| {
        std.debug.print("verify-physical-web error: {s}\n", .{@errorName(err)});
        return 1;
    };
    return if (ok) 0 else 1;
}
