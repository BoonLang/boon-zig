const std = @import("std");
const boon = @import("boon");

pub const Command = enum {
    help,
    version,
};

pub fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    _ = stderr;
    const command = try parseArgs(allocator, args);
    switch (command) {
        .help => {
            try writeHelp(stdout);
            return 0;
        },
        .version => {
            try stdout.print("boon-zig {s}\n", .{boon.version});
            return 0;
        },
    }
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Command {
    _ = allocator;
    if (args.len <= 1) return .help;

    const arg = args[1];
    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "help")) {
        return .help;
    }
    if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "version")) {
        return .version;
    }

    return error.UnknownCommand;
}

pub fn writeHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\boon-zig
        \\
        \\Usage:
        \\  boon-zig [--help]
        \\  boon-zig [--version]
        \\
        \\This repository is in bootstrap mode. Parser, runtime, and renderer commands
        \\will be added in later phases from PLAN.md.
        \\
    );
}

test "parseArgs defaults to help" {
    const args = [_][]const u8{"boon-zig"};
    try std.testing.expectEqual(.help, try parseArgs(std.testing.allocator, &args));
}

test "parseArgs accepts version" {
    const args = [_][]const u8{"boon-zig", "--version"};
    try std.testing.expectEqual(.version, try parseArgs(std.testing.allocator, &args));
}

test "parseArgs rejects unknown commands" {
    const args = [_][]const u8{"boon-zig", "nope"};
    try std.testing.expectError(error.UnknownCommand, parseArgs(std.testing.allocator, &args));
}
