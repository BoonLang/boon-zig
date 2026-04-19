const std = @import("std");
const boon = @import("boon");
const browser_assets = @import("browser_assets");

pub const Command = union(enum) {
    help,
    version,
    format: []const u8,
    parse: []const u8,
    hir: []const u8,
    flow: []const u8,
    run_headless: HeadlessArgs,
    snapshot: SnapshotArgs,
    physical_state: SnapshotArgs,
    serve_browser: BrowserServeArgs,
    run_terminal: TerminalArgs,
};

pub const HeadlessArgs = struct {
    path: []const u8,
    trace: bool,
    virtual_time_ms: u64,
    state_dir: ?[]const u8,
    clear_state: bool,
    script_path: ?[]const u8,
    expect_text: ?[]const u8,
};

pub const SnapshotArgs = struct {
    path: []const u8,
    virtual_time_ms: u64,
    script_path: ?[]const u8,
    frames: u64,
    expect_text: ?[]const u8,
};

pub const BrowserServeArgs = struct {
    path: []const u8,
    port: u16,
};

pub const TerminalArgs = struct {
    path: []const u8,
    trace: bool,
    virtual_time_ms: u64,
    script_path: ?[]const u8,
};

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
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
        .format => |path| return try runFormat(allocator, io, path, stdout, stderr),
        .parse => |path| return try runParse(allocator, io, path, stdout, stderr),
        .hir => |path| return try runHir(allocator, io, path, stdout, stderr),
        .flow => |path| return try runFlow(allocator, io, path, stdout, stderr),
        .run_headless => |headless_args| return try runHeadless(allocator, io, headless_args, stdout, stderr),
        .snapshot => |snapshot_args| return try runSnapshot(allocator, io, snapshot_args, stdout, stderr),
        .physical_state => |snapshot_args| return try runPhysicalState(allocator, io, snapshot_args, stdout, stderr),
        .serve_browser => |browser_args| return try runServeBrowser(allocator, io, browser_args, stdout, stderr),
        .run_terminal => |terminal_args| return try runTerminal(allocator, io, terminal_args, stdout, stderr),
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
    if (std.mem.eql(u8, arg, "parse")) {
        if (args.len <= 2) return error.MissingPath;
        return .{ .parse = args[2] };
    }
    if (std.mem.eql(u8, arg, "format")) {
        if (args.len <= 2) return error.MissingPath;
        return .{ .format = args[2] };
    }
    if (std.mem.eql(u8, arg, "hir")) {
        if (args.len <= 2) return error.MissingPath;
        return .{ .hir = args[2] };
    }
    if (std.mem.eql(u8, arg, "flow")) {
        if (args.len <= 2) return error.MissingPath;
        return .{ .flow = args[2] };
    }
    if (std.mem.eql(u8, arg, "run-headless")) {
        if (args.len <= 2) return error.MissingPath;
        var trace = false;
        var virtual_time_ms: u64 = 0;
        var state_dir: ?[]const u8 = null;
        var clear_state = false;
        var script_path: ?[]const u8 = null;
        var expect_text: ?[]const u8 = null;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--trace")) {
                trace = true;
            } else if (std.mem.eql(u8, flag, "--virtual-time")) {
                index += 1;
                if (index >= args.len) return error.MissingVirtualTime;
                virtual_time_ms = try parseDurationArg(args[index]);
            } else if (std.mem.eql(u8, flag, "--state-dir")) {
                index += 1;
                if (index >= args.len) return error.MissingStateDir;
                state_dir = args[index];
            } else if (std.mem.eql(u8, flag, "--clear-state")) {
                clear_state = true;
            } else if (std.mem.eql(u8, flag, "--script")) {
                index += 1;
                if (index >= args.len) return error.MissingScriptPath;
                script_path = args[index];
            } else if (std.mem.eql(u8, flag, "--expect-text")) {
                index += 1;
                if (index >= args.len) return error.MissingExpectedText;
                expect_text = args[index];
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .run_headless = .{
            .path = args[2],
            .trace = trace,
            .virtual_time_ms = virtual_time_ms,
            .state_dir = state_dir,
            .clear_state = clear_state,
            .script_path = script_path,
            .expect_text = expect_text,
        } };
    }
    if (std.mem.eql(u8, arg, "snapshot")) {
        if (args.len <= 2) return error.MissingPath;
        var virtual_time_ms: u64 = 0;
        var script_path: ?[]const u8 = null;
        var frames: u64 = 1;
        var expect_text: ?[]const u8 = null;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--virtual-time")) {
                index += 1;
                if (index >= args.len) return error.MissingVirtualTime;
                virtual_time_ms = try parseDurationArg(args[index]);
            } else if (std.mem.eql(u8, flag, "--script")) {
                index += 1;
                if (index >= args.len) return error.MissingScriptPath;
                script_path = args[index];
            } else if (std.mem.eql(u8, flag, "--frames")) {
                index += 1;
                if (index >= args.len) return error.MissingFrames;
                frames = try std.fmt.parseInt(u64, args[index], 10);
            } else if (std.mem.eql(u8, flag, "--expect-text")) {
                index += 1;
                if (index >= args.len) return error.MissingExpectedText;
                expect_text = args[index];
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .snapshot = .{
            .path = args[2],
            .virtual_time_ms = virtual_time_ms,
            .script_path = script_path,
            .frames = frames,
            .expect_text = expect_text,
        } };
    }
    if (std.mem.eql(u8, arg, "physical-state")) {
        if (args.len <= 2) return error.MissingPath;
        var virtual_time_ms: u64 = 0;
        var script_path: ?[]const u8 = null;
        var frames: u64 = 1;
        var expect_text: ?[]const u8 = null;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--virtual-time")) {
                index += 1;
                if (index >= args.len) return error.MissingVirtualTime;
                virtual_time_ms = try parseDurationArg(args[index]);
            } else if (std.mem.eql(u8, flag, "--script")) {
                index += 1;
                if (index >= args.len) return error.MissingScriptPath;
                script_path = args[index];
            } else if (std.mem.eql(u8, flag, "--frames")) {
                index += 1;
                if (index >= args.len) return error.MissingFrames;
                frames = try std.fmt.parseInt(u64, args[index], 10);
            } else if (std.mem.eql(u8, flag, "--expect-text")) {
                index += 1;
                if (index >= args.len) return error.MissingExpectedText;
                expect_text = args[index];
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .physical_state = .{
            .path = args[2],
            .virtual_time_ms = virtual_time_ms,
            .script_path = script_path,
            .frames = frames,
            .expect_text = expect_text,
        } };
    }
    if (std.mem.eql(u8, arg, "serve-browser")) {
        if (args.len <= 2) return error.MissingPath;
        var port: u16 = 4176;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--port")) {
                index += 1;
                if (index >= args.len) return error.MissingPort;
                port = try std.fmt.parseInt(u16, args[index], 10);
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .serve_browser = .{
            .path = args[2],
            .port = port,
        } };
    }
    if (std.mem.eql(u8, arg, "run-terminal")) {
        if (args.len <= 2) return error.MissingPath;
        var trace = false;
        var virtual_time_ms: u64 = 0;
        var script_path: ?[]const u8 = null;
        var index: usize = 3;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--trace")) {
                trace = true;
            } else if (std.mem.eql(u8, flag, "--virtual-time")) {
                index += 1;
                if (index >= args.len) return error.MissingVirtualTime;
                virtual_time_ms = try parseDurationArg(args[index]);
            } else if (std.mem.eql(u8, flag, "--script")) {
                index += 1;
                if (index >= args.len) return error.MissingScriptPath;
                script_path = args[index];
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .run_terminal = .{
            .path = args[2],
            .trace = trace,
            .virtual_time_ms = virtual_time_ms,
            .script_path = script_path,
        } };
    }

    return error.UnknownCommand;
}

fn parseDurationArg(text: []const u8) !u64 {
    if (std.mem.endsWith(u8, text, "ms")) {
        return try std.fmt.parseInt(u64, text[0 .. text.len - 2], 10);
    }
    if (std.mem.endsWith(u8, text, "s")) {
        const seconds = try std.fmt.parseInt(u64, text[0 .. text.len - 1], 10);
        return seconds * 1000;
    }
    return error.InvalidDuration;
}

pub fn writeHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\boon-zig
        \\
        \\Usage:
        \\  boon-zig [--help]
        \\  boon-zig [--version]
        \\  boon-zig format <path>
        \\  boon-zig parse <path>
        \\  boon-zig hir <path>
        \\  boon-zig flow <path>
        \\  boon-zig run-headless <path> [--trace] [--virtual-time <duration>] [--state-dir <path>] [--clear-state] [--script <path>] [--expect-text <text>]
        \\  boon-zig snapshot <path> [--virtual-time <duration>] [--script <path>] [--frames <count>] [--expect-text <text>]
        \\  boon-zig physical-state <path> [--virtual-time <duration>] [--script <path>] [--frames <count>] [--expect-text <text>]
        \\  boon-zig serve-browser <path> [--port <port>]
        \\  boon-zig run-terminal <path> [--trace] [--virtual-time <duration>] [--script <path>]
        \\
        \\Current phase support:
        \\  format   Format a Boon source file in place.
        \\  parse    Lex and parse a Boon source file and print structural stats.
        \\  hir      Lower a Boon source file into HIR and print lowering stats.
        \\  flow     Lower a Boon source file into Flow IR and print graph stats.
        \\  run-headless  Run a Boon source file in the headless runtime.
        \\  snapshot  Render a deterministic terminal-grid snapshot from the headless document tree.
        \\  physical-state  Emit the current structured physical render target when one exists.
        \\  serve-browser  Serve the browser shell and /__boon/physical-state from the shared runtime host.
        \\  run-terminal  Run the documented interactive terminal fallback REPL on top of the snapshot/headless engine.
        \\
    );
}

fn runParse(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const outcome = try boon.parser.parseAlloc(allocator, source);
    switch (outcome) {
        .ok => |document| {
            var parsed = document;
            defer parsed.deinit();
            try stdout.print(
                "parsed {s}: tokens={d} groups={d} forms={d} bytes={d}\n",
                .{ path, parsed.token_count, parsed.group_count, parsed.form_count, parsed.source_len },
            );
            return 0;
        },
        .err => |failure| {
            try stderr.print("failed to parse {s}\n", .{path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

fn runFormat(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const outcome = try boon.fmt.formatAlloc(allocator, source);
    switch (outcome) {
        .ok => |formatted| {
            defer allocator.free(formatted);
            var cwd = std.Io.Dir.cwd();
            try cwd.writeFile(io, .{ .sub_path = path, .data = formatted });
            try stdout.print("formatted {s}\n", .{path});
            return 0;
        },
        .err => |failure| {
            try stderr.print("failed to format {s}\n", .{path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

fn runHir(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const outcome = try boon.hir.lowerAlloc(allocator, source);
    switch (outcome) {
        .ok => |document| {
            var lowered = document;
            defer lowered.deinit();
            try stdout.print(
                "lowered {s}: items={d} definitions={d} exprs={d} calls={d} forms={d} bytes={d}\n",
                .{
                    path,
                    lowered.items.len,
                    lowered.definition_count,
                    lowered.expr_count,
                    lowered.call_count,
                    lowered.form_count,
                    lowered.source_len,
                },
            );
            return 0;
        },
        .err => |failure| {
            try stderr.print("failed to lower {s}\n", .{path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

fn runFlow(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const outcome = try boon.flow_ir.lowerAlloc(allocator, source);
    switch (outcome) {
        .ok => |document| {
            var flowed = document;
            defer flowed.deinit();
            try stdout.print(
                "flowed {s}: bindings={d} nodes={d} link_ports={d} stateful={d} bytes={d}\n",
                .{
                    path,
                    flowed.bindings.len,
                    flowed.nodes.len,
                    flowed.link_port_count,
                    flowed.stateful_count,
                    flowed.source_len,
                },
            );
            return 0;
        },
        .err => |failure| {
            try stderr.print("failed to lower flow {s}\n", .{path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

fn runHeadless(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: HeadlessArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        args.path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const state_file_path = if (args.state_dir) |state_dir|
        try headlessStateFilePathAlloc(allocator, state_dir, args.path)
    else
        null;
    defer if (state_file_path) |path| allocator.free(path);

    const outcome = try boon.headless.runAlloc(allocator, source, .{
        .trace = args.trace,
        .virtual_time_ms = args.virtual_time_ms,
        .state_file_path = state_file_path,
        .clear_state = args.clear_state,
    });
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();

            if (args.script_path) |script_path| {
                const initial_render = try runtime.renderAlloc(allocator);
                defer allocator.free(initial_render);
                try executeHeadlessScript(allocator, io, script_path, &runtime);
            }

            if (args.trace) {
                const trace = try runtime.traceAlloc(allocator);
                defer allocator.free(trace);
                if (trace.len != 0) try stdout.print("{s}\n", .{trace});
            }

            const rendered = try runtime.renderAlloc(allocator);
            defer allocator.free(rendered);
            if (args.expect_text) |expected| {
                if (!std.mem.eql(u8, rendered, expected)) {
                    try stderr.print("expected render {s}, got {s}\n", .{ expected, rendered });
                    return 1;
                }
            }
            try stdout.print("render {s}\n", .{rendered});
            return 0;
        },
        .err => |failure| {
            try stderr.print("failed to run headless {s}\n", .{args.path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

fn runSnapshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: SnapshotArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    _ = args.frames;

    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        args.path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const outcome = try boon.headless.runAlloc(allocator, source, .{
        .virtual_time_ms = args.virtual_time_ms,
    });
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();

            if (args.script_path) |script_path| {
                try executeHeadlessScript(allocator, io, script_path, &runtime);
            }

            const snapshot = try runtime.snapshotAlloc(allocator);
            defer allocator.free(snapshot);
            if (args.expect_text) |expected| {
                if (!std.mem.eql(u8, snapshot, expected)) {
                    try stderr.print("expected snapshot {s}, got {s}\n", .{ expected, snapshot });
                    return 1;
                }
            }
            try stdout.print("snapshot\n{s}\n", .{snapshot});
            return 0;
        },
        .err => |failure| {
            try stderr.print("failed to snapshot {s}\n", .{args.path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

fn runPhysicalState(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: SnapshotArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    _ = args.frames;

    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        args.path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const outcome = try boon.headless.runAlloc(allocator, source, .{
        .virtual_time_ms = args.virtual_time_ms,
    });
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();

            if (args.script_path) |script_path| {
                try executeHeadlessScript(allocator, io, script_path, &runtime);
            }

            const target = try runtime.physicalRenderTarget(allocator);
            if (target) |resolved| {
                try writePhysicalRenderTargetJson(stdout, resolved);
                return 0;
            }
            try stderr.print("missing physical render target for {s}\n", .{args.path});
            return 1;
        },
        .err => |failure| {
            try stderr.print("failed to compute physical-state {s}\n", .{args.path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

fn runServeBrowser(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: BrowserServeArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        args.path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const address = try std.Io.net.IpAddress.parse("127.0.0.1", args.port);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    try stdout.print("browser runtime listening at http://127.0.0.1:{d}/\n", .{args.port});
    try stdout.flush();

    while (true) {
        var stream = try server.accept(io);
        serveBrowserConnection(allocator, io, &stream, args.path, source, stderr) catch |err| {
            try stderr.print("serve-browser connection error: {t}\n", .{err});
            try stderr.flush();
        };
    }
}

fn runTerminal(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: TerminalArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        args.path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(source);

    const outcome = try boon.headless.runAlloc(allocator, source, .{
        .trace = args.trace,
        .virtual_time_ms = args.virtual_time_ms,
    });
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();

            if (args.script_path) |script_path| {
                try executeHeadlessScript(allocator, io, script_path, &runtime);
            }

            var raw_terminal = enableRawTerminal() catch |err| switch (err) {
                error.NotATerminal => null,
                else => return err,
            };
            if (raw_terminal) |*mode| {
                defer mode.restore() catch {};
                const keyboard_mode = try detectKeyboardUiMode(allocator, &runtime);
                try stdout.writeAll("run-terminal keyboard mode\n");
                try writeTerminalKeyboardSummary(allocator, &runtime, stdout, keyboard_mode);
                try stdout.writeByte('\n');
                try stdout.flush();

                while (true) {
                    const loop_mode = try detectKeyboardUiMode(allocator, &runtime);
                    try renderTerminalKeyboardScreen(allocator, &runtime, stdout, loop_mode);
                    const should_continue = handleTerminalKeyboardInput(allocator, args, &runtime, stdout, stderr, loop_mode) catch |err| blk: {
                        try stderr.print("error: {s}\n", .{@errorName(err)});
                        try stderr.flush();
                        break :blk true;
                    };
                    if (!should_continue) break;
                }
                return 0;
            }

            var stdin_buffer: [2048]u8 = undefined;
            var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);

            try stdout.writeAll(
                \\run-terminal fallback
                \\Type `help` for commands, `quit` to exit.
                \\
            );
            try stdout.flush();

            while (true) {
                try renderTerminalScreen(allocator, &runtime, stdout);
                try stdout.writeAll("> ");
                try stdout.flush();

                const maybe_line = stdin_reader.interface.takeDelimiter('\n') catch |err| switch (err) {
                    error.ReadFailed => return err,
                    error.StreamTooLong => {
                        try stderr.writeAll("error: terminal input line too long\n");
                        try stderr.flush();
                        continue;
                    },
                };
                const raw_line = maybe_line orelse break;
                const line = std.mem.trim(u8, raw_line, " \r\t");
                if (line.len == 0) continue;
                if (std.mem.eql(u8, line, "quit") or std.mem.eql(u8, line, "exit")) break;
                if (std.mem.eql(u8, line, "help")) {
                    try writeTerminalHelp(stdout);
                    try stdout.flush();
                    continue;
                }
                if (std.mem.eql(u8, line, "render") or std.mem.eql(u8, line, "controls")) continue;
                if (std.mem.eql(u8, line, "trace")) {
                    if (!args.trace) {
                        try stderr.writeAll("error: run-terminal was not started with --trace\n");
                        try stderr.flush();
                        continue;
                    }
                    const trace = try runtime.traceAlloc(allocator);
                    defer allocator.free(trace);
                    try stdout.print("{s}\n", .{trace});
                    try stdout.flush();
                    continue;
                }

                executeTerminalCommand(allocator, &runtime, line) catch |err| {
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                    try stderr.flush();
                };
            }
            return 0;
        },
        .err => |failure| {
            try stderr.print("failed to run terminal {s}\n", .{args.path});
            try failure.render(source, stderr);
            return 1;
        },
    }
}

const RawTerminal = struct {
    original: std.posix.termios,

    fn restore(self: *const RawTerminal) !void {
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.original);
    }
};

const KeyboardUiMode = enum {
    generic,
    vertical_game,
    horizontal_game,
};

fn enableRawTerminal() !?RawTerminal {
    const original = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch |err| switch (err) {
        error.NotATerminal => return null,
        else => return err,
    };

    var raw = original;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
    return .{ .original = original };
}

fn renderTerminalKeyboardScreen(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
    mode: KeyboardUiMode,
) !void {
    try stdout.writeAll("\x1b[2J\x1b[H");
    switch (mode) {
        .generic => try renderTerminalScreen(allocator, runtime, stdout),
        .vertical_game, .horizontal_game => try renderTerminalGameScreen(allocator, runtime, stdout),
    }
    try writeTerminalKeyboardSummary(allocator, runtime, stdout, mode);
    try stdout.writeByte('\n');
    try stdout.flush();
}

fn handleTerminalKeyboardInput(
    allocator: std.mem.Allocator,
    args: TerminalArgs,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    mode: KeyboardUiMode,
) !bool {
    if (mode != .generic) {
        const snapshot = try runtime.snapshotAlloc(allocator);
        defer allocator.free(snapshot);
        const game_active = !isIdleGameSnapshot(snapshot);

        var fds = [_]std.posix.pollfd{
            .{
                .fd = std.posix.STDIN_FILENO,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };
        const ready = try std.posix.poll(&fds, 180);
        if (ready == 0) {
            if (game_active) {
                _ = try clickFirstKnownButton(runtime, allocator, &.{ "Tick" });
            }
            return true;
        }
    }

    var byte: [1]u8 = undefined;
    const amount = try std.posix.read(std.posix.STDIN_FILENO, &byte);
    if (amount == 0) return false;

    switch (byte[0]) {
        'q', 'Q' => return false,
        'r', 'R' => {
            _ = try clickFirstKnownButton(runtime, allocator, &.{ "Restart" });
            return true;
        },
        'h', 'H', '?' => {
            try writeTerminalKeyboardHelp(stdout);
            try stdout.flush();
            return true;
        },
        ':' => {
            const maybe_command = try readTerminalCommandLine(allocator, stdout);
            const command = maybe_command orelse return true;
            defer allocator.free(command);
            if (command.len == 0) return true;
            if (std.mem.eql(u8, command, "quit") or std.mem.eql(u8, command, "exit")) return false;
            if (std.mem.eql(u8, command, "help")) {
                try writeTerminalHelp(stdout);
                try stdout.flush();
                return true;
            }
            if (std.mem.eql(u8, command, "render") or std.mem.eql(u8, command, "controls")) return true;
            if (std.mem.eql(u8, command, "trace")) {
                if (!args.trace) {
                    try stderr.writeAll("error: run-terminal was not started with --trace\n");
                    try stderr.flush();
                    return true;
                }
                const trace = try runtime.traceAlloc(allocator);
                defer allocator.free(trace);
                try stdout.print("\n{s}\n", .{trace});
                try stdout.flush();
                return true;
            }
            executeTerminalCommand(allocator, runtime, command) catch |err| {
                try stderr.print("error: {s}\n", .{@errorName(err)});
                try stderr.flush();
            };
            return true;
        },
        't', 'T' => {
            if (!args.trace) {
                try stderr.writeAll("error: run-terminal was not started with --trace\n");
                try stderr.flush();
                return true;
            }
            const trace = try runtime.traceAlloc(allocator);
            defer allocator.free(trace);
            try stdout.print("\n{s}\n", .{trace});
            try stdout.flush();
            return true;
        },
        'a', 'A' => {
            _ = try clickFirstKnownButton(runtime, allocator, &.{ "Left" });
            return true;
        },
        'd', 'D' => {
            _ = try clickFirstKnownButton(runtime, allocator, &.{ "Right" });
            return true;
        },
        'w', 'W' => {
            if (!try clickFirstKnownButton(runtime, allocator, &.{ "Up" })) {
                _ = try clickFirstKnownButton(runtime, allocator, &.{ "Serve", "Launch" });
            }
            return true;
        },
        '\r', '\n' => {
            if (mode != .generic) {
                const snapshot = try runtime.snapshotAlloc(allocator);
                defer allocator.free(snapshot);
                if (isIdleGameSnapshot(snapshot)) {
                    _ = try clickFirstKnownButton(runtime, allocator, &.{ "Serve", "Launch" });
                }
                return true;
            }
            _ = try clickFirstKnownButton(runtime, allocator, &.{ "Serve", "Launch" });
            return true;
        },
        's', 'S' => {
            if (!try clickFirstKnownButton(runtime, allocator, &.{ "Down" })) {
                _ = try clickFirstKnownButton(runtime, allocator, &.{ "Tick" });
            }
            return true;
        },
        ' ' => {
            if (mode != .generic) {
                _ = try clickFirstKnownButton(runtime, allocator, &.{ "Tick" });
                return true;
            }
            _ = try clickPrimaryKeyboardAction(runtime, allocator);
            return true;
        },
        '1'...'9' => {
            try runtime.clickButton(byte[0] - '1');
            return true;
        },
        0x1b => return try handleTerminalEscapeSequence(runtime, allocator),
        else => return true,
    }
}

fn handleTerminalEscapeSequence(runtime: *boon.headless.Session, allocator: std.mem.Allocator) !bool {
    var sequence: [2]u8 = undefined;
    const count = try std.posix.read(std.posix.STDIN_FILENO, &sequence);
    if (count < 2 or sequence[0] != '[') return true;

    switch (sequence[1]) {
        'A' => {
            if (!try clickFirstKnownButton(runtime, allocator, &.{ "Up" })) {
                _ = try clickFirstKnownButton(runtime, allocator, &.{ "Serve", "Launch" });
            }
        },
        'B' => {
            if (!try clickFirstKnownButton(runtime, allocator, &.{ "Down" })) {
                _ = try clickFirstKnownButton(runtime, allocator, &.{ "Tick" });
            }
        },
        'C' => _ = try clickFirstKnownButton(runtime, allocator, &.{ "Right" }),
        'D' => _ = try clickFirstKnownButton(runtime, allocator, &.{ "Left" }),
        else => {},
    }
    return true;
}

fn readTerminalCommandLine(allocator: std.mem.Allocator, stdout: *std.Io.Writer) !?[]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try stdout.writeAll("\ncommand> ");
    try stdout.flush();

    while (true) {
        var byte: [1]u8 = undefined;
        const amount = try std.posix.read(std.posix.STDIN_FILENO, &byte);
        if (amount == 0) return null;

        switch (byte[0]) {
            '\r', '\n' => {
                try stdout.writeByte('\n');
                try stdout.flush();
                return try buffer.toOwnedSlice(allocator);
            },
            0x1b => {
                try stdout.writeAll("^C\n");
                try stdout.flush();
                return null;
            },
            0x7f, 0x08 => {
                if (buffer.items.len == 0) continue;
                _ = buffer.pop();
                try stdout.writeAll("\x08 \x08");
                try stdout.flush();
            },
            else => {
                try buffer.append(allocator, byte[0]);
                try stdout.writeByte(byte[0]);
                try stdout.flush();
            },
        }
    }
}

fn clickPrimaryKeyboardAction(runtime: *boon.headless.Session, allocator: std.mem.Allocator) !bool {
    const snapshot = try runtime.snapshotAlloc(allocator);
    defer allocator.free(snapshot);

    if (std.mem.indexOf(u8, snapshot, "Ball:-1") != null or std.mem.indexOf(u8, snapshot, "Ready") != null) {
        if (try clickFirstKnownButton(runtime, allocator, &.{ "Serve", "Launch" })) return true;
    }
    return try clickFirstKnownButton(runtime, allocator, &.{ "Tick", "Serve", "Launch" });
}

fn clickFirstKnownButton(runtime: *boon.headless.Session, allocator: std.mem.Allocator, labels: []const []const u8) !bool {
    for (labels) |label| {
        runtime.clickButtonByLabel(allocator, label) catch |err| switch (err) {
            error.UnknownControlLabel => continue,
            else => return err,
        };
        return true;
    }
    return false;
}

fn renderTerminalScreen(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
) !void {
    const snapshot = try runtime.snapshotAlloc(allocator);
    defer allocator.free(snapshot);
    const controls = try runtime.controlsAlloc(allocator);
    defer allocator.free(controls);
    try stdout.print("{s}\n\n{s}\n", .{ snapshot, controls });
    try stdout.flush();
}

fn writeTerminalHelp(stdout: *std.Io.Writer) !void {
    try stdout.writeAll(
        \\commands:
        \\  render
        \\  controls
        \\  trace
        \\  click <index>
        \\  click-label <text>
        \\  dblclick <index>
        \\  dblclick-label <text>
        \\  text <index> <value>
        \\  text-active <value>
        \\  key <index> <key>
        \\  key-active <key>
        \\  select <index> <value>
        \\  hover <index> on|off
        \\  hover-label <text> on|off
        \\  focus <index>
        \\  focus-active
        \\  blur <index>
        \\  blur-active
        \\  wait <milliseconds>
        \\  quit
        \\
    );
}

fn writeTerminalKeyboardHelp(stdout: *std.Io.Writer) !void {
    try stdout.writeAll(
        \\keyboard shortcuts:
        \\  Left Arrow / A   click label `Left`
        \\  Right Arrow / D  click label `Right`
        \\  Up Arrow / W     click label `Up`, else `Serve` or `Launch`
        \\  Down Arrow / S   click label `Down`, else `Tick`
        \\  Enter            click label `Serve` or `Launch`
        \\  Space            context-sensitive primary action
        \\  R                click label `Restart`
        \\  1-9              click visible button index 0-8
        \\  :                open the full command prompt for generic examples
        \\  T                print trace when `--trace` is enabled
        \\  H                show this help
        \\  Q                quit
        \\
    );
}

fn writeTerminalKeyboardSummary(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
    mode: KeyboardUiMode,
) !void {
    switch (mode) {
        .vertical_game => {
            try stdout.writeAll("keyboard: ↑/W up  ↓/S down  Enter serve/launch  R restart  Q quit");
            return;
        },
        .horizontal_game => {
            try stdout.writeAll("keyboard: ←/A left  →/D right  Enter serve/launch  R restart  Q quit");
            return;
        },
        .generic => {},
    }

    const controls = try runtime.controlsAlloc(allocator);
    defer allocator.free(controls);

    const has_up_down = std.mem.indexOf(u8, controls, "Up") != null or std.mem.indexOf(u8, controls, "Down") != null;
    const has_left_right = std.mem.indexOf(u8, controls, "Left") != null or std.mem.indexOf(u8, controls, "Right") != null;

    if (has_up_down) {
        try stdout.writeAll("keyboard: ↑/W up  ↓/S down  Enter serve  Space tick  1-9 buttons  : commands  H help  Q quit");
        return;
    }
    if (has_left_right) {
        try stdout.writeAll("keyboard: ←/A left  →/D right  Enter serve/launch  Space tick  1-9 buttons  : commands  H help  Q quit");
        return;
    }
    try stdout.writeAll("keyboard: arrows move or act  Enter primary  Space tick  1-9 buttons  : commands  H help  Q quit");
}

fn renderTerminalGameScreen(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
) !void {
    const snapshot = try runtime.snapshotAlloc(allocator);
    defer allocator.free(snapshot);

    var lines = std.mem.tokenizeScalar(u8, snapshot, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "[") and std.mem.indexOf(u8, line, "Tick") != null) continue;
        try stdout.print("{s}\n", .{line});
    }
    try stdout.flush();
}

fn detectKeyboardUiMode(allocator: std.mem.Allocator, runtime: *boon.headless.Session) !KeyboardUiMode {
    const controls = try runtime.controlsAlloc(allocator);
    defer allocator.free(controls);

    if (std.mem.indexOf(u8, controls, "Tick") != null and std.mem.indexOf(u8, controls, "Up") != null and std.mem.indexOf(u8, controls, "Down") != null) {
        return .vertical_game;
    }
    if (std.mem.indexOf(u8, controls, "Tick") != null and std.mem.indexOf(u8, controls, "Left") != null and std.mem.indexOf(u8, controls, "Right") != null) {
        return .horizontal_game;
    }
    return .generic;
}

fn isIdleGameSnapshot(snapshot: []const u8) bool {
    return std.mem.indexOf(u8, snapshot, "Press Enter") != null or std.mem.indexOf(u8, snapshot, "Ready") != null;
}

fn executeTerminalCommand(allocator: std.mem.Allocator, runtime: *boon.headless.Session, line: []const u8) !void {
    var parts = std.mem.tokenizeScalar(u8, line, ' ');
    const command = parts.next() orelse return error.InvalidTerminalCommand;
    if (std.mem.eql(u8, command, "click")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        return runtime.clickButton(index);
    }
    if (std.mem.eql(u8, command, "click-label")) {
        const value = parts.rest();
        if (value.len == 0) return error.InvalidTerminalCommand;
        return runtime.clickButtonByLabel(allocator, value);
    }
    if (std.mem.eql(u8, command, "dblclick")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        return runtime.doubleClickLabel(index);
    }
    if (std.mem.eql(u8, command, "dblclick-label")) {
        const value = parts.rest();
        if (value.len == 0) return error.InvalidTerminalCommand;
        return runtime.doubleClickLabelByText(allocator, value);
    }
    if (std.mem.eql(u8, command, "text")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        const value = parts.rest();
        if (value.len == 0) return error.InvalidTerminalCommand;
        return runtime.setTextInputValue(index, value);
    }
    if (std.mem.eql(u8, command, "text-active")) {
        const value = parts.rest();
        if (value.len == 0) return error.InvalidTerminalCommand;
        return runtime.setFirstTextInputValue(allocator, value);
    }
    if (std.mem.eql(u8, command, "key")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        const value = parts.next() orelse return error.InvalidTerminalCommand;
        return runtime.pressTextInputKey(index, value);
    }
    if (std.mem.eql(u8, command, "key-active")) {
        const value = parts.next() orelse return error.InvalidTerminalCommand;
        return runtime.pressFirstTextInputKey(allocator, value);
    }
    if (std.mem.eql(u8, command, "select")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        const value = parts.rest();
        if (value.len == 0) return error.InvalidTerminalCommand;
        return runtime.setSelectValue(index, value);
    }
    if (std.mem.eql(u8, command, "hover")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        const value = parts.next() orelse return error.InvalidTerminalCommand;
        return runtime.setHover(index, std.mem.eql(u8, value, "on") or std.mem.eql(u8, value, "true"));
    }
    if (std.mem.eql(u8, command, "hover-label")) {
        const rest = parts.rest();
        const separator = std.mem.lastIndexOfScalar(u8, rest, ' ') orelse return error.InvalidTerminalCommand;
        const label = std.mem.trim(u8, rest[0..separator], " ");
        const state_text = std.mem.trim(u8, rest[separator + 1 ..], " ");
        if (label.len == 0 or state_text.len == 0) return error.InvalidTerminalCommand;
        return runtime.setHoverByLabel(allocator, label, std.mem.eql(u8, state_text, "on") or std.mem.eql(u8, state_text, "true"));
    }
    if (std.mem.eql(u8, command, "focus")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        return runtime.focusTextInput(index);
    }
    if (std.mem.eql(u8, command, "focus-active")) {
        return runtime.focusFirstTextInput(allocator);
    }
    if (std.mem.eql(u8, command, "blur")) {
        const index = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        return runtime.blurTextInput(index);
    }
    if (std.mem.eql(u8, command, "blur-active")) {
        return runtime.blurFirstTextInput(allocator);
    }
    if (std.mem.eql(u8, command, "wait")) {
        const ms = try std.fmt.parseInt(u64, parts.next() orelse return error.InvalidTerminalCommand, 10);
        return runtime.advanceTime(ms);
    }
    return error.InvalidTerminalCommand;
}

fn parseTerminalIndex(text: []const u8) !usize {
    return try std.fmt.parseInt(usize, text, 10);
}

fn headlessStateFilePathAlloc(allocator: std.mem.Allocator, state_dir: []const u8, source_path: []const u8) ![]u8 {
    const stem = std.fs.path.stem(source_path);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(source_path);
    const digest = hasher.final();
    return try std.fmt.allocPrint(allocator, "{s}/{s}-{x}.json", .{ state_dir, stem, digest });
}

fn executeHeadlessScript(
    allocator: std.mem.Allocator,
    io: std.Io,
    script_path: []const u8,
    runtime: *boon.headless.Session,
) !void {
    const data = try std.Io.Dir.cwd().readFileAlloc(
        io,
        script_path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();

    const actions_value = switch (parsed.value) {
        .object => |object| object.get("actions") orelse return error.InvalidHeadlessScript,
        .array => |*array| std.json.Value{ .array = array.* },
        else => return error.InvalidHeadlessScript,
    };
    const actions = switch (actions_value) {
        .array => |array| array.items,
        else => return error.InvalidHeadlessScript,
    };

    for (actions) |action| {
        try executeHeadlessScriptAction(runtime, action);
    }
}

const RequestTarget = struct {
    path: []const u8,
    query: []const u8,
};

fn splitRequestTarget(target: []const u8) RequestTarget {
    if (std.mem.indexOfScalar(u8, target, '?')) |index| {
        return .{
            .path = target[0..index],
            .query = target[index + 1 ..],
        };
    }
    return .{ .path = target, .query = "" };
}

fn queryParam(query: []const u8, name: []const u8) ?[]const u8 {
    var iterator = std.mem.splitScalar(u8, query, '&');
    while (iterator.next()) |entry| {
        if (entry.len == 0) continue;
        if (std.mem.indexOfScalar(u8, entry, '=')) |index| {
            if (std.mem.eql(u8, entry[0..index], name)) return entry[index + 1 ..];
        } else if (std.mem.eql(u8, entry, name)) {
            return "";
        }
    }
    return null;
}

fn serveBrowserConnection(
    allocator: std.mem.Allocator,
    io: std.Io,
    stream: *std.Io.net.Stream,
    source_path: []const u8,
    source: []const u8,
    stderr: *std.Io.Writer,
) !void {
    defer stream.close(io);

    var send_buffer: [4096]u8 = undefined;
    var recv_buffer: [4096]u8 = undefined;
    var connection_reader = stream.reader(io, &recv_buffer);
    var connection_writer = stream.writer(io, &send_buffer);
    var server: std.http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    var request = server.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return,
        else => return err,
    };

    const target = splitRequestTarget(request.head.target);
    if (request.head.method != .GET) {
        try request.respond("method not allowed\n", .{
            .status = .method_not_allowed,
            .keep_alive = false,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
        });
        return;
    }
    if (std.mem.eql(u8, target.path, "/__boon/physical-state")) {
        const example = queryParam(target.query, "example") orelse "todo_mvc_physical";
        const theme = queryParam(target.query, "theme") orelse "Professional";
        const mode = queryParam(target.query, "mode") orelse "Light";
        if (!std.mem.eql(u8, example, "todo_mvc_physical")) {
            try request.respond("unsupported physical example\n", .{
                .status = .bad_request,
                .keep_alive = false,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
            });
            return;
        }

        const payload = physicalStateJsonAlloc(allocator, source, theme, mode) catch |err| {
            try stderr.print("serve-browser physical-state failed: {t}\n", .{err});
            try stderr.flush();
            try request.respond("failed to compute physical state\n", .{
                .status = .internal_server_error,
                .keep_alive = false,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
            });
            return;
        };
        defer allocator.free(payload);

        try request.respond(payload, .{
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Cache-Control", .value = "no-store" },
            },
        });
        return;
    }

    if (std.mem.eql(u8, target.path, "/manifest.json")) {
        const body = try browserManifestJsonAlloc(allocator, source_path, source);
        defer allocator.free(body);
        try request.respond(body, .{
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Cache-Control", .value = "no-store" },
            },
        });
        return;
    }

    if (browserAssetRelativePath(target.path)) |relative_path| {
        const body = browserAssetBody(relative_path) orelse {
            try request.respond("not found\n", .{
                .status = .not_found,
                .keep_alive = false,
                .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
            });
            return;
        };

        try request.respond(body, .{
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = browserAssetContentType(relative_path) },
                .{ .name = "Cache-Control", .value = "no-store" },
            },
        });
        return;
    }

    try request.respond("not found\n", .{
        .status = .not_found,
        .keep_alive = false,
        .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
    });
}

fn browserAssetRelativePath(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) return "index.html";
    if (std.mem.eql(u8, path, "/boon-browser.mjs")) return "boon-browser.mjs";
    return null;
}

fn browserAssetBody(relative_path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, relative_path, "index.html")) return browser_assets.index_html;
    if (std.mem.eql(u8, relative_path, "boon-browser.mjs")) return browser_assets.boon_browser_mjs;
    return null;
}

fn browserAssetContentType(relative_path: []const u8) []const u8 {
    if (std.mem.eql(u8, relative_path, "index.html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, relative_path, "boon-browser.mjs")) return "text/javascript; charset=utf-8";
    if (std.mem.eql(u8, relative_path, "manifest.json")) return "application/json";
    return "application/octet-stream";
}

fn physicalStateJsonAlloc(
    allocator: std.mem.Allocator,
    source: []const u8,
    theme: []const u8,
    mode: []const u8,
) ![]u8 {
    const outcome = try boon.headless.runAlloc(allocator, source, .{});
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();

            try applyPhysicalThemeAndMode(&runtime, theme, mode);
            const target = try runtime.physicalRenderTarget(allocator) orelse return error.MissingPhysicalRenderTarget;

            var out: std.Io.Writer.Allocating = .init(allocator);
            errdefer out.deinit();
            try writePhysicalRenderTargetJson(&out.writer, target);
            return try out.toOwnedSlice();
        },
        .err => return error.PhysicalStateUnavailable,
    }
}

fn browserManifestJsonAlloc(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source: []const u8,
) ![]u8 {
    const themes = [_][]const u8{ "Professional", "Glassmorphism", "Neobrutalism", "Neumorphism" };

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    try out.writer.writeAll("{\"bundle\":\"boon-zig-browser-host\"");
    try out.writer.writeAll(",\"supported_examples\":[\"counter\",\"interval\",\"cells\",\"cells_dynamic\",\"todo_mvc\",\"todo_mvc_physical\"]");
    try out.writer.writeAll(",\"storage\":\"IndexedDB primary with in-memory fallback for smoke environments\"");
    try out.writer.writeAll(",\"physical_render_targets\":{");
    for (themes, 0..) |theme, index| {
        const payload = try physicalStateJsonAlloc(allocator, source, theme, "Light");
        defer allocator.free(payload);
        const trimmed = std.mem.trimEnd(u8, payload, "\n");
        if (index != 0) try out.writer.writeByte(',');
        try writeJsonEscapedString(&out.writer, theme);
        try out.writer.writeByte(':');
        try out.writer.writeAll(trimmed);
    }
    try out.writer.writeAll("}");
    try out.writer.writeAll(",\"physical_render_target_source\":{");
    try out.writer.writeAll("\"example\":");
    try writeJsonEscapedString(&out.writer, source_path);
    try out.writer.writeAll(",\"runner\":\"serve-browser\"");
    try out.writer.writeAll(",\"themes\":[");
    for (themes, 0..) |theme, index| {
        if (index != 0) try out.writer.writeByte(',');
        try writeJsonEscapedString(&out.writer, theme);
    }
    try out.writer.writeAll("]}}");
    return try out.toOwnedSlice();
}

fn applyPhysicalThemeAndMode(runtime: *boon.headless.Session, theme: []const u8, mode: []const u8) !void {
    const theme_click: ?usize = if (std.mem.eql(u8, theme, "Professional"))
        null
    else if (std.mem.eql(u8, theme, "Glassmorphism"))
        1
    else if (std.mem.eql(u8, theme, "Neobrutalism"))
        2
    else if (std.mem.eql(u8, theme, "Neumorphism"))
        3
    else
        return error.UnsupportedThemeName;

    if (theme_click) |button_index| {
        try runtime.clickButton(button_index);
    }
    if (std.mem.eql(u8, mode, "Dark")) {
        try runtime.clickButton(4);
    } else if (!std.mem.eql(u8, mode, "Light")) {
        return error.UnsupportedModeName;
    }
}

fn executeHeadlessScriptAction(runtime: *boon.headless.Session, action: std.json.Value) !void {
    const parts = switch (action) {
        .array => |array| array.items,
        else => return error.InvalidHeadlessScript,
    };
    if (parts.len == 0) return error.InvalidHeadlessScript;

    const name = try jsonString(parts[0]);
    if (std.mem.eql(u8, name, "click_button")) {
        if (parts.len != 2) return error.InvalidHeadlessScript;
        try runtime.clickButton(try jsonIndex(parts[1]));
        return;
    }
    if (std.mem.eql(u8, name, "wait")) {
        if (parts.len != 2) return error.InvalidHeadlessScript;
        try runtime.advanceTime(try jsonU64(parts[1]));
        return;
    }
    if (std.mem.eql(u8, name, "set_text_input") or std.mem.eql(u8, name, "set_text_input_value")) {
        if (parts.len != 3) return error.InvalidHeadlessScript;
        try runtime.setTextInputValue(try jsonIndex(parts[1]), try jsonString(parts[2]));
        return;
    }
    if (std.mem.eql(u8, name, "press_text_input_key")) {
        if (parts.len != 3) return error.InvalidHeadlessScript;
        try runtime.pressTextInputKey(try jsonIndex(parts[1]), try jsonString(parts[2]));
        return;
    }
    if (std.mem.eql(u8, name, "set_select") or std.mem.eql(u8, name, "set_select_value")) {
        if (parts.len != 3) return error.InvalidHeadlessScript;
        try runtime.setSelectValue(try jsonIndex(parts[1]), try jsonString(parts[2]));
        return;
    }
    if (std.mem.eql(u8, name, "set_hover")) {
        if (parts.len != 3) return error.InvalidHeadlessScript;
        try runtime.setHover(try jsonIndex(parts[1]), try jsonBool(parts[2]));
        return;
    }
    if (std.mem.eql(u8, name, "focus_text_input")) {
        if (parts.len != 2) return error.InvalidHeadlessScript;
        try runtime.focusTextInput(try jsonIndex(parts[1]));
        return;
    }
    if (std.mem.eql(u8, name, "blur_text_input")) {
        if (parts.len != 2) return error.InvalidHeadlessScript;
        try runtime.blurTextInput(try jsonIndex(parts[1]));
        return;
    }
    if (std.mem.eql(u8, name, "double_click_label")) {
        if (parts.len != 2) return error.InvalidHeadlessScript;
        try runtime.doubleClickLabel(try jsonIndex(parts[1]));
        return;
    }
    return error.InvalidHeadlessScript;
}

fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.InvalidHeadlessScript,
    };
}

fn jsonBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |flag| flag,
        else => error.InvalidHeadlessScript,
    };
}

fn jsonU64(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => |number| if (number >= 0) @intCast(number) else error.InvalidHeadlessScript,
        .float => |number| if (number >= 0 and @floor(number) == number) @intFromFloat(number) else error.InvalidHeadlessScript,
        .number_string => |text| try std.fmt.parseInt(u64, text, 10),
        else => error.InvalidHeadlessScript,
    };
}

fn jsonIndex(value: std.json.Value) !usize {
    return @intCast(try jsonU64(value));
}

fn writePhysicalRenderTargetJson(writer: *std.Io.Writer, target: boon.headless.PhysicalRenderTarget) !void {
    try writer.print("{{\"kind\":\"{s}\"", .{target.kindLabel()});
    switch (target) {
        .ascii_strip => |ascii| {
            try writeJsonOptionalStringField(writer, "outer_shape", ascii.outer_shape);
            try writeJsonOptionalStringField(writer, "inner_shape", ascii.inner_shape);
            try writer.writeAll(",\"rows\":[");
            try writeJsonEscapedString(writer, &ascii.glyphs);
            try writer.writeAll("]}");
        },
        .cavity_panel => |panel| {
            try writeJsonOptionalStringField(writer, "outer_shape", panel.outer_shape);
            try writeJsonOptionalStringField(writer, "inner_shape", panel.inner_shape);
            try writer.writeAll(",\"rows\":[");
            for (panel.rows, 0..) |row, index| {
                if (index != 0) try writer.writeAll(",");
                try writeJsonEscapedString(writer, &row);
            }
            try writer.writeAll("]}");
        },
        .shaded_panel => |panel| {
            try writeJsonOptionalStringField(writer, "outer_shape", panel.outer_shape);
            try writeJsonOptionalStringField(writer, "inner_shape", panel.inner_shape);
            try writer.writeAll(",\"rows\":[");
            for (panel.rows, 0..) |row, index| {
                if (index != 0) try writer.writeAll(",");
                try writeJsonEscapedString(writer, &row);
            }
            try writer.writeAll("]}");
        },
        .lit_panel => |panel| {
            try writeJsonOptionalStringField(writer, "outer_shape", panel.outer_shape);
            try writeJsonOptionalStringField(writer, "inner_shape", panel.inner_shape);
            try writer.writeAll(",\"rows\":[");
            for (panel.rows, 0..) |row, index| {
                if (index != 0) try writer.writeAll(",");
                try writeJsonEscapedString(writer, &row);
            }
            try writer.writeAll("]");
            if (panel.material) |material| {
                try writer.writeAll(",\"material\":{");
                try writer.print("\"gloss\":{d},\"metal\":{d},\"glow\":{d},\"tone\":\"{s}\"", .{
                    material.gloss,
                    material.metal,
                    material.glow_intensity,
                    material.tone.label(),
                });
                try writer.writeAll("}");
            }
            try writer.writeAll("}");
        },
    }
    try writer.writeAll("\n");
}

fn writeJsonOptionalStringField(writer: *std.Io.Writer, name: []const u8, value: ?[]const u8) !void {
    if (value) |text| {
        try writer.print(",\"{s}\":", .{name});
        try writeJsonEscapedString(writer, text);
    }
}

fn writeJsonEscapedString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"', '\\' => {
            try writer.writeByte('\\');
            try writer.writeByte(byte);
        },
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => if (byte < 0x20) {
            try writer.print("\\u{X:0>4}", .{byte});
        } else {
            try writer.writeByte(byte);
        },
    };
    try writer.writeByte('"');
}

test "parseArgs defaults to help" {
    const args = [_][]const u8{"boon-zig"};
    try std.testing.expectEqual(.help, try parseArgs(std.testing.allocator, &args));
}

test "parseArgs accepts version" {
    const args = [_][]const u8{"boon-zig", "--version"};
    try std.testing.expectEqual(.version, try parseArgs(std.testing.allocator, &args));
}

test "parseArgs accepts parse path" {
    const args = [_][]const u8{"boon-zig", "parse", "examples/upstream/counter/counter.bn"};
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .parse => |path| try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", path),
        else => return error.ExpectedParseCommand,
    }
}

test "parseArgs accepts hir path" {
    const args = [_][]const u8{"boon-zig", "hir", "examples/upstream/counter/counter.bn"};
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .hir => |path| try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", path),
        else => return error.ExpectedHirCommand,
    }
}

test "parseArgs accepts physical-state path" {
    const args = [_][]const u8{"boon-zig", "physical-state", "examples/upstream/todo_mvc_physical/RUN.bn"};
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .physical_state => |physical_args| try std.testing.expectEqualStrings("examples/upstream/todo_mvc_physical/RUN.bn", physical_args.path),
        else => return error.ExpectedPhysicalStateCommand,
    }
}

test "parseArgs accepts serve-browser flags" {
    const args = [_][]const u8{
        "boon-zig",
        "serve-browser",
        "examples/upstream/todo_mvc_physical/RUN.bn",
        "--port",
        "4188",
    };
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .serve_browser => |browser_args| {
            try std.testing.expectEqualStrings("examples/upstream/todo_mvc_physical/RUN.bn", browser_args.path);
            try std.testing.expectEqual(@as(u16, 4188), browser_args.port);
        },
        else => return error.ExpectedServeBrowserCommand,
    }
}

test "parseArgs accepts flow path" {
    const args = [_][]const u8{"boon-zig", "flow", "examples/upstream/counter/counter.bn"};
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .flow => |path| try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", path),
        else => return error.ExpectedFlowCommand,
    }
}

test "parseArgs accepts run-headless flags" {
    const args = [_][]const u8{
        "boon-zig",
        "run-headless",
        "examples/upstream/counter/counter.bn",
        "--trace",
        "--virtual-time",
        "2s",
        "--state-dir",
        ".zig-cache/boon-state",
        "--clear-state",
        "--script",
        "tests/examples/counter_sequence.json",
        "--expect-text",
        "5+",
    };
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .run_headless => |headless_args| {
            try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", headless_args.path);
            try std.testing.expect(headless_args.trace);
            try std.testing.expectEqual(@as(u64, 2000), headless_args.virtual_time_ms);
            try std.testing.expectEqualStrings(".zig-cache/boon-state", headless_args.state_dir.?);
            try std.testing.expect(headless_args.clear_state);
            try std.testing.expectEqualStrings("tests/examples/counter_sequence.json", headless_args.script_path.?);
            try std.testing.expectEqualStrings("5+", headless_args.expect_text.?);
        },
        else => return error.ExpectedHeadlessCommand,
    }
}

test "parseArgs accepts snapshot flags" {
    const args = [_][]const u8{
        "boon-zig",
        "snapshot",
        "examples/upstream/counter/counter.bn",
        "--virtual-time",
        "2s",
        "--script",
        "tests/examples/counter_sequence.json",
        "--frames",
        "10",
        "--expect-text",
        "5\n[+]",
    };
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .snapshot => |snapshot_args| {
            try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", snapshot_args.path);
            try std.testing.expectEqual(@as(u64, 2000), snapshot_args.virtual_time_ms);
            try std.testing.expectEqualStrings("tests/examples/counter_sequence.json", snapshot_args.script_path.?);
            try std.testing.expectEqual(@as(u64, 10), snapshot_args.frames);
            try std.testing.expectEqualStrings("5\n[+]", snapshot_args.expect_text.?);
        },
        else => return error.ExpectedSnapshotCommand,
    }
}

test "parseDurationArg parses seconds and milliseconds" {
    try std.testing.expectEqual(@as(u64, 2000), try parseDurationArg("2s"));
    try std.testing.expectEqual(@as(u64, 1100), try parseDurationArg("1100ms"));
}

test "parseArgs rejects unknown commands" {
    const args = [_][]const u8{"boon-zig", "nope"};
    try std.testing.expectError(error.UnknownCommand, parseArgs(std.testing.allocator, &args));
}
