const std = @import("std");
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);

    const exit_code = cli.run(
        arena,
        args,
        &stdout_writer.interface,
        &stderr_writer.interface,
    ) catch |err| switch (err) {
        error.UnknownCommand => blk: {
            try stderr_writer.interface.print("error: unknown command or flag\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        else => return err,
    };

    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    std.process.exit(exit_code);
}
