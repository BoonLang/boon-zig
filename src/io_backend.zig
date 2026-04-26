const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("boon_build_options");

pub const Backend = enum {
    threaded,
    evented,
};

pub const selected: Backend = std.meta.stringToEnum(Backend, build_options.io_backend) orelse
    @compileError("invalid -Dio_backend value; expected 'threaded' or 'evented'");

pub const Runtime = switch (selected) {
    .threaded => std.Io.Threaded,
    .evented => switch (@typeInfo(std.Io.Evented)) {
        .void => @compileError("std.Io.Evented is unavailable on this Zig/toolchain/target"),
        else => std.Io.Evented,
    },
};

pub fn init() !Runtime {
    const allocator = if (comptime builtin.single_threaded) std.heap.c_allocator else std.heap.smp_allocator;
    return switch (selected) {
        .threaded => Runtime.init(allocator, .{}),
        .evented => blk: {
            var runtime: Runtime = undefined;
            try runtime.init(allocator, .{});
            break :blk runtime;
        },
    };
}
