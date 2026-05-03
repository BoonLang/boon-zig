const std = @import("std");
const verify_physical = @import("verify_physical.zig");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();
    const selected_arg = args.next() orelse "-";
    const build_only_arg = args.next() orelse "false";
    const selected = if (std.mem.eql(u8, selected_arg, "-")) null else selected_arg;
    const build_only = std.mem.eql(u8, build_only_arg, "true");
    const ok = try verify_physical.run(std.heap.c_allocator, .native, selected, build_only, "examples/upstream");
    if (!ok) return error.PhysicalVerificationIncomplete;
}
