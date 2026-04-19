const std = @import("std");
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
    return switch (selected) {
        .threaded => Runtime.init(std.heap.smp_allocator, .{}),
        .evented => blk: {
            var runtime: Runtime = undefined;
            try runtime.init(std.heap.smp_allocator, .{});
            break :blk runtime;
        },
    };
}
