const std = @import("std");

const service_name = "com.system76.CosmicComp.BackgroundLaunch";
const object_path = "/com/system76/CosmicComp/BackgroundLaunch";
const interface_name = "com.system76.CosmicComp.BackgroundLaunch1";

fn usage() noreturn {
    std.debug.print("usage: cosmic-background-launch --workspace <name> -- <command> [args...]\n", .{});
    std.process.exit(2);
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.arena.allocator();

    const argv = try init.minimal.args.toSlice(allocator);
    if (argv.len < 5 or !std.mem.eql(u8, argv[1], "--workspace")) usage();
    const workspace_name = argv[2];
    if (workspace_name.len == 0 or !std.mem.eql(u8, argv[3], "--")) usage();
    const command_argv = argv[4..];
    if (command_argv.len == 0) usage();

    const helper_argv = try allocator.alloc([]const u8, argv.len);
    helper_argv[0] = "/usr/bin/cosmic-background-launch";
    @memcpy(helper_argv[1..], argv[1..]);

    const helper_result = try std.process.run(allocator, init.io, .{
        .argv = helper_argv,
    });

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);

    if (helper_result.term == .exited and helper_result.term.exited == 0) {
        try stdout_writer.interface.writeAll(helper_result.stdout);
        try stdout_writer.interface.flush();
        return 0;
    }
    if (!std.mem.containsAtLeast(u8, helper_result.stderr, 1, "Signature mismatch")) {
        try stderr_writer.interface.writeAll(helper_result.stderr);
        try stderr_writer.interface.flush();
        return exitCode(helper_result.term);
    }

    // Older live COSMIC sessions expose Launch(argv, cwd, env). Keep using the
    // background-launch service when /usr/bin/cosmic-background-launch has
    // already been upgraded to the newer workspace-aware ABI.
    const cwd = try std.process.currentPathAlloc(init.io, allocator);

    var busctl_argv: std.ArrayList([]const u8) = .empty;
    try busctl_argv.appendSlice(allocator, &.{
        "busctl",
        "--user",
        "--",
        "call",
        service_name,
        object_path,
        interface_name,
        "Launch",
        "assa{ss}",
        try std.fmt.allocPrint(allocator, "{}", .{command_argv.len}),
    });
    try busctl_argv.appendSlice(allocator, command_argv);
    try busctl_argv.appendSlice(allocator, &.{ cwd, "1", "SDL_VIDEODRIVER", "x11" });

    const fallback_result = try std.process.run(allocator, init.io, .{
        .argv = busctl_argv.items,
    });
    try stdout_writer.interface.writeAll(fallback_result.stdout);
    try stderr_writer.interface.writeAll(fallback_result.stderr);
    if (fallback_result.term == .exited and fallback_result.term.exited == 0 and shouldWaitForExit(command_argv)) {
        if (parseBusctlPid(fallback_result.stdout)) |pid| {
            waitForExit(init.io, allocator, pid) catch |err| {
                try stderr_writer.interface.print("background-launched process {d} did not exit: {s}\n", .{ pid, @errorName(err) });
                try stdout_writer.interface.flush();
                try stderr_writer.interface.flush();
                return 124;
            };
        }
    }
    try stdout_writer.interface.flush();
    try stderr_writer.interface.flush();
    return exitCode(fallback_result.term);
}

fn shouldWaitForExit(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.startsWith(u8, arg, "--exit-after-frames=")) return true;
        if (std.mem.startsWith(u8, arg, "--capture-frame=")) return true;
    }
    return false;
}

fn parseBusctlPid(stdout: []const u8) ?u32 {
    var parts = std.mem.tokenizeAny(u8, stdout, " \t\r\n");
    const kind = parts.next() orelse return null;
    if (!std.mem.eql(u8, kind, "us")) return null;
    const pid_text = parts.next() orelse return null;
    return std.fmt.parseUnsigned(u32, pid_text, 10) catch null;
}

fn waitForExit(io: std.Io, allocator: std.mem.Allocator, pid: u32) !void {
    const stat_path = try std.fmt.allocPrint(allocator, "/proc/{d}/stat", .{pid});
    var attempt: usize = 0;
    while (attempt < 300) : (attempt += 1) {
        if (!processExists(io, stat_path)) return;
        try std.Io.sleep(io, .fromMilliseconds(100), .awake);
    }
    return error.Timeout;
}

fn processExists(io: std.Io, stat_path: []const u8) bool {
    const file = std.Io.Dir.openFileAbsolute(io, stat_path, .{}) catch return false;
    file.close(io);
    return true;
}

fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| @intCast(@min(code, 255)),
        .signal => 128,
        .stopped => 128,
        .unknown => 1,
    };
}
