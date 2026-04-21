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
        io,
        args,
        &stdout_writer.interface,
        &stderr_writer.interface,
    ) catch |err| switch (err) {
        error.UnknownCommand => blk: {
            try stderr_writer.interface.print("error: unknown command or flag\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingPath => blk: {
            try stderr_writer.interface.print("error: command requires a path\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingVirtualTime => blk: {
            try stderr_writer.interface.print("error: --virtual-time requires a duration like 2s or 500ms\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.InvalidDuration => blk: {
            try stderr_writer.interface.print("error: invalid duration, use forms like 2s or 500ms\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingScriptPath => blk: {
            try stderr_writer.interface.print("error: --script requires a path\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingExpectedText => blk: {
            try stderr_writer.interface.print("error: --expect-text requires a string\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingFrames => blk: {
            try stderr_writer.interface.print("error: --frames requires a count\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingPort => blk: {
            try stderr_writer.interface.print("error: --port requires a port number\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingFilter => blk: {
            try stderr_writer.interface.print("error: --filter requires a value like p0 or a case name\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingOutDir => blk: {
            try stderr_writer.interface.print("error: --out-dir requires a path\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.MissingVerifyMode => blk: {
            try stderr_writer.interface.print("error: verify-examples requires either --headless or --terminal-grid\n\n", .{});
            try cli.writeHelp(&stderr_writer.interface);
            break :blk 1;
        },
        error.InvalidHeadlessScript => blk: {
            try stderr_writer.interface.print("error: invalid headless script format\n", .{});
            break :blk 1;
        },
        error.InvalidTerminalCommand => blk: {
            try stderr_writer.interface.print("error: invalid terminal command\n", .{});
            break :blk 1;
        },
        error.ExpectedTerminalRoot => blk: {
            try stderr_writer.interface.print("error: `run` requires a Terminal/new root\n", .{});
            break :blk 1;
        },
        else => return err,
    };

    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    std.process.exit(exit_code);
}
