const std = @import("std");
const builtin = @import("builtin");
const boon = @import("boon");
const browser_assets = @import("browser_assets");

pub const Command = union(enum) {
    help,
    version,
    format: []const u8,
    parse: []const u8,
    hir: []const u8,
    flow: []const u8,
    sync_corpus,
    verify_corpus: VerifyCorpusArgs,
    verify_upstream_pin,
    verify_examples: VerifyExamplesArgs,
    build_browser: BuildBrowserArgs,
    verify_visual: VerifyVisualArgs,
    example: TerminalArgs,
    run: TerminalArgs,
    run_headless: HeadlessArgs,
    snapshot: SnapshotArgs,
    physical_state: SnapshotArgs,
    serve_browser: BrowserServeArgs,
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

pub const VerifyCorpusArgs = struct {
    parse_only: bool,
};

pub const VerifyExamplesArgs = struct {
    mode: VerifyExamplesMode,
    filter: []const u8,
};

pub const VerifyExamplesMode = enum {
    headless,
    terminal_grid,
};

pub const BuildBrowserArgs = struct {
    out_dir: []const u8,
};

pub const VerifyVisualArgs = struct {
    filter: []const u8,
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
        .sync_corpus => return try runSyncCorpus(allocator, io, stdout, stderr),
        .verify_corpus => |verify_corpus_args| return try runVerifyCorpus(allocator, io, verify_corpus_args, stdout, stderr),
        .verify_upstream_pin => return try runVerifyUpstreamPin(allocator, io, stdout, stderr),
        .verify_examples => |verify_args| return try runVerifyExamples(allocator, io, verify_args, stdout, stderr),
        .build_browser => |build_browser_args| return try runBuildBrowser(allocator, io, build_browser_args, stdout, stderr),
        .verify_visual => |verify_visual_args| return try runVerifyVisual(allocator, io, verify_visual_args, stdout, stderr),
        .example => |terminal_args| return try runTerminal(allocator, io, terminal_args, stdout, stderr),
        .run => |terminal_args| return try runTerminal(allocator, io, terminal_args, stdout, stderr),
        .run_headless => |headless_args| return try runHeadless(allocator, io, headless_args, stdout, stderr),
        .snapshot => |snapshot_args| return try runSnapshot(allocator, io, snapshot_args, stdout, stderr),
        .physical_state => |snapshot_args| return try runPhysicalState(allocator, io, snapshot_args, stdout, stderr),
        .serve_browser => |browser_args| return try runServeBrowser(allocator, io, browser_args, stdout, stderr),
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
    if (std.mem.eql(u8, arg, "sync-corpus")) {
        return .sync_corpus;
    }
    if (std.mem.eql(u8, arg, "verify-corpus")) {
        var parse_only = false;
        var index: usize = 2;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--parse-only")) {
                parse_only = true;
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .verify_corpus = .{ .parse_only = parse_only } };
    }
    if (std.mem.eql(u8, arg, "verify-upstream-pin")) {
        if (args.len != 2) return error.UnknownCommand;
        return .verify_upstream_pin;
    }
    if (std.mem.eql(u8, arg, "verify-examples")) {
        var mode: ?VerifyExamplesMode = null;
        var filter: []const u8 = "p0";
        var index: usize = 2;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--headless")) {
                mode = .headless;
            } else if (std.mem.eql(u8, flag, "--terminal-grid")) {
                mode = .terminal_grid;
            } else if (std.mem.eql(u8, flag, "--filter")) {
                index += 1;
                if (index >= args.len) return error.MissingFilter;
                filter = args[index];
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .verify_examples = .{
            .mode = mode orelse return error.MissingVerifyMode,
            .filter = filter,
        } };
    }
    if (std.mem.eql(u8, arg, "build-browser")) {
        var out_dir: ?[]const u8 = null;
        var index: usize = 2;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--out-dir")) {
                index += 1;
                if (index >= args.len) return error.MissingOutDir;
                out_dir = args[index];
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .build_browser = .{
            .out_dir = out_dir orelse return error.MissingOutDir,
        } };
    }
    if (std.mem.eql(u8, arg, "verify-visual")) {
        var filter: ?[]const u8 = null;
        var index: usize = 2;
        while (index < args.len) : (index += 1) {
            const flag = args[index];
            if (std.mem.eql(u8, flag, "--filter")) {
                index += 1;
                if (index >= args.len) return error.MissingFilter;
                filter = args[index];
            } else if (std.mem.eql(u8, flag, "--all-with-reference-assets")) {
                filter = "todo_mvc";
            } else {
                return error.UnknownCommand;
            }
        }
        return .{ .verify_visual = .{
            .filter = filter orelse return error.MissingFilter,
        } };
    }
    if (std.mem.eql(u8, arg, "example")) {
        if (args.len <= 2) return error.MissingPath;
        return .{ .example = try parseTerminalArgs(try resolveExamplePath(args[2]), args, 3) };
    }
    if (std.mem.eql(u8, arg, "run") or std.mem.eql(u8, arg, "run-terminal")) {
        if (args.len <= 2) return error.MissingPath;
        return .{ .run = try parseTerminalArgs(args[2], args, 3) };
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
    return error.UnknownCommand;
}

fn parseTerminalArgs(path: []const u8, args: []const []const u8, start_index: usize) !TerminalArgs {
    var trace = false;
    var virtual_time_ms: u64 = 0;
    var script_path: ?[]const u8 = null;
    var index: usize = start_index;
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
    return .{
        .path = path,
        .trace = trace,
        .virtual_time_ms = virtual_time_ms,
        .script_path = script_path,
    };
}

fn resolveExamplePath(name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, name, "counter")) return "examples/terminal/counter/counter.bn";
    if (std.mem.eql(u8, name, "interval")) return "examples/terminal/interval/interval.bn";
    if (std.mem.eql(u8, name, "cells")) return "examples/terminal/cells/cells.bn";
    if (std.mem.eql(u8, name, "cells_dynamic")) return "examples/terminal/cells_dynamic/cells_dynamic.bn";
    if (std.mem.eql(u8, name, "todo_mvc")) return "examples/terminal/todo_mvc/todo_mvc.bn";
    if (std.mem.eql(u8, name, "pong")) return "examples/terminal/pong/pong.bn";
    if (std.mem.eql(u8, name, "arkanoid")) return "examples/terminal/arkanoid/arkanoid.bn";
    if (std.mem.eql(u8, name, "todo_mvc_physical")) return "examples/upstream/todo_mvc_physical/RUN.bn";
    if (std.mem.indexOfScalar(u8, name, '/') != null or std.mem.endsWith(u8, name, ".bn")) return name;
    return error.UnknownExample;
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
        \\  boon-zig sync-corpus
        \\  boon-zig verify-corpus [--parse-only]
        \\  boon-zig verify-upstream-pin
        \\  boon-zig verify-examples --headless|--terminal-grid [--filter <name|p0>]
        \\  boon-zig build-browser --out-dir <path>
        \\  boon-zig verify-visual --filter <name>|--all-with-reference-assets
        \\  boon-zig example <name> [--trace] [--virtual-time <duration>] [--script <path>]
        \\  boon-zig run <path> [--trace] [--virtual-time <duration>] [--script <path>]
        \\  boon-zig run-headless <path> [--trace] [--virtual-time <duration>] [--state-dir <path>] [--clear-state] [--script <path>] [--expect-text <text>]
        \\  boon-zig snapshot <path> [--virtual-time <duration>] [--script <path>] [--frames <count>] [--expect-text <text>]
        \\  boon-zig physical-state <path> [--virtual-time <duration>] [--script <path>] [--frames <count>] [--expect-text <text>]
        \\  boon-zig serve-browser <path> [--port <port>]
        \\
        \\Current phase support:
        \\  format   Format a Boon source file in place.
        \\  parse    Lex and parse a Boon source file and print structural stats.
        \\  hir      Lower a Boon source file into HIR and print lowering stats.
        \\  flow     Lower a Boon source file into Flow IR and print graph stats.
        \\  sync-corpus  Sync the pinned upstream playground example tree into examples/upstream.
        \\  verify-corpus  Verify the imported upstream tree and parser coverage.
        \\  verify-upstream-pin  Verify fixtures/upstream_pin.json matches compiled corpus constants.
        \\  verify-examples  Run Zig-native example verification lanes.
        \\  build-browser  Export the browser host bundle and manifest.
        \\  verify-visual  Run the browser visual comparison lane.
        \\  example  Run a built-in example by short name: counter, interval, cells, cells_dynamic, todo_mvc, pong, arkanoid.
        \\  run     Run a Terminal/new Boon source file in the interactive terminal host.
        \\  run-headless  Run a Boon source file in the headless runtime.
        \\  snapshot  Render a deterministic terminal-grid snapshot from the headless document tree.
        \\  physical-state  Emit the current structured physical render target when one exists.
        \\  serve-browser  Serve the browser shell and /__boon/physical-state from the shared runtime host.
        \\
    );
}

const VerifyExpectedText = union(enum) {
    exact: []const u8,
    contains: []const u8,
};

const VerifyAction = union(enum) {
    click_button: usize,
    press_key: []const u8,
    wait_ms: u64,
    mouse_move: struct { x: usize, y: usize },
    mouse_click: struct { x: usize, y: usize },
    mouse_double_click: struct { x: usize, y: usize },
    mouse_double_click_first_label,
};

const VerifyHeadlessCase = struct {
    name: []const u8,
    path: []const u8,
    virtual_time_ms: u64 = 0,
    actions: []const VerifyAction = &.{},
    expected: VerifyExpectedText,
};

const VerifySnapshotCase = struct {
    name: []const u8,
    path: []const u8,
    expected_text: []const u8,
    virtual_time_ms: u64 = 0,
    actions: []const VerifyAction = &.{},
};

const corpus_upstream_url = "https://github.com/BoonLang/boon";
const corpus_pinned_commit = "c924d9f7d7e1c156604c9377e0487db48c278353";
const corpus_upstream_root = "third_party/boon-upstream";
const corpus_upstream_examples_root = "third_party/boon-upstream/playground/frontend/src/examples";
const corpus_imported_examples_root = "examples/upstream";
const corpus_override_root = "examples/upstream_overrides";
const corpus_upstream_pin_path = "fixtures/upstream_pin.json";
const browser_todo_physical_path = "examples/upstream/todo_mvc_physical/RUN.bn";
const browser_visual_reference_path = "examples/upstream/todo_mvc/reference_700x700_(1400x1400).png";
const browser_visual_output_dir = ".artifacts/browser_visual";
const browser_visual_port: u16 = 4173;
const browser_visual_similarity_threshold = 0.83;
const planned_terminal_p0_examples = [_][]const u8{ "pong", "arkanoid" };

const verify_counter_actions = [_]VerifyAction{
    .{ .click_button = 0 },
    .{ .click_button = 0 },
    .{ .click_button = 0 },
    .{ .click_button = 0 },
    .{ .click_button = 0 },
};

const verify_pong_actions = [_]VerifyAction{
    .{ .press_key = "Enter" },
    .{ .press_key = "Space" },
    .{ .press_key = "Space" },
    .{ .press_key = "Space" },
    .{ .press_key = "Space" },
    .{ .press_key = "Space" },
    .{ .press_key = "Enter" },
    .{ .press_key = "Space" },
};

const verify_arkanoid_actions = [_]VerifyAction{
    .{ .press_key = "Right" },
    .{ .press_key = "Enter" },
    .{ .press_key = "Space" },
};

const headless_p0_cases = [_]VerifyHeadlessCase{
    .{
        .name = "counter",
        .path = "examples/terminal/counter/counter.bn",
        .actions = &verify_counter_actions,
        .expected = .{ .exact = "5+" },
    },
    .{
        .name = "interval",
        .path = "examples/terminal/interval/interval.bn",
        .virtual_time_ms = 2000,
        .expected = .{ .exact = "2" },
    },
    .{
        .name = "cells",
        .path = "examples/terminal/cells/cells.bn",
        .expected = .{ .contains = "Focus A0  Hover none ReadyFormula  A0 : 5|    |[A   ]|B   ||C   ||D   ||E   ||F   ||G   ||H   ||I   ||J   ||K   ||L   |[ 0  ][5   ]| 15 || 30 || 3  ||note||" },
    },
    .{
        .name = "todo_mvc",
        .path = "examples/terminal/todo_mvc/todo_mvc.bn",
        .expected = .{ .exact = "todos❯NoElementBuy groceriesNoElementClean room 2itemsleftAllActiveCompletedNoElementDouble-click to edit a todoCreated by Martin KavíkPart of TodoMVC" },
    },
    .{
        .name = "pong",
        .path = "examples/terminal/pong/pong.bn",
        .actions = &verify_pong_actions,
        .expected = .{ .exact = "PONGYOU0CPU0STATUSRally########################.....................##.....................##[].................[]##[]..............o..[]##[].................[]##.....................##.....................########################" },
    },
    .{
        .name = "arkanoid",
        .path = "examples/terminal/arkanoid/arkanoid.bn",
        .actions = &verify_arkanoid_actions,
        .expected = .{ .exact = "Arkanoid########.....o.....p....######Bricks:2 Paddle:1 Ball:1 Flight" },
    },
};

const terminal_grid_p0_cases = [_]VerifySnapshotCase{
    .{
        .name = "counter",
        .path = "examples/terminal/counter/counter.bn",
        .expected_text = @embedFile("verify_terminal_grid/counter.expected"),
        .actions = &verify_counter_actions,
    },
    .{
        .name = "interval",
        .path = "examples/terminal/interval/interval.bn",
        .expected_text = @embedFile("verify_terminal_grid/interval.expected"),
        .virtual_time_ms = 2000,
    },
    .{
        .name = "cells",
        .path = "examples/terminal/cells/cells.bn",
        .expected_text = @embedFile("verify_terminal_grid/cells.expected"),
    },
    .{
        .name = "todo_mvc",
        .path = "examples/terminal/todo_mvc/todo_mvc.bn",
        .expected_text = @embedFile("verify_terminal_grid/todo_mvc.expected"),
    },
    .{
        .name = "pong",
        .path = "examples/terminal/pong/pong.bn",
        .expected_text = @embedFile("verify_terminal_grid/pong.expected"),
        .actions = &verify_pong_actions,
    },
    .{
        .name = "arkanoid",
        .path = "examples/terminal/arkanoid/arkanoid.bn",
        .expected_text = @embedFile("verify_terminal_grid/arkanoid.expected"),
        .actions = &verify_arkanoid_actions,
    },
};

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

fn runSyncCorpus(
    allocator: std.mem.Allocator,
    io: std.Io,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    _ = stderr;
    try ensureCorpusUpstreamReady(allocator, io);
    try syncCorpusExamples(allocator, io);
    try stdout.print("sync-corpus ok\n", .{});
    return 0;
}

fn runVerifyCorpus(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: VerifyCorpusArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    try ensureCorpusUpstreamReady(allocator, io);

    var failures: std.ArrayList([]u8) = .empty;
    defer {
        for (failures.items) |item| allocator.free(item);
        failures.deinit(allocator);
    }

    if (!args.parse_only) {
        try verifyCorpusImportedTree(allocator, io, &failures);
    }

    const blocked = try verifyCorpusParses(allocator, io);
    if (failures.items.len != 0) {
        try stderr.print("verify-corpus failed\n", .{});
        for (failures.items) |failure| {
            try stderr.print("- {s}\n", .{failure});
        }
        return 1;
    }

    if (blocked != 0) {
        try stdout.print("verify-corpus ok ({d} parser blockers detected)\n", .{blocked});
        return 0;
    }

    try stdout.print("verify-corpus ok\n", .{});
    return 0;
}

fn runVerifyUpstreamPin(
    allocator: std.mem.Allocator,
    io: std.Io,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(
        io,
        corpus_upstream_pin_path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
    defer allocator.free(data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();

    const object = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidUpstreamPin,
    };

    var failures: std.ArrayList([]u8) = .empty;
    defer {
        for (failures.items) |item| allocator.free(item);
        failures.deinit(allocator);
    }

    try verifyPinString(allocator, &failures, object, "repo", corpus_upstream_url);
    try verifyPinString(allocator, &failures, object, "commit", corpus_pinned_commit);
    try verifyPinString(allocator, &failures, object, "source_root", corpus_upstream_examples_root);
    try verifyPinString(allocator, &failures, object, "imported_root", corpus_imported_examples_root);
    try verifyPinString(allocator, &failures, object, "override_root", corpus_override_root);

    const expected_tree_hash = try importedCorpusTreeHashAlloc(allocator, io);
    defer allocator.free(expected_tree_hash);
    try verifyPinString(allocator, &failures, object, "tree_hash", expected_tree_hash);

    if (failures.items.len != 0) {
        try stderr.print("verify-upstream-pin failed\n", .{});
        for (failures.items) |failure| {
            try stderr.print("- {s}\n", .{failure});
        }
        return 1;
    }

    try stdout.print("verify-upstream-pin ok\n", .{});
    return 0;
}

fn verifyPinString(
    allocator: std.mem.Allocator,
    failures: *std.ArrayList([]u8),
    object: anytype,
    field: []const u8,
    expected: []const u8,
) !void {
    const value = object.get(field) orelse {
        try failures.append(allocator, try std.fmt.allocPrint(allocator, "{s}: missing field", .{field}));
        return;
    };
    const actual = switch (value) {
        .string => |text| text,
        else => {
            try failures.append(allocator, try std.fmt.allocPrint(allocator, "{s}: expected string field", .{field}));
            return;
        },
    };
    if (!std.mem.eql(u8, actual, expected)) {
        try failures.append(
            allocator,
            try std.fmt.allocPrint(allocator, "{s}: expected `{s}`, found `{s}`", .{ field, expected, actual }),
        );
    }
}

fn importedCorpusTreeHashAlloc(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = &.{ "git", "ls-files", "-s", corpus_imported_examples_root, corpus_override_root },
        .stderr_limit = .limited(8 * 1024),
        .stdout_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.UpstreamPinGitLsFilesFailed,
        else => return error.UpstreamPinGitLsFilesFailed,
    }

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(result.stdout, &digest, .{});
    return try std.fmt.allocPrint(allocator, "{x}", .{digest});
}

fn runBuildBrowser(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: BuildBrowserArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    _ = stderr;
    var cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, args.out_dir);
    const index_path = try std.fs.path.join(allocator, &.{ args.out_dir, "index.html" });
    defer allocator.free(index_path);
    try cwd.writeFile(io, .{ .sub_path = index_path, .data = browser_assets.index_html });
    const module_path = try std.fs.path.join(allocator, &.{ args.out_dir, "boon-browser.mjs" });
    defer allocator.free(module_path);
    try cwd.writeFile(io, .{ .sub_path = module_path, .data = browser_assets.boon_browser_mjs });

    const source = try cwd.readFileAlloc(io, browser_todo_physical_path, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(source);

    const manifest = try browserManifestJsonAlloc(allocator, browser_todo_physical_path, source);
    defer allocator.free(manifest);

    const manifest_path = try std.fs.path.join(allocator, &.{ args.out_dir, "manifest.json" });
    defer allocator.free(manifest_path);
    try cwd.writeFile(io, .{ .sub_path = manifest_path, .data = manifest });

    try stdout.print("built browser bundle in {s}\n", .{args.out_dir});
    return 0;
}

fn runVerifyVisual(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: VerifyVisualArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    if (!std.mem.eql(u8, args.filter, "todo_mvc")) {
        try stderr.print("verify-visual currently supports only --filter todo_mvc or --all-with-reference-assets\n", .{});
        return 2;
    }

    try std.Io.Dir.cwd().createDirPath(io, browser_visual_output_dir);

    var self_exe_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const self_exe_len = try std.process.executablePath(io, &self_exe_buffer);
    const self_exe = self_exe_buffer[0..self_exe_len];

    const port_text = try std.fmt.allocPrint(allocator, "{d}", .{browser_visual_port});
    defer allocator.free(port_text);

    var server = try std.process.spawn(io, .{
        .argv = &.{ self_exe, "serve-browser", "examples/upstream/todo_mvc/todo_mvc.bn", "--port", port_text },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    defer server.kill(io);

    try waitForBrowserServer(io, browser_visual_port);

    const current_path = try std.fs.path.join(allocator, &.{ browser_visual_output_dir, "todo_mvc.current.png" });
    defer allocator.free(current_path);
    const diff_path = try std.fs.path.join(allocator, &.{ browser_visual_output_dir, "todo_mvc.diff.png" });
    defer allocator.free(diff_path);
    const visual_url = try std.fmt.allocPrint(
        allocator,
        "http://127.0.0.1:{d}/index.html?example=todo_mvc&visual=1",
        .{browser_visual_port},
    );
    defer allocator.free(visual_url);
    const screenshot_arg = try std.fmt.allocPrint(allocator, "--screenshot={s}", .{current_path});
    defer allocator.free(screenshot_arg);

    const screenshot = try std.process.run(allocator, io, .{
        .argv = &.{
            "/snap/bin/chromium",
            "--headless",
            "--disable-gpu",
            "--hide-scrollbars",
            "--window-size=1400,1400",
            "--run-all-compositor-stages-before-draw",
            "--virtual-time-budget=2000",
            screenshot_arg,
            visual_url,
        },
        .stderr_limit = .limited(16 * 1024),
        .stdout_limit = .limited(16 * 1024),
    });
    defer allocator.free(screenshot.stdout);
    defer allocator.free(screenshot.stderr);
    switch (screenshot.term) {
        .exited => |code| if (code != 0) {
            try stderr.print("verify-visual failed: chromium exited with {d}\n{s}{s}\n", .{ code, screenshot.stdout, screenshot.stderr });
            return 1;
        },
        else => {
            try stderr.print("verify-visual failed: chromium did not exit cleanly\n", .{});
            return 1;
        },
    }

    const compare = try std.process.run(allocator, io, .{
        .argv = &.{ "compare", "-metric", "RMSE", browser_visual_reference_path, current_path, diff_path },
        .stderr_limit = .limited(16 * 1024),
        .stdout_limit = .limited(16 * 1024),
    });
    defer allocator.free(compare.stdout);
    defer allocator.free(compare.stderr);

    const similarity = try parseImagemagickRmseSimilarity(compare.stderr);
    if (similarity < browser_visual_similarity_threshold) {
        try stderr.print(
            "verify-visual failed: todo_mvc similarity {d:.4} below threshold {d:.2}\nreference={s}\ncurrent={s}\ndiff={s}\n",
            .{ similarity, browser_visual_similarity_threshold, browser_visual_reference_path, current_path, diff_path },
        );
        return 1;
    }

    try stdout.print("PASS todo_mvc similarity {d:.4}\n", .{similarity});
    try stdout.print("current={s}\n", .{current_path});
    try stdout.print("diff={s}\n", .{diff_path});
    try stdout.print("verify-visual ok (1 passed)\n", .{});
    return 0;
}

fn ensureCorpusUpstreamReady(
    allocator: std.mem.Allocator,
    io: std.Io,
) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, corpus_upstream_root, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try cwd.createDirPath(io, "third_party");
            const clone = try std.process.run(allocator, io, .{
                .argv = &.{ "git", "clone", corpus_upstream_url, corpus_upstream_root },
                .stderr_limit = .limited(32 * 1024),
                .stdout_limit = .limited(32 * 1024),
            });
            defer allocator.free(clone.stdout);
            defer allocator.free(clone.stderr);
            switch (clone.term) {
                .exited => |code| if (code != 0) return error.CorpusGitCloneFailed,
                else => return error.CorpusGitCloneFailed,
            }
        },
        else => return err,
    };

    cwd.access(io, corpus_upstream_examples_root, .{}) catch return error.MissingUpstreamExamplesTree;

    const cat_file_arg = try std.fmt.allocPrint(allocator, "{s}^{{commit}}", .{corpus_pinned_commit});
    defer allocator.free(cat_file_arg);
    const cat_file = try std.process.run(allocator, io, .{
        .argv = &.{ "git", "cat-file", "-e", cat_file_arg },
        .cwd = .{ .path = corpus_upstream_root },
        .stderr_limit = .limited(8 * 1024),
        .stdout_limit = .limited(8 * 1024),
    });
    defer allocator.free(cat_file.stdout);
    defer allocator.free(cat_file.stderr);
    const pinned_available = switch (cat_file.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!pinned_available) {
        const fetch = try std.process.run(allocator, io, .{
            .argv = &.{ "git", "fetch", "--all", "--tags", "--prune" },
            .cwd = .{ .path = corpus_upstream_root },
            .stderr_limit = .limited(32 * 1024),
            .stdout_limit = .limited(32 * 1024),
        });
        defer allocator.free(fetch.stdout);
        defer allocator.free(fetch.stderr);
        switch (fetch.term) {
            .exited => |code| if (code != 0) return error.CorpusGitFetchFailed,
            else => return error.CorpusGitFetchFailed,
        }
    }

    const checkout = try std.process.run(allocator, io, .{
        .argv = &.{ "git", "checkout", corpus_pinned_commit },
        .cwd = .{ .path = corpus_upstream_root },
        .stderr_limit = .limited(32 * 1024),
        .stdout_limit = .limited(32 * 1024),
    });
    defer allocator.free(checkout.stdout);
    defer allocator.free(checkout.stderr);
    switch (checkout.term) {
        .exited => |code| if (code != 0) return error.CorpusGitCheckoutFailed,
        else => return error.CorpusGitCheckoutFailed,
    }
}

fn syncCorpusExamples(
    allocator: std.mem.Allocator,
    io: std.Io,
) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, corpus_imported_examples_root, .{}) catch |err| switch (err) {
        error.FileNotFound => {},
        else => try cwd.deleteTree(io, corpus_imported_examples_root),
    };
    try cwd.createDirPath(io, corpus_imported_examples_root);
    try copyDirectoryTree(allocator, io, corpus_upstream_examples_root, corpus_imported_examples_root);
    cwd.access(io, corpus_override_root, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    try copyDirectoryTree(allocator, io, corpus_override_root, corpus_imported_examples_root);
}

fn verifyCorpusImportedTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList([]u8),
) !void {
    const imported_files = try collectRelativeFiles(allocator, io, corpus_imported_examples_root);
    defer freeOwnedStringSlice(allocator, imported_files);

    const source_files = try collectRelativeFiles(allocator, io, corpus_upstream_examples_root);
    defer freeOwnedStringSlice(allocator, source_files);

    var override_files: ?[][]u8 = null;
    std.Io.Dir.cwd().access(io, corpus_override_root, .{}) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    if (std.Io.Dir.cwd().access(io, corpus_override_root, .{})) |_| {
        override_files = try collectRelativeFiles(allocator, io, corpus_override_root);
    } else |_| {}
    defer if (override_files) |items| freeOwnedStringSlice(allocator, items);

    var expected_map: std.StringHashMap(void) = .init(allocator);
    defer expected_map.deinit();
    for (source_files) |path| try expected_map.put(path, {});
    if (override_files) |items| for (items) |path| try expected_map.put(path, {});

    var imported_map: std.StringHashMap(void) = .init(allocator);
    defer imported_map.deinit();
    for (imported_files) |path| try imported_map.put(path, {});

    var expected_iter = expected_map.iterator();
    while (expected_iter.next()) |entry| {
        const path = entry.key_ptr.*;
        if (!imported_map.contains(path)) {
            try failures.append(allocator, try std.fmt.allocPrint(allocator, "missing imported file: {s}", .{path}));
            continue;
        }
    }
    var imported_iter = imported_map.iterator();
    while (imported_iter.next()) |entry| {
        const path = entry.key_ptr.*;
        if (!expected_map.contains(path)) {
            try failures.append(allocator, try std.fmt.allocPrint(allocator, "unexpected imported file: {s}", .{path}));
        }
    }
}

fn verifyCorpusParses(
    allocator: std.mem.Allocator,
    io: std.Io,
) !usize {
    var blocked: usize = 0;
    const imported_files = try collectRelativeFilesWithSuffix(allocator, io, corpus_imported_examples_root, ".bn");
    defer freeOwnedStringSlice(allocator, imported_files);

    for (imported_files) |rel| {
        const full_path = try std.fs.path.join(allocator, &.{ corpus_imported_examples_root, rel });
        defer allocator.free(full_path);
        const source = try std.Io.Dir.cwd().readFileAlloc(io, full_path, allocator, .limited(std.math.maxInt(usize)));
        defer allocator.free(source);
        const outcome = try boon.parser.parseAlloc(allocator, source);
        switch (outcome) {
            .ok => |document| {
                var parsed = document;
                parsed.deinit();
            },
            .err => |failure| {
                blocked += 1;
                _ = failure;
            },
        }
    }

    for (planned_terminal_p0_examples) |name| {
        const full_path = try std.fmt.allocPrint(allocator, "examples/terminal/{s}/{s}.bn", .{ name, name });
        defer allocator.free(full_path);
        std.Io.Dir.cwd().access(io, full_path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        const source = try std.Io.Dir.cwd().readFileAlloc(io, full_path, allocator, .limited(std.math.maxInt(usize)));
        defer allocator.free(source);
        const outcome = try boon.parser.parseAlloc(allocator, source);
        switch (outcome) {
            .ok => |document| {
                var parsed = document;
                parsed.deinit();
            },
            .err => |failure| {
                blocked += 1;
                _ = failure;
            },
        }
    }

    return blocked;
}

fn collectRelativeFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
) ![][]u8 {
    var dir = try std.Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var paths: std.ArrayList([]u8) = .empty;
    errdefer freeOwnedStringSlice(allocator, paths.items);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        try paths.append(allocator, try allocator.dupe(u8, entry.path));
    }
    std.mem.sort([]u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
    return try paths.toOwnedSlice(allocator);
}

fn collectRelativeFilesWithSuffix(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
    suffix: []const u8,
) ![][]u8 {
    const all = try collectRelativeFiles(allocator, io, root_path);
    var filtered: std.ArrayList([]u8) = .empty;
    errdefer freeOwnedStringSlice(allocator, filtered.items);
    for (all) |path| {
        if (std.mem.endsWith(u8, path, suffix)) {
            try filtered.append(allocator, try allocator.dupe(u8, path));
        }
    }
    freeOwnedStringSlice(allocator, all);
    return try filtered.toOwnedSlice(allocator);
}

fn freeOwnedStringSlice(allocator: std.mem.Allocator, items: [][]u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

fn copyDirectoryTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    src_root: []const u8,
    dst_root: []const u8,
) !void {
    var src_dir = try std.Io.Dir.cwd().openDir(io, src_root, .{ .iterate = true });
    defer src_dir.close(io);

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    var cwd = std.Io.Dir.cwd();
    while (try walker.next(io)) |entry| {
        const dst_path = try std.fs.path.join(allocator, &.{ dst_root, entry.path });
        defer allocator.free(dst_path);
        switch (entry.kind) {
            .directory => try cwd.createDirPath(io, dst_path),
            .file => {
                if (std.fs.path.dirname(dst_path)) |parent| try cwd.createDirPath(io, parent);
                const src_path = try std.fs.path.join(allocator, &.{ src_root, entry.path });
                defer allocator.free(src_path);
                const source = try cwd.readFileAlloc(io, src_path, allocator, .limited(std.math.maxInt(usize)));
                defer allocator.free(source);
                try cwd.writeFile(io, .{ .sub_path = dst_path, .data = source });
            },
            else => {},
        }
    }
}

fn waitForBrowserServer(io: std.Io, port: u16) !void {
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", port);
    var attempt: usize = 0;
    while (attempt < 100) : (attempt += 1) {
        if (address.connect(io, .{ .mode = .stream })) |stream| {
            stream.close(io);
            return;
        } else |_| {
            try std.Io.sleep(io, .fromMilliseconds(100), .awake);
        }
    }
    return error.ServerDidNotStart;
}

fn parseImagemagickRmseSimilarity(text: []const u8) !f64 {
    const start = std.mem.indexOfScalar(u8, text, '(') orelse return error.InvalidCompareOutput;
    const end = std.mem.indexOfScalarPos(u8, text, start + 1, ')') orelse return error.InvalidCompareOutput;
    const normalized = try std.fmt.parseFloat(f64, std.mem.trim(u8, text[start + 1 .. end], " \t\r\n"));
    return 1.0 - normalized;
}

const compiled_cache_dir = ".zig-cache/boon-runtime";
const compiled_cache_schema = "compiled-v2";

fn compiledProgramForSource(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    source: []const u8,
) !boon.headless.CompileOutcome {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, compiled_cache_dir);

    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(compiled_cache_schema);
    hasher.update(boon.version);
    hasher.update(path);
    hasher.update(source);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    const cache_name = try std.fmt.allocPrint(allocator, "{s}/{x}.bin", .{ compiled_cache_dir, digest });
    defer allocator.free(cache_name);

    const cached_data = cwd.readFileAlloc(io, cache_name, allocator, .limited(std.math.maxInt(usize))) catch null;
    if (cached_data) |data| {
        defer allocator.free(data);
        var reader = std.Io.Reader.fixed(data);
        const program = boon.headless.deserializeCompiledProgramAlloc(allocator, &reader) catch |err| switch (err) {
            error.InvalidCacheFormat,
            error.EndOfStream,
            => null,
            else => return err,
        };
        if (program) |loaded| {
            return .{ .ok = loaded };
        }
    }

    const compiled = try boon.headless.compileAlloc(allocator, source);
    switch (compiled) {
        .ok => |program| {
            var encoded: std.Io.Writer.Allocating = .init(allocator);
            defer encoded.deinit();
            try boon.headless.serializeCompiledProgram(&encoded.writer, &program);
            cwd.writeFile(io, .{ .sub_path = cache_name, .data = encoded.written() }) catch {};
            return .{ .ok = program };
        },
        .err => |failure| return .{ .err = failure },
    }
}

fn runCompiledSource(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    source: []const u8,
    options: boon.headless.Options,
) !boon.headless.Outcome {
    const compiled_outcome = try compiledProgramForSource(allocator, io, path, source);
    return switch (compiled_outcome) {
        .ok => |program| try boon.headless.runCompiledAlloc(allocator, program, options),
        .err => |failure| .{ .err = failure },
    };
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

    const outcome = try runCompiledSource(allocator, io, args.path, source, .{
        .trace = args.trace,
        .virtual_time_ms = args.virtual_time_ms,
        .state_file_path = state_file_path,
        .clear_state = args.clear_state,
        .terminal_columns = 80,
        .terminal_rows = 24,
    });
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();

            if (args.script_path) |script_path| {
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

    const outcome = try runCompiledSource(allocator, io, args.path, source, .{
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

    const outcome = try runCompiledSource(allocator, io, args.path, source, .{
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

fn runVerifyExamples(
    allocator: std.mem.Allocator,
    io: std.Io,
    args: VerifyExamplesArgs,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    return switch (args.mode) {
        .headless => try verifyHeadlessCases(allocator, io, args.filter, stdout, stderr),
        .terminal_grid => try verifyTerminalGridCases(allocator, io, args.filter, stdout, stderr),
    };
}

fn verifyHeadlessCases(
    allocator: std.mem.Allocator,
    io: std.Io,
    filter: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var passed: usize = 0;
    var matched: usize = 0;

    for (headless_p0_cases) |case| {
        if (!verifyCaseMatches(filter, case.name)) continue;
        matched += 1;

        const render = runVerifiedHeadlessCase(allocator, io, case) catch |err| {
            try stderr.print("verify-examples failed\n- {s}: {t}\n", .{ case.name, err });
            return 1;
        };
        defer allocator.free(render);

        const ok = switch (case.expected) {
            .exact => |expected| std.mem.eql(u8, render, expected),
            .contains => |expected| std.mem.indexOf(u8, render, expected) != null,
        };
        if (!ok) {
            switch (case.expected) {
                .exact => |expected| try stderr.print(
                    "verify-examples failed\n- {s}: expected exact render {s}, got {s}\n",
                    .{ case.name, expected, render },
                ),
                .contains => |expected| try stderr.print(
                    "verify-examples failed\n- {s}: expected render containing {s}, got {s}\n",
                    .{ case.name, expected, render },
                ),
            }
            return 1;
        }

        passed += 1;
        try stdout.print("PASS {s}\n", .{case.name});
    }

    if (matched == 0) {
        try stderr.print("verify-examples failed\n- {s}: no headless case matched this filter\n", .{filter});
        return 1;
    }

    try stdout.print("verify-examples ok ({d} passed, 0 exact blockers recorded)\n", .{passed});
    return 0;
}

fn verifyTerminalGridCases(
    allocator: std.mem.Allocator,
    io: std.Io,
    filter: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var passed: usize = 0;
    var matched: usize = 0;

    for (terminal_grid_p0_cases) |case| {
        if (!verifyCaseMatches(filter, case.name)) continue;
        matched += 1;

        const snapshot = runVerifiedSnapshotCase(allocator, io, case) catch |err| {
            try stderr.print("verify-examples failed\n- {s}: {t}\n", .{ case.name, err });
            return 1;
        };
        defer allocator.free(snapshot);

        const trimmed_expected = std.mem.trimEnd(u8, case.expected_text, "\n");

        if (!std.mem.eql(u8, snapshot, trimmed_expected)) {
            try stderr.print(
                "verify-examples failed\n- {s}: snapshot mismatch\nexpected:\n{s}\n\ngot:\n{s}\n",
                .{ case.name, trimmed_expected, snapshot },
            );
            return 1;
        }

        passed += 1;
        try stdout.print("PASS {s}\n", .{case.name});
    }

    if (matched == 0) {
        try stderr.print("verify-examples failed\n- {s}: no terminal-grid case matched this filter\n", .{filter});
        return 1;
    }

    try stdout.print("verify-examples ok ({d} passed, 0 exact blockers recorded)\n", .{passed});
    return 0;
}

fn runVerifiedHeadlessCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    case: VerifyHeadlessCase,
) ![]u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, case.path, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(source);

    const outcome = try runCompiledSource(allocator, io, case.path, source, .{ .virtual_time_ms = case.virtual_time_ms });
    const session = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("verify case {s} failed to boot: {s}\n", .{ case.name, failure.message });
            return error.VerifyExampleBootFailed;
        },
    };
    var runtime = session;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(allocator);
    for (case.actions) |action| {
        try executeVerifyAction(allocator, &runtime, &input_state, action);
    }

    return try runtime.renderAlloc(allocator);
}

fn runVerifiedSnapshotCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    case: VerifySnapshotCase,
) ![]u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, case.path, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(source);

    const outcome = try runCompiledSource(allocator, io, case.path, source, .{ .virtual_time_ms = case.virtual_time_ms });
    const session = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("verify case {s} failed to boot: {s}\n", .{ case.name, failure.message });
            return error.VerifyExampleBootFailed;
        },
    };
    var runtime = session;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(allocator);
    for (case.actions) |action| {
        try executeVerifyAction(allocator, &runtime, &input_state, action);
    }

    return try runtime.snapshotAlloc(allocator);
}

fn executeVerifyAction(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    action: VerifyAction,
) !void {
    switch (action) {
        .click_button => |index| try runtime.clickButton(index),
        .press_key => |key| {
            _ = try dispatchHeadlessTerminalNamedKey(allocator, runtime, input_state, key);
        },
        .wait_ms => |milliseconds| try runtime.advanceTime(milliseconds),
        .mouse_move => |point| try dispatchHeadlessTerminalMouse(allocator, runtime, input_state, point.x, point.y, .move),
        .mouse_click => |point| try dispatchHeadlessTerminalMouse(allocator, runtime, input_state, point.x, point.y, .click),
        .mouse_double_click => |point| try dispatchHeadlessTerminalMouse(allocator, runtime, input_state, point.x, point.y, .double_click),
        .mouse_double_click_first_label => {
            const regions = (try runtime.terminalHitRegionsAlloc(allocator)) orelse return error.MissingTerminalHitRegions;
            defer allocator.free(regions);
            for (regions) |region| {
                if (region.label_double_click_index != null) {
                    try dispatchHeadlessTerminalMouse(allocator, runtime, input_state, region.x, region.y, .double_click);
                    return;
                }
            }
            return error.MissingTerminalHitRegions;
        },
    }
}

fn verifyCaseMatches(filter: []const u8, case_name: []const u8) bool {
    return std.mem.eql(u8, filter, "p0") or std.mem.eql(u8, filter, case_name);
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

    const outcome = try runCompiledSource(allocator, io, args.path, source, .{
        .trace = args.trace,
        .virtual_time_ms = args.virtual_time_ms,
        .terminal_columns = terminalViewport().width,
        .terminal_rows = terminalViewport().height,
    });
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();

            if (runtime.rootKind() != .terminal) return error.ExpectedTerminalRoot;

            if (args.script_path) |script_path| {
                try executeHeadlessScript(allocator, io, script_path, &runtime);
            }

            var raw_terminal = enableRawTerminal(io) catch |err| switch (err) {
                error.NotATerminal => null,
                else => return err,
            };
            if (raw_terminal) |*mode| {
                defer mode.restore(io) catch {};
                var input_state = TerminalInputState{};
                defer input_state.deinit(allocator);
                while (true) {
                    const contract = (try runtime.terminalContractView()) orelse return error.ExpectedTerminalRoot;
                    try renderTerminalDeclaredScreen(allocator, &runtime, stdout, contract, &input_state);
                    try normalizeTerminalInputState(allocator, &runtime, &input_state);
                    try promotePendingTerminalFocus(allocator, &runtime, &input_state);
                    const should_continue = handleTerminalDeclaredInput(allocator, args, &runtime, stdout, stderr, contract, &input_state) catch |err| blk: {
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
                \\run terminal fallback
                \\Type `help` for commands, `quit` to exit.
                \\
            );
            try stdout.flush();

            var input_state = TerminalInputState{};
            defer input_state.deinit(allocator);
            while (true) {
                const contract = (try runtime.terminalContractView()) orelse return error.ExpectedTerminalRoot;
                try renderTerminalDeclaredScreen(allocator, &runtime, stdout, contract, &input_state);
                try normalizeTerminalInputState(allocator, &runtime, &input_state);
                try promotePendingTerminalFocus(allocator, &runtime, &input_state);
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
                if (std.mem.startsWith(u8, line, "press ")) {
                    const key = std.mem.trim(u8, line["press ".len..], " \t");
                    if (key.len != 0) _ = try dispatchTerminalNamedKey(allocator, &runtime, contract, &input_state, key);
                    continue;
                }
                if (std.mem.eql(u8, line, "trace")) {
                    if (!args.trace) {
                        try stderr.writeAll("error: run was not started with --trace\n");
                        try stderr.flush();
                        continue;
                    }
                    const trace = try runtime.traceAlloc(allocator);
                    defer allocator.free(trace);
                    try stdout.print("{s}\n", .{trace});
                    try stdout.flush();
                    continue;
                }
                if (std.mem.eql(u8, line, "regions")) {
                    try writeTerminalRegions(allocator, &runtime, stdout);
                    try stdout.flush();
                    continue;
                }

                executeTerminalCommand(allocator, &runtime, &input_state, line) catch |err| {
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

fn renderTerminalDeclaredScreen(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
    contract: *const boon.headless.TerminalContract,
    input_state: *TerminalInputState,
) !void {
    _ = contract;
    try stdout.writeAll("\x1b[2J\x1b[H");
    const snapshot = try runtime.snapshotAlloc(allocator);
    defer allocator.free(snapshot);
    const viewport = terminalViewport();
    input_state.viewport_width = viewport.width;
    input_state.viewport_height = viewport.height;
    try clampTerminalViewport(input_state, snapshot);
    try writeTerminalViewport(stdout, snapshot, input_state);
    try positionTerminalCursorForFocusedInput(allocator, runtime, stdout, input_state);
    try stdout.flush();
}

const TerminalInputState = struct {
    focused_text_input: ?usize = null,
    focused_text_input_cursor: usize = 0,
    focused_text_input_value: std.ArrayList(u8) = .empty,
    focused_text_input_ref: ?boon.headless.TextInputSessionRef = null,
    pending_focus_promote: bool = false,
    hovered_indices: std.ArrayList(usize) = .empty,
    last_mouse_click: ?TerminalMouseClick = null,
    view_x: usize = 0,
    view_y: usize = 0,
    viewport_width: usize = 80,
    viewport_height: usize = 24,
    content_width: usize = 0,
    content_height: usize = 0,

    fn deinit(self: *TerminalInputState, allocator: std.mem.Allocator) void {
        self.focused_text_input_value.deinit(allocator);
        self.hovered_indices.deinit(allocator);
    }
};

const TerminalMouseClick = struct {
    button_index: ?usize = null,
    label_double_click_index: ?usize = null,
    x: usize,
    y: usize,
    at_ms: i64,
};

const TerminalMouseButton = enum {
    left,
    middle,
    right,
    release,
    wheel_up,
    wheel_down,
    other,
};

const TerminalViewport = struct {
    width: usize,
    height: usize,
};

const ParsedMouseEvent = struct {
    x: usize,
    y: usize,
    button: TerminalMouseButton,
    is_motion: bool,
};

fn handleTerminalDeclaredInput(
    allocator: std.mem.Allocator,
    args: TerminalArgs,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    contract: *const boon.headless.TerminalContract,
    input_state: *TerminalInputState,
) !bool {
    try normalizeTerminalInputState(allocator, runtime, input_state);

    if (contract.loop) |loop| {
        var fds = [_]std.posix.pollfd{.{
            .fd = std.posix.STDIN_FILENO,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const timeout_ms: i32 = if (loop.while_active) @intCast(@min(loop.every_ms, @as(u64, std.math.maxInt(i32)))) else -1;
        const ready = try std.posix.poll(&fds, timeout_ms);
        if (ready == 0) {
            if (loop.while_active) try runtime.triggerLinkWithScope(loop.pulse_link, loop.scope);
            return true;
        }
    }

    var byte: [1]u8 = undefined;
    const amount = try std.posix.read(std.posix.STDIN_FILENO, &byte);
    if (amount == 0) return false;

    switch (byte[0]) {
        0x03 => return false,
        0x07 => {
            try writeDeclaredTerminalHelp(stdout, contract);
            try stdout.flush();
            return true;
        },
        0x14 => {
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
            if (std.mem.startsWith(u8, command, "press ")) {
                const key = std.mem.trim(u8, command["press ".len..], " \t");
                if (key.len != 0) _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, key);
                return true;
            }
            if (std.mem.eql(u8, command, "trace")) {
                if (!args.trace) {
                    try stderr.writeAll("error: run was not started with --trace\n");
                    try stderr.flush();
                    return true;
                }
                const trace = try runtime.traceAlloc(allocator);
                defer allocator.free(trace);
                try stdout.print("\n{s}\n", .{trace});
                try stdout.flush();
                return true;
            }
            if (std.mem.eql(u8, command, "regions")) {
                try stdout.writeByte('\n');
                try writeTerminalRegions(allocator, runtime, stdout);
                try stdout.flush();
                return true;
            }
            executeTerminalCommand(allocator, runtime, input_state, command) catch |err| {
                try stderr.print("error: {s}\n", .{@errorName(err)});
                try stderr.flush();
            };
            return true;
        },
        '\r', '\n' => {
            _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Enter");
            return true;
        },
        ' ' => {
            _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Space");
            return true;
        },
        '\t' => {
            if (try cycleTerminalTextInputFocus(allocator, runtime, input_state, false)) return true;
            _ = try dispatchTerminalKey(runtime, contract, "Tab");
            return true;
        },
        0x7f, 0x08 => {
            _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Backspace");
            return true;
        },
        0x1b => return try handleDeclaredTerminalEscapeSequence(allocator, runtime, contract, input_state),
        else => {
            if (byte[0] >= 0x20 and byte[0] < 0x7f) {
                const key = [_]u8{byte[0]};
                _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, &key);
                return true;
            }
            return true;
        },
    }
}

fn handleDeclaredTerminalEscapeSequence(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    contract: *const boon.headless.TerminalContract,
    input_state: *TerminalInputState,
) !bool {
    const first = try readRequiredTerminalByte();
    if (first != '[') {
        _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Escape");
        return true;
    }

    const second = try readRequiredTerminalByte();
    if (second == '<') {
        const maybe_event = try parseSgrMouseEvent();
        if (maybe_event) |event| {
            try handleTerminalMouseEvent(allocator, runtime, input_state, event);
        }
        return true;
    }
    if (second >= '0' and second <= '9') {
        return try handleDeclaredTerminalCsiNumber(allocator, runtime, contract, input_state, second);
    }

    switch (second) {
        'A' => _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Up"),
        'B' => _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Down"),
        'C' => _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Right"),
        'D' => _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Left"),
        'Z' => {
            if (!try cycleTerminalTextInputFocus(allocator, runtime, input_state, true)) {
                _ = try dispatchTerminalKey(runtime, contract, "Shift+Tab");
            }
        },
        else => _ = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, "Escape"),
    }
    return true;
}

fn handleDeclaredTerminalCsiNumber(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    contract: *const boon.headless.TerminalContract,
    input_state: *TerminalInputState,
    first_digit: u8,
) !bool {
    _ = allocator;
    var digits_buf: [8]u8 = undefined;
    digits_buf[0] = first_digit;
    var len: usize = 1;
    while (len < digits_buf.len) {
        const byte = try readRequiredTerminalByte();
        if (byte == '~') break;
        if (byte < '0' or byte > '9') return true;
        digits_buf[len] = byte;
        len += 1;
    }
    const code = std.fmt.parseInt(u8, digits_buf[0..len], 10) catch return true;
    switch (code) {
        5 => scrollTerminalViewport(input_state, -10),
        6 => scrollTerminalViewport(input_state, 10),
        else => {
            if (input_state.focused_text_input) |index| {
                const key = switch (code) {
                    5 => "PageUp",
                    6 => "PageDown",
                    else => null,
                };
                if (key) |resolved| try runtime.pressTextInputKey(index, resolved);
            } else {
                const key = switch (code) {
                    5 => "PageUp",
                    6 => "PageDown",
                    else => null,
                };
                if (key) |resolved| _ = try dispatchTerminalKey(runtime, contract, resolved);
            }
        },
    }
    return true;
}

fn readRequiredTerminalByte() !u8 {
    var byte: [1]u8 = undefined;
    const amount = try std.posix.read(std.posix.STDIN_FILENO, &byte);
    if (amount == 0) return error.EndOfStream;
    return byte[0];
}

fn parseSgrMouseEvent() !?ParsedMouseEvent {
    var buffer: [32]u8 = undefined;
    var len: usize = 0;
    while (len < buffer.len) {
        const byte = try readRequiredTerminalByte();
        buffer[len] = byte;
        len += 1;
        if (byte == 'M' or byte == 'm') break;
    }
    if (len == 0) return null;

    const final = buffer[len - 1];
    if (final != 'M' and final != 'm') return null;
    const payload = buffer[0 .. len - 1];
    var parts = std.mem.tokenizeScalar(u8, payload, ';');
    const cb_text = parts.next() orelse return null;
    const cx_text = parts.next() orelse return null;
    const cy_text = parts.next() orelse return null;
    const cb = std.fmt.parseInt(u16, cb_text, 10) catch return null;
    const cx_1 = std.fmt.parseInt(usize, cx_text, 10) catch return null;
    const cy_1 = std.fmt.parseInt(usize, cy_text, 10) catch return null;

    const base = cb & 0b11;
    const is_motion = (cb & 0b100000) != 0;
    const button: TerminalMouseButton = if (final == 'm')
        .release
    else if ((cb & 0b1000000) != 0)
        if ((cb & 0b1) == 0) .wheel_up else .wheel_down
    else switch (base) {
        0 => .left,
        1 => .middle,
        2 => .right,
        3 => .release,
        else => .other,
    };

    return .{
        .x = if (cx_1 == 0) 0 else cx_1 - 1,
        .y = if (cy_1 == 0) 0 else cy_1 - 1,
        .button = button,
        .is_motion = is_motion,
    };
}

fn handleTerminalMouseEvent(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    event: ParsedMouseEvent,
) !void {
    switch (event.button) {
        .wheel_up => {
            scrollTerminalViewport(input_state, -3);
            return;
        },
        .wheel_down => {
            scrollTerminalViewport(input_state, 3);
            return;
        },
        else => {},
    }

    const regions = (try runtime.terminalHitRegionsView()) orelse return;

    const absolute_x = event.x + input_state.view_x;
    const absolute_y = event.y + input_state.view_y;

    var hovered_now: std.ArrayList(usize) = .empty;
    defer hovered_now.deinit(allocator);

    var clicked_button: ?usize = null;
    var clicked_label_double_click: ?usize = null;
    var clicked_text_input: ?usize = null;

    for (regions) |region| {
        if (!region.contains(absolute_x, absolute_y)) continue;
        if (region.hover_index) |hover_index| {
            if (!containsIndex(hovered_now.items, hover_index)) try hovered_now.append(allocator, hover_index);
        }
        if (clicked_button == null and region.button_index != null) clicked_button = region.button_index;
        if (clicked_label_double_click == null and region.label_double_click_index != null) clicked_label_double_click = region.label_double_click_index;
        if (clicked_text_input == null and region.text_input_index != null) clicked_text_input = region.text_input_index;
    }

    try reconcileHoveredRegions(allocator, runtime, input_state, hovered_now.items);

    if (event.is_motion) return;

    switch (event.button) {
        .left, .release => {
            if (clicked_text_input) |text_input_index| {
                try setTerminalTextInputFocus(allocator, runtime, input_state, text_input_index);
            } else if (input_state.focused_text_input != null) {
                try setTerminalTextInputFocus(allocator, runtime, input_state, null);
            }

            if (event.button == .release) {
                if (clicked_button) |button_index| try runtime.clickButton(button_index);
                if (clicked_label_double_click) |label_index| {
                    const now_ms = currentMonotonicMs();
                    if (input_state.last_mouse_click) |last| {
                        if (last.label_double_click_index == label_index and now_ms - last.at_ms <= 400) {
                            try runtime.doubleClickLabel(label_index);
                            try focusPromotedTextInput(allocator, runtime, input_state, absolute_x, absolute_y);
                            input_state.last_mouse_click = null;
                            return;
                        }
                    }
                    input_state.last_mouse_click = .{
                        .button_index = clicked_button,
                        .label_double_click_index = label_index,
                        .x = absolute_x,
                        .y = absolute_y,
                        .at_ms = now_ms,
                    };
                    return;
                }
                if (clicked_button != null) {
                    input_state.last_mouse_click = .{
                        .button_index = clicked_button,
                        .label_double_click_index = null,
                        .x = absolute_x,
                        .y = absolute_y,
                        .at_ms = currentMonotonicMs(),
                    };
                } else {
                    input_state.last_mouse_click = null;
                }
            }
        },
        else => {},
    }
}

fn reconcileHoveredRegions(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    next_hovered: []const usize,
) !void {
    for (input_state.hovered_indices.items) |index| {
        if (!containsIndex(next_hovered, index)) try runtime.setHover(index, false);
    }
    for (next_hovered) |index| {
        if (!containsIndex(input_state.hovered_indices.items, index)) try runtime.setHover(index, true);
    }
    try input_state.hovered_indices.resize(allocator, 0);
    try input_state.hovered_indices.appendSlice(allocator, next_hovered);
}

fn containsIndex(items: []const usize, needle: usize) bool {
    for (items) |item| {
        if (item == needle) return true;
    }
    return false;
}

fn terminalViewport() TerminalViewport {
    if (builtin.os.tag == .linux) {
        var wsz: std.posix.winsize = .{ .row = 24, .col = 80, .xpixel = 0, .ypixel = 0 };
        const rc = std.os.linux.ioctl(std.posix.STDOUT_FILENO, std.os.linux.T.IOCGWINSZ, @intFromPtr(&wsz));
        if (std.posix.errno(rc) == .SUCCESS) {
            return .{
                .width = @max(@as(usize, wsz.col), 1),
                .height = @max(@as(usize, wsz.row), 1),
            };
        }
    }
    return .{ .width = 80, .height = 24 };
}

fn clampTerminalViewport(input_state: *TerminalInputState, snapshot: []const u8) !void {
    var lines = std.mem.splitScalar(u8, snapshot, '\n');
    var content_height: usize = 0;
    var content_width: usize = 0;
    while (lines.next()) |line| {
        content_height += 1;
        content_width = @max(content_width, line.len);
    }
    input_state.content_width = content_width;
    input_state.content_height = content_height;

    const visible_height = @max(input_state.viewport_height, 1);
    const visible_width = @max(input_state.viewport_width, 1);
    const max_y = if (content_height > visible_height) content_height - visible_height else 0;
    const max_x = if (content_width > visible_width) content_width - visible_width else 0;
    if (input_state.view_y > max_y) input_state.view_y = max_y;
    if (input_state.view_x > max_x) input_state.view_x = max_x;
}

fn writeTerminalViewport(stdout: *std.Io.Writer, snapshot: []const u8, input_state: *const TerminalInputState) !void {
    var lines = std.mem.splitScalar(u8, snapshot, '\n');
    var row_index: usize = 0;
    var printed_rows: usize = 0;
    const colorize_cells = std.mem.startsWith(u8, snapshot, "Cells\nArrows or click move selection");
    while (lines.next()) |line| {
        if (row_index < input_state.view_y) {
            row_index += 1;
            continue;
        }
        if (printed_rows >= input_state.viewport_height) break;
        const start = @min(input_state.view_x, line.len);
        const end = @min(line.len, input_state.view_x + input_state.viewport_width);
        const visible_line = line[start..end];
        if (colorize_cells) {
            try writeColoredCellsViewportLine(stdout, visible_line, row_index);
        } else {
            try stdout.writeAll(visible_line);
        }
        printed_rows += 1;
        row_index += 1;
        if (printed_rows < input_state.viewport_height) try stdout.writeAll("\r\n");
    }
}

fn writeColoredCellsViewportLine(stdout: *std.Io.Writer, line: []const u8, row_index: usize) !void {
    switch (row_index) {
        0 => {
            try stdout.writeAll("\x1b[1;38;5;42m");
            try stdout.writeAll(line);
            try stdout.writeAll("\x1b[0m");
            return;
        },
        1 => {
            try stdout.writeAll("\x1b[2;38;5;245m");
            try stdout.writeAll(line);
            try stdout.writeAll("\x1b[0m");
            return;
        },
        2 => {
            try stdout.writeAll("\x1b[1;38;5;81m");
            try stdout.writeAll(line);
            try stdout.writeAll("\x1b[0m");
            return;
        },
        3 => {
            try stdout.writeAll("\x1b[38;5;16;48;5;252m");
            try stdout.writeAll(line);
            try stdout.writeAll("\x1b[0m");
            return;
        },
        else => {},
    }

    for (line) |char| {
        switch (char) {
            '|' => try stdout.writeAll("\x1b[38;5;244m|\x1b[0m"),
            '[' => try stdout.writeAll("\x1b[1;38;5;220m[\x1b[0m"),
            ']' => try stdout.writeAll("\x1b[1;38;5;220m]\x1b[0m"),
            '<' => try stdout.writeAll("\x1b[1;38;5;51m<\x1b[0m"),
            '>' => try stdout.writeAll("\x1b[1;38;5;51m>\x1b[0m"),
            '*' => try stdout.writeAll("\x1b[1;38;5;51m*\x1b[0m"),
            else => try stdout.writeByte(char),
        }
    }
}

fn positionTerminalCursorForFocusedInput(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
    input_state: *const TerminalInputState,
) !void {
    _ = allocator;
    if (input_state.focused_text_input) |index| {
        const regions = (try runtime.terminalHitRegionsView()) orelse {
            try stdout.writeAll("\x1b[?25l");
            return;
        };
        var region_match: ?boon.headless.TerminalHitRegion = null;
        for (regions) |region| {
            if (region.text_input_index == index) {
                region_match = region;
                break;
            }
        }
        const region = region_match orelse {
            try stdout.writeAll("\x1b[?25l");
            return;
        };

        const current = input_state.focused_text_input_value.items;

        const logical_x = region.x + 1 + @min(input_state.focused_text_input_cursor, current.len);
        const logical_y = region.y;
        const visible_width = @max(input_state.viewport_width, 1);
        const visible_height = @max(input_state.viewport_height, 1);

        if (logical_x < input_state.view_x or logical_x >= input_state.view_x + visible_width) {
            try stdout.writeAll("\x1b[?25l");
            return;
        }
        if (logical_y < input_state.view_y or logical_y >= input_state.view_y + visible_height) {
            try stdout.writeAll("\x1b[?25l");
            return;
        }

        const screen_x = logical_x - input_state.view_x + 1;
        const screen_y = logical_y - input_state.view_y + 1;
        try stdout.writeAll("\x1b[?25h");
        try stdout.print("\x1b[{d};{d}H", .{ screen_y, screen_x });
        return;
    }
    try stdout.writeAll("\x1b[?25l");
}

fn dispatchTerminalTestKey(
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    key: []const u8,
) !void {
    _ = try dispatchTerminalNamedKey(std.testing.allocator, runtime, null, input_state, key);
}

fn openFocusedCellForEdit(
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
) !void {
    try dispatchTerminalTestKey(runtime, input_state, "Enter");
    try promotePendingTerminalFocus(std.testing.allocator, runtime, input_state);
}

fn replaceFocusedCellText(
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    text: []const u8,
) !void {
    try openFocusedCellForEdit(runtime, input_state);
    try runtime.setFirstTextInputValue(std.testing.allocator, text);
    try dispatchTerminalTestKey(runtime, input_state, "Enter");
}

fn scrollTerminalViewport(input_state: *TerminalInputState, delta_rows: isize) void {
    const max_y = if (input_state.content_height > input_state.viewport_height) input_state.content_height - input_state.viewport_height else 0;
    if (delta_rows < 0) {
        const amount: usize = @intCast(-delta_rows);
        input_state.view_y = if (amount > input_state.view_y) 0 else input_state.view_y - amount;
    } else {
        input_state.view_y = @min(max_y, input_state.view_y + @as(usize, @intCast(delta_rows)));
    }
}

fn focusPromotedTextInput(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    absolute_x: ?usize,
    absolute_y: ?usize,
) !void {
    if (try runtime.terminalHitRegionsView()) |regions| {
        if (absolute_x != null and absolute_y != null) {
            for (regions) |region| {
                if (region.text_input_index) |text_input_index| {
                    if (region.contains(absolute_x.?, absolute_y.?)) {
                        try setTerminalTextInputFocus(allocator, runtime, input_state, text_input_index);
                        return;
                    }
                }
            }
        }
    }

    const text_input_count = try runtime.textInputCountAlloc(allocator);
    if (text_input_count == 1) {
        try setTerminalTextInputFocus(allocator, runtime, input_state, 0);
    }
}

fn promotePendingTerminalFocus(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
) !void {
    if (!input_state.pending_focus_promote) return;
    if (input_state.focused_text_input != null) {
        input_state.pending_focus_promote = false;
        return;
    }
    try focusPromotedTextInput(allocator, runtime, input_state, null, null);
    input_state.pending_focus_promote = false;
}

fn currentMonotonicMs() i64 {
    var timespec: std.posix.timespec = undefined;
    switch (std.posix.errno(std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &timespec))) {
        .SUCCESS => {
            const seconds_ms: i64 = @intCast(timespec.sec * std.time.ms_per_s);
            const nanos_ms: i64 = @intCast(@divTrunc(timespec.nsec, std.time.ns_per_ms));
            return seconds_ms + nanos_ms;
        },
        else => return 0,
    }
}

fn dispatchTerminalKey(
    runtime: *boon.headless.Session,
    contract: *const boon.headless.TerminalContract,
    key: []const u8,
) !bool {
    for (contract.keyboard_bindings) |binding| {
        if (!binding.when) continue;
        for (binding.keys) |candidate| {
            if (std.mem.eql(u8, candidate, key)) {
                try runtime.triggerLinkWithScope(binding.link, binding.scope);
                return true;
            }
        }
    }
    return false;
}

fn dispatchTerminalNamedKey(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    contract: *const boon.headless.TerminalContract,
    input_state: *TerminalInputState,
    key: []const u8,
) !bool {
    try normalizeTerminalInputState(allocator, runtime, input_state);

    if (std.mem.eql(u8, key, "Tab")) {
        if (try cycleTerminalTextInputFocus(allocator, runtime, input_state, false)) return true;
        return try dispatchTerminalKey(runtime, contract, "Tab");
    }
    if (std.mem.eql(u8, key, "Shift+Tab")) {
        if (try cycleTerminalTextInputFocus(allocator, runtime, input_state, true)) return true;
        return try dispatchTerminalKey(runtime, contract, "Shift+Tab");
    }

    if (input_state.focused_text_input) |index| {
        if (std.mem.eql(u8, key, "Space")) {
            try appendTerminalTextInputChar(allocator, runtime, input_state, index, ' ');
            return true;
        }
        if (std.mem.eql(u8, key, "Backspace")) {
            try backspaceTerminalTextInput(allocator, runtime, input_state, index);
            return true;
        }
        if (std.mem.eql(u8, key, "Left")) {
            if (input_state.focused_text_input_cursor > 0) input_state.focused_text_input_cursor -= 1;
            return true;
        }
        if (std.mem.eql(u8, key, "Right")) {
            const current = input_state.focused_text_input_value.items;
            if (input_state.focused_text_input_cursor < current.len) input_state.focused_text_input_cursor += 1;
            return true;
        }
        if (std.mem.eql(u8, key, "Enter") or std.mem.eql(u8, key, "Escape") or std.mem.eql(u8, key, "Up") or std.mem.eql(u8, key, "Down")) {
            try runtime.pressTextInputKey(index, key);
            try normalizeTerminalInputState(allocator, runtime, input_state);
            try promotePendingTerminalFocus(allocator, runtime, input_state);
            return true;
        }
        if (key.len == 1 and key[0] >= 0x20 and key[0] < 0x7f) {
            try appendTerminalTextInputChar(allocator, runtime, input_state, index, key[0]);
            return true;
        }
    }

    const focus_before_binding = input_state.focused_text_input;
    const dispatched = blk: {
        if (std.mem.eql(u8, key, "Space")) break :blk try dispatchTerminalKey(runtime, contract, "Space");
        if (std.mem.eql(u8, key, "Enter")) break :blk try dispatchTerminalKey(runtime, contract, "Enter");
        if (std.mem.eql(u8, key, "Escape")) break :blk try dispatchTerminalKey(runtime, contract, "Escape");
        if (std.mem.eql(u8, key, "Up")) break :blk try dispatchTerminalKey(runtime, contract, "Up");
        if (std.mem.eql(u8, key, "Down")) break :blk try dispatchTerminalKey(runtime, contract, "Down");
        if (std.mem.eql(u8, key, "Left")) break :blk try dispatchTerminalKey(runtime, contract, "Left");
        if (std.mem.eql(u8, key, "Right")) break :blk try dispatchTerminalKey(runtime, contract, "Right");
        break :blk try dispatchTerminalKey(runtime, contract, key);
    };

    if (dispatched and focus_before_binding == null and input_state.focused_text_input == null) {
        input_state.pending_focus_promote = (try runtime.textInputCountAlloc(allocator)) == 1;
    }

    return dispatched;
}

fn dispatchHeadlessTerminalKey(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    key: []const u8,
) !bool {
    _ = allocator;
    const contract = (try runtime.terminalContractView()) orelse return false;
    return try dispatchTerminalKey(runtime, contract, key);
}

fn dispatchHeadlessTerminalNamedKey(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    key: []const u8,
) !bool {
    const needs_pre_promote = input_state.pending_focus_promote and
        (key.len == 1 or
            std.mem.eql(u8, key, "Space") or
            std.mem.eql(u8, key, "Backspace") or
            std.mem.eql(u8, key, "Left") or
            std.mem.eql(u8, key, "Right") or
            std.mem.eql(u8, key, "Enter") or
            std.mem.eql(u8, key, "Escape") or
            std.mem.eql(u8, key, "Up") or
            std.mem.eql(u8, key, "Down"));
    if (needs_pre_promote) {
        try normalizeTerminalInputState(allocator, runtime, input_state);
        try promotePendingTerminalFocus(allocator, runtime, input_state);
    }

    const contract = (try runtime.terminalContractView()) orelse return false;
    const dispatched = try dispatchTerminalNamedKey(allocator, runtime, contract, input_state, key);

    const needs_post_reconcile = input_state.focused_text_input != null or
        input_state.hovered_indices.items.len != 0 or
        std.mem.eql(u8, key, "Enter") or
        std.mem.eql(u8, key, "Tab") or
        std.mem.eql(u8, key, "Shift+Tab") or
        std.mem.eql(u8, key, "Escape");
    if (needs_post_reconcile) {
        try normalizeTerminalInputState(allocator, runtime, input_state);
        try promotePendingTerminalFocus(allocator, runtime, input_state);
    }
    return dispatched;
}

const HeadlessMouseAction = enum {
    move,
    click,
    double_click,
};

fn dispatchHeadlessTerminalMouse(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    x: usize,
    y: usize,
    action: HeadlessMouseAction,
) !void {
    switch (action) {
        .move => try handleTerminalMouseEvent(allocator, runtime, input_state, .{
            .x = x,
            .y = y,
            .button = .left,
            .is_motion = true,
        }),
        .click => try handleTerminalMouseEvent(allocator, runtime, input_state, .{
            .x = x,
            .y = y,
            .button = .release,
            .is_motion = false,
        }),
        .double_click => {
            if (try runtime.terminalHitRegionsView()) |regions| {
                const absolute_x = x + input_state.view_x;
                const absolute_y = y + input_state.view_y;
                for (regions) |region| {
                    if (!region.contains(absolute_x, absolute_y)) continue;
                    if (region.label_double_click_index) |label_index| {
                        try runtime.doubleClickLabel(label_index);
                        try focusPromotedTextInput(allocator, runtime, input_state, absolute_x, absolute_y);
                        return;
                    }
                }
            }
            try handleTerminalMouseEvent(allocator, runtime, input_state, .{
                .x = x,
                .y = y,
                .button = .release,
                .is_motion = false,
            });
            try handleTerminalMouseEvent(allocator, runtime, input_state, .{
                .x = x,
                .y = y,
                .button = .release,
                .is_motion = false,
            });
        },
    }
}

fn writeDeclaredTerminalHelp(stdout: *std.Io.Writer, contract: *const boon.headless.TerminalContract) !void {
    try stdout.writeAll(
        \\terminal shortcuts:
        \\  Ctrl+C         quit
        \\  Ctrl+G         show this help
        \\  Ctrl+T         open the debug command prompt
        \\  PageUp/Down    scroll oversized terminal apps
        \\mouse:
        \\  move           updates hovered elements
        \\  wheel          scrolls oversized terminal apps
        \\  left click     clicks buttons and focuses text inputs
        \\  double click   triggers label double-click handlers
        \\
    );
    if (contract.keyboard_bindings.len == 0) return;
    try stdout.writeAll("app bindings:\n");
    for (contract.keyboard_bindings) |binding| {
        if (!binding.when) continue;
        try stdout.writeAll("  ");
        for (binding.keys, 0..) |key, index| {
            if (index != 0) try stdout.writeAll("/");
            try stdout.writeAll(key);
        }
        if (binding.label) |label| {
            try stdout.writeByte(' ');
            try stdout.writeAll(label);
        }
        try stdout.writeByte('\n');
    }
}

fn normalizeTerminalInputState(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
) !void {
    if (input_state.focused_text_input == null and input_state.hovered_indices.items.len == 0) return;
    if (input_state.focused_text_input) |index| {
        if (index >= try runtime.textInputCountAlloc(allocator)) {
            input_state.focused_text_input = null;
            input_state.focused_text_input_ref = null;
            input_state.focused_text_input_cursor = 0;
            try input_state.focused_text_input_value.resize(allocator, 0);
        }
    }
    if (try runtime.terminalHitRegionsView()) |regions| {
        var valid_hovers: std.ArrayList(usize) = .empty;
        defer valid_hovers.deinit(allocator);
        for (regions) |region| {
            if (region.hover_index) |hover_index| {
                if (!containsIndex(valid_hovers.items, hover_index)) try valid_hovers.append(allocator, hover_index);
            }
        }
        var cursor: usize = 0;
        while (cursor < input_state.hovered_indices.items.len) {
            const hover_index = input_state.hovered_indices.items[cursor];
            if (containsIndex(valid_hovers.items, hover_index)) {
                cursor += 1;
                continue;
            }
            try runtime.setHover(hover_index, false);
            _ = input_state.hovered_indices.orderedRemove(cursor);
        }
    } else {
        for (input_state.hovered_indices.items) |hover_index| {
            try runtime.setHover(hover_index, false);
        }
        try input_state.hovered_indices.resize(allocator, 0);
    }
}

fn setTerminalTextInputFocus(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    next_focus: ?usize,
) !void {
    const count = try runtime.textInputCountAlloc(allocator);
    if (input_state.focused_text_input) |current| {
        if (current < count and (next_focus == null or next_focus.? != current)) {
            runtime.blurTextInput(current) catch |err| switch (err) {
                error.InvalidTextInputIndex => {},
                else => return err,
            };
        }
    }
    if (next_focus) |index| {
        if (index >= count) return;
        if (input_state.focused_text_input == null or input_state.focused_text_input.? != index) {
            runtime.focusTextInput(index) catch |err| switch (err) {
                error.InvalidTextInputIndex => {},
                else => return err,
            };
        }
        const current = try runtime.textInputTextView(index);
        try input_state.focused_text_input_value.resize(allocator, 0);
        try input_state.focused_text_input_value.appendSlice(allocator, current);
        input_state.focused_text_input_cursor = current.len;
        input_state.focused_text_input_ref = null;
    } else {
        input_state.focused_text_input_cursor = 0;
        input_state.focused_text_input_ref = null;
        try input_state.focused_text_input_value.resize(allocator, 0);
    }
    input_state.focused_text_input = next_focus;
}

fn cycleTerminalTextInputFocus(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    backward: bool,
) !bool {
    const count = try runtime.textInputCountAlloc(allocator);
    if (count == 0) return false;
    const next_index = if (input_state.focused_text_input) |current|
        if (backward)
            if (current == 0) count - 1 else current - 1
        else if (current + 1 >= count)
            0
        else
            current + 1
    else if (backward)
        count - 1
    else
        0;
    try setTerminalTextInputFocus(allocator, runtime, input_state, next_index);
    return true;
}

fn appendTerminalTextInputChar(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    index: usize,
    byte: u8,
) !void {
    var next: std.ArrayList(u8) = .empty;
    defer next.deinit(allocator);
    const current = input_state.focused_text_input_value.items;
    const cursor = @min(input_state.focused_text_input_cursor, current.len);
    try next.appendSlice(allocator, current[0..cursor]);
    try next.append(allocator, byte);
    try next.appendSlice(allocator, current[cursor..]);
    const text = try next.toOwnedSlice(allocator);
    defer allocator.free(text);
    try runtime.setTextInputValue(index, text);
    try input_state.focused_text_input_value.resize(allocator, 0);
    try input_state.focused_text_input_value.appendSlice(allocator, text);
    input_state.focused_text_input_cursor = cursor + 1;
}

fn backspaceTerminalTextInput(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    index: usize,
) !void {
    const current = input_state.focused_text_input_value.items;
    const cursor = @min(input_state.focused_text_input_cursor, current.len);
    if (cursor == 0) return;
    var next: std.ArrayList(u8) = .empty;
    defer next.deinit(allocator);
    try next.appendSlice(allocator, current[0 .. cursor - 1]);
    try next.appendSlice(allocator, current[cursor..]);
    const text = try next.toOwnedSlice(allocator);
    defer allocator.free(text);
    try runtime.setTextInputValue(index, text);
    try input_state.focused_text_input_value.resize(allocator, 0);
    try input_state.focused_text_input_value.appendSlice(allocator, text);
    input_state.focused_text_input_cursor = cursor - 1;
}

const RawTerminal = struct {
    original: std.posix.termios,

    fn restore(self: *const RawTerminal, io: std.Io) !void {
        uninstallRawTerminalCrashGuard();
        try std.Io.File.stdout().writeStreamingAll(io, "\x1b[?25h\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l");
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.original);
    }
};

const raw_terminal_guard_signals = [_]std.posix.SIG{ .SEGV, .BUS, .ILL, .ABRT, .FPE };
var raw_terminal_guard_active = false;
var raw_terminal_guard_original: std.posix.termios = undefined;
var raw_terminal_guard_previous: [raw_terminal_guard_signals.len]std.posix.Sigaction = undefined;

fn installRawTerminalCrashGuard(original: std.posix.termios) void {
    if (comptime std.posix.Sigaction == void) return;

    raw_terminal_guard_original = original;
    for (raw_terminal_guard_signals, 0..) |sig, index| {
        const act: std.posix.Sigaction = .{
            .handler = .{ .handler = rawTerminalCrashHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(sig, &act, &raw_terminal_guard_previous[index]);
    }
    raw_terminal_guard_active = true;
}

fn uninstallRawTerminalCrashGuard() void {
    if (!raw_terminal_guard_active) return;
    if (comptime std.posix.Sigaction == void) {
        raw_terminal_guard_active = false;
        return;
    }
    for (raw_terminal_guard_signals, 0..) |sig, index| {
        std.posix.sigaction(sig, &raw_terminal_guard_previous[index], null);
    }
    raw_terminal_guard_active = false;
}

fn rawTerminalCrashWriteAll(text: []const u8) void {
    var written: usize = 0;
    while (written < text.len) {
        const rc = std.posix.system.write(std.posix.STDOUT_FILENO, text[written..].ptr, text.len - written);
        switch (std.posix.errno(rc)) {
            .SUCCESS => written += @intCast(rc),
            .INTR => continue,
            else => return,
        }
    }
}

fn rawTerminalCrashHandler(sig: std.posix.SIG) callconv(.c) void {
    if (raw_terminal_guard_active) {
        rawTerminalCrashWriteAll("\x1b[?25h\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l");
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw_terminal_guard_original) catch {};
        raw_terminal_guard_active = false;
    }

    if (comptime std.posix.Sigaction != void) {
        const reset: std.posix.Sigaction = .{
            .handler = .{ .handler = std.posix.SIG.DFL },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(sig, &reset, null);
    }
    std.posix.raise(sig) catch {};
    std.process.exit(@intCast(128 + @intFromEnum(sig)));
}

fn enableRawTerminal(io: std.Io) !?RawTerminal {
    const original = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch |err| switch (err) {
        error.NotATerminal => return null,
        else => return err,
    };

    var raw = original;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.lflag.ISIG = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
    try std.Io.File.stdout().writeStreamingAll(io, "\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h");
    installRawTerminalCrashGuard(original);
    return .{ .original = original };
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

fn writeTerminalHelp(stdout: *std.Io.Writer) !void {
    try stdout.writeAll(
        \\commands:
        \\  render
        \\  controls
        \\  regions
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
        \\  mouse-move <x> <y>
        \\  mouse-click <x> <y>
        \\  mouse-double-click <x> <y>
        \\  focus <index>
        \\  focus-active
        \\  blur <index>
        \\  blur-active
        \\  wait <milliseconds>
        \\  quit
        \\
    );
}

fn writeTerminalRegions(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    stdout: *std.Io.Writer,
) !void {
    const maybe_regions = try runtime.terminalHitRegionsAlloc(allocator);
    const regions = maybe_regions orelse {
        try stdout.writeAll("no terminal regions\n");
        return;
    };
    defer allocator.free(regions);

    for (regions, 0..) |region, index| {
        try stdout.print(
            "{d}: x={d} y={d} w={d} h={d} click={?d} dblclick={?d} text={?d} hover={?d}\n",
            .{
                index,
                region.x,
                region.y,
                region.width,
                region.height,
                region.button_index,
                region.label_double_click_index,
                region.text_input_index,
                region.hover_index,
            },
        );
    }
}

fn executeTerminalCommand(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    line: []const u8,
) !void {
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
        try runtime.doubleClickLabel(index);
        try focusPromotedTextInput(allocator, runtime, input_state, null, null);
        return;
    }
    if (std.mem.eql(u8, command, "dblclick-label")) {
        const value = parts.rest();
        if (value.len == 0) return error.InvalidTerminalCommand;
        try runtime.doubleClickLabelByText(allocator, value);
        try focusPromotedTextInput(allocator, runtime, input_state, null, null);
        return;
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
    if (std.mem.eql(u8, command, "mouse-move")) {
        const x = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        const y = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        if (parts.next() != null) return error.InvalidTerminalCommand;
        return dispatchHeadlessTerminalMouse(allocator, runtime, input_state, x, y, .move);
    }
    if (std.mem.eql(u8, command, "mouse-click")) {
        const x = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        const y = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        if (parts.next() != null) return error.InvalidTerminalCommand;
        return dispatchHeadlessTerminalMouse(allocator, runtime, input_state, x, y, .click);
    }
    if (std.mem.eql(u8, command, "mouse-double-click")) {
        const x = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        const y = try parseTerminalIndex(parts.next() orelse return error.InvalidTerminalCommand);
        if (parts.next() != null) return error.InvalidTerminalCommand;
        return dispatchHeadlessTerminalMouse(allocator, runtime, input_state, x, y, .double_click);
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

    var input_state = TerminalInputState{};
    defer input_state.deinit(allocator);
    for (actions) |action| {
        try executeHeadlessScriptAction(allocator, runtime, &input_state, action);
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

test "headless press_key dispatches element-owned terminal bindings" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected pong cli terminal failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    try std.testing.expect(try dispatchHeadlessTerminalKey(std.testing.allocator, &runtime, "Enter"));

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Rally") != null);
}

test "compiled headless press_key dispatches pong terminal bindings with cli viewport options" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const compiled_outcome = try boon.headless.compileAlloc(std.testing.allocator, source);
    const compiled = switch (compiled_outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected compiled pong cli terminal failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    const outcome = try boon.headless.runCompiledAlloc(std.testing.allocator, compiled, .{
        .terminal_columns = 80,
        .terminal_rows = 24,
    });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected compiled pong cli runtime failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    try std.testing.expect(try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Enter"));

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Rally") != null);
}

test "executeHeadlessScriptAction applies press_key to terminal root" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected pong script failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const action = std.json.Value{
        .array = .{ .items = &.{
            std.json.Value{ .string = "press_key" },
            std.json.Value{ .string = "Enter" },
        }, .capacity = 2 },
    };
    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, action);

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Rally") != null);
}

test "terminal script key sequence advances pong rally" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected pong sequence failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    try std.testing.expect(try dispatchHeadlessTerminalKey(std.testing.allocator, &runtime, "Enter"));
    try std.testing.expect(try dispatchHeadlessTerminalKey(std.testing.allocator, &runtime, "Space"));

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Rally") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "o") != null);
}

test "full pong verifier key sequence still reaches rally state" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected pong verifier failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const keys = [_][]const u8{ "Enter", "Space", "Space", "Space", "Space", "Space", "Enter", "Space" };
    for (keys) |key| {
        try std.testing.expect(try dispatchHeadlessTerminalKey(std.testing.allocator, &runtime, key));
    }

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Rally") != null);
}

test "parsed pong script drives terminal bindings" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const script = @embedFile("../tests/examples/pong_sequence.json");

    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected pong parsed script failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, script, .{});
    defer parsed.deinit();
    const actions_value = switch (parsed.value) {
        .object => |object| object.get("actions") orelse return error.InvalidHeadlessScript,
        else => return error.InvalidHeadlessScript,
    };
    const actions = switch (actions_value) {
        .array => |array| array.items,
        else => return error.InvalidHeadlessScript,
    };
    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    for (actions) |action| {
        try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, action);
    }

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Rally") != null);
}

test "terminal counter key binding increments terminal app" {
    const source = @embedFile("../examples/terminal/counter/counter.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal counter failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    try std.testing.expect(try dispatchHeadlessTerminalKey(std.testing.allocator, &runtime, "+"));

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expectEqualStrings("1+", render);
}

test "terminal mouse click dispatches visible button region" {
    const source = @embedFile("../examples/terminal/counter/counter.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal counter mouse failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);

    var click_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.button_index != null) {
            click_region = region;
            break;
        }
    }
    try std.testing.expect(click_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    const region = click_region.?;
    try handleTerminalMouseEvent(std.testing.allocator, &runtime, &input_state, .{
        .x = region.x,
        .y = region.y,
        .button = .release,
        .is_motion = false,
    });

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expectEqualStrings("1+", render);
}

test "terminal mouse double click opens cells editor" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells mouse failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);

    var edit_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.label_double_click_index != null) {
            edit_region = region;
            break;
        }
    }
    try std.testing.expect(edit_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    const region = edit_region.?;
    try handleTerminalMouseEvent(std.testing.allocator, &runtime, &input_state, .{
        .x = region.x,
        .y = region.y,
        .button = .release,
        .is_motion = false,
    });
    try handleTerminalMouseEvent(std.testing.allocator, &runtime, &input_state, .{
        .x = region.x,
        .y = region.y,
        .button = .release,
        .is_motion = false,
    });

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "<5>") != null);
}

test "terminal mouse motion updates hover-gated todo controls" {
    const source = @embedFile("../examples/terminal/todo_mvc/todo_mvc.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal todo hover failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const initial = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "×") == null);

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);

    var hover_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.hover_index != null) {
            hover_region = region;
            break;
        }
    }
    try std.testing.expect(hover_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    const region = hover_region.?;
    try handleTerminalMouseEvent(std.testing.allocator, &runtime, &input_state, .{
        .x = region.x,
        .y = region.y,
        .button = .left,
        .is_motion = true,
    });

    const hovered = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(hovered);
    try std.testing.expect(std.mem.indexOf(u8, hovered, "×") != null);
}

test "executeHeadlessScriptAction applies mouse_click to terminal app" {
    const source = @embedFile("../examples/terminal/counter/counter.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal counter mouse script failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);
    var click_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.button_index != null) {
            click_region = region;
            break;
        }
    }
    try std.testing.expect(click_region != null);

    const region = click_region.?;
    const action = std.json.Value{
        .array = .{ .items = &.{
            std.json.Value{ .string = "mouse_click" },
            std.json.Value{ .integer = @intCast(region.x) },
            std.json.Value{ .integer = @intCast(region.y) },
        }, .capacity = 3 },
    };
    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, action);

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expectEqualStrings("1+", render);
}

test "executeHeadlessScriptAction applies mouse_move to hover terminal app" {
    const source = @embedFile("../examples/terminal/todo_mvc/todo_mvc.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal todo mouse script failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);
    var hover_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.hover_index != null) {
            hover_region = region;
            break;
        }
    }
    try std.testing.expect(hover_region != null);

    const region = hover_region.?;
    const action = std.json.Value{
        .array = .{ .items = &.{
            std.json.Value{ .string = "mouse_move" },
            std.json.Value{ .integer = @intCast(region.x) },
            std.json.Value{ .integer = @intCast(region.y) },
        }, .capacity = 3 },
    };
    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, action);

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "×") != null);
}

test "terminal cells mouse move updates hover status and visible hovered cell" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells hover failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);

    var target_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.button_index != null and region.y > 0 and region.x > 10) {
            target_region = region;
            break;
        }
    }
    try std.testing.expect(target_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    const region = target_region.?;
    try handleTerminalMouseEvent(std.testing.allocator, &runtime, &input_state, .{
        .x = region.x,
        .y = region.y,
        .button = .left,
        .is_motion = true,
    });

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Hover B0") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "* 15 *") != null);
}

test "terminal cells enter on formula cell opens editor with formula text" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells formula edit failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try openFocusedCellForEdit(&runtime, &input_state);

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Editing B0") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "=add(A0, A1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Formula B0 : =add(A0, A1)") != null);
    try std.testing.expect(input_state.focused_text_input != null);
}

test "terminal cells escape exits edit mode immediately and keeps formula visible in formula bar" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells escape failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try openFocusedCellForEdit(&runtime, &input_state);
    try dispatchTerminalTestKey(&runtime, &input_state, "Escape");

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Ready") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Editing B0") == null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "<=add(A0, A1)>") == null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Formula B0 : =add(A0, A1)") != null);
    try std.testing.expect(input_state.focused_text_input == null);
}

test "terminal cells viewport stays until focus leaves visible rows" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells viewport failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    inline for (0..2) |_| try dispatchTerminalTestKey(&runtime, &input_state, "Down");
    const first_snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(first_snapshot);
    try std.testing.expect(std.mem.indexOf(u8, first_snapshot, "[ 0  ][5   ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, first_snapshot, "Focus A2") != null);

    inline for (0..14) |_| try dispatchTerminalTestKey(&runtime, &input_state, "Down");
    const second_snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(second_snapshot);
    try std.testing.expect(std.mem.indexOf(u8, second_snapshot, "Focus A16") != null);
    try std.testing.expect(std.mem.indexOf(u8, second_snapshot, "[ 1  ||10") != null);
    try std.testing.expect(std.mem.indexOf(u8, second_snapshot, "[ 0  ][5   ]") == null);
}

test "terminal cells can escape and reopen formula edit then modify middle character with arrows" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells cursor edit failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try openFocusedCellForEdit(&runtime, &input_state);

    const editing_snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(editing_snapshot);
    try std.testing.expect(std.mem.indexOf(u8, editing_snapshot, "Editing C0") != null);
    try std.testing.expect(std.mem.indexOf(u8, editing_snapshot, "=sum(A0:A2)") != null);

    try dispatchTerminalTestKey(&runtime, &input_state, "Escape");
    const ready_snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(ready_snapshot);
    try std.testing.expect(std.mem.indexOf(u8, ready_snapshot, "Ready") != null);

    try openFocusedCellForEdit(&runtime, &input_state);
    try std.testing.expect(input_state.focused_text_input != null);

    inline for (0..4) |_| {
        try dispatchTerminalTestKey(&runtime, &input_state, "Left");
    }
    try dispatchTerminalTestKey(&runtime, &input_state, "Backspace");
    try dispatchTerminalTestKey(&runtime, &input_state, "1");
    try dispatchTerminalTestKey(&runtime, &input_state, "Enter");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "0 5 15 25") != null);

    try openFocusedCellForEdit(&runtime, &input_state);
    const edited_snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(edited_snapshot);
    try std.testing.expect(std.mem.indexOf(u8, edited_snapshot, "=sum(A1:A2)") != null);
}

test "terminal cells support 7guis formula functions with numbers and references" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells function-set failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    inline for (0..3) |_| try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=sub(A2, 4)");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=mul(A1, 4)");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=mod(A2, 6)");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=prod(2, 3, 4)");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=div(A2, 5)");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=div(1, 0)");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=add(I0, 2)");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "0 5 15 30 11 40 3 24 3 0 2") != null);
}

test "terminal cells support text direct refs ranges invalid refs and cycles" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells expression-rules failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    inline for (0..3) |_| try dispatchTerminalTestKey(&runtime, &input_state, "Down");
    try replaceFocusedCellText(&runtime, &input_state, "hello");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=A0");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=add(A3, 2)");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=B01");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=F3");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=E3");
    try dispatchTerminalTestKey(&runtime, &input_state, "Right");
    try replaceFocusedCellText(&runtime, &input_state, "=A0:C0");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "3 hello 5 2 0 0 0 50") != null);
}

test "terminal cells edit rerender scenario stays fast" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells performance failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    var timer = try std.time.Timer.start();

    try dispatchTerminalTestKey(&runtime, &input_state, "Down");
    try dispatchTerminalTestKey(&runtime, &input_state, "Down");
    try openFocusedCellForEdit(&runtime, &input_state);
    try dispatchTerminalTestKey(&runtime, &input_state, "5");
    try dispatchTerminalTestKey(&runtime, &input_state, "Enter");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "2 155") != null);

    const elapsed_ns = timer.read();
    const limit_ns: u64 = switch (@import("builtin").mode) {
        .ReleaseFast, .ReleaseSmall => 60 * std.time.ns_per_ms,
        .ReleaseSafe => 120 * std.time.ns_per_ms,
        .Debug => 500 * std.time.ns_per_ms,
    };
    try std.testing.expect(
        elapsed_ns <= limit_ns,
    );
}

test "executeHeadlessScriptAction applies mouse_double_click and key presses to terminal cells" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells mouse script failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);
    var edit_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.label_double_click_index != null) {
            edit_region = region;
            break;
        }
    }
    try std.testing.expect(edit_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);
    const region = edit_region.?;
    const double_click_action = std.json.Value{
        .array = .{ .items = &.{
            std.json.Value{ .string = "mouse_double_click" },
            std.json.Value{ .integer = @intCast(region.x) },
            std.json.Value{ .integer = @intCast(region.y) },
        }, .capacity = 3 },
    };
    const backspace_action = std.json.Value{
        .array = .{ .items = &.{
            std.json.Value{ .string = "press_key" },
            std.json.Value{ .string = "Backspace" },
        }, .capacity = 2 },
    };
    const type_action = std.json.Value{
        .array = .{ .items = &.{
            std.json.Value{ .string = "press_key" },
            std.json.Value{ .string = "7" },
        }, .capacity = 2 },
    };
    const enter_action = std.json.Value{
        .array = .{ .items = &.{
            std.json.Value{ .string = "press_key" },
            std.json.Value{ .string = "Enter" },
        }, .capacity = 2 },
    };

    try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, double_click_action);
    try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, backspace_action);
    try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, type_action);
    try executeHeadlessScriptAction(std.testing.allocator, &runtime, &input_state, enter_action);

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "0 7 17 32") != null);
}

test "executeTerminalCommand double-click helpers focus promoted text input in terminal cells" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells debug command failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    try executeTerminalCommand(std.testing.allocator, &runtime, &input_state, "dblclick-label 5");
    try std.testing.expect(input_state.focused_text_input != null);

    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Backspace");
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "7");
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Enter");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "0 7 17 32") != null);
}

test "executeTerminalCommand mouse-double-click opens cells editor from coordinates" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells mouse-double-click command failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);

    var edit_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.label_double_click_index) |_| {
            edit_region = region;
            break;
        }
    }
    try std.testing.expect(edit_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const region = edit_region.?;
    const command = try std.fmt.allocPrint(
        std.testing.allocator,
        "mouse-double-click {d} {d}",
        .{ region.x, region.y },
    );
    defer std.testing.allocator.free(command);

    try executeTerminalCommand(std.testing.allocator, &runtime, &input_state, command);

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "<5>") != null);
}

test "terminal cells live-style mouse double click then type then enter commits edit" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells live-style failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);
    var edit_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.label_double_click_index != null) {
            edit_region = region;
            break;
        }
    }
    try std.testing.expect(edit_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const region = edit_region.?;
    try dispatchHeadlessTerminalMouse(std.testing.allocator, &runtime, &input_state, region.x, region.y, .double_click);
    try std.testing.expect(input_state.focused_text_input != null);

    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Backspace");
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "7");
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Enter");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "0 7 17 32") != null);
}

test "terminal cells arrow key moves visible selection live-style" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells arrow-key failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    var contract = (try runtime.terminalContractAlloc(std.testing.allocator)).?;
    defer contract.deinit(std.testing.allocator);
    _ = try dispatchTerminalNamedKey(std.testing.allocator, &runtime, &contract, &input_state, "Right");

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "[B   ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "[ 15 ]") != null);
}

test "terminal cells arrow navigation does not schedule text-input focus promotion" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells arrow promotion failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    var contract = (try runtime.terminalContractAlloc(std.testing.allocator)).?;
    defer contract.deinit(std.testing.allocator);
    _ = try dispatchTerminalNamedKey(std.testing.allocator, &runtime, &contract, &input_state, "Down");

    try std.testing.expectEqual(@as(?usize, null), input_state.focused_text_input);
    try std.testing.expect(!input_state.pending_focus_promote);
}

test "terminal cells partial formula typing does not crash on empty cell" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells partial formula failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const keys = [_][]const u8{
        "Down",  "Down",  "Down",  "Down",  "Down",  "Down",
        "Right", "Right", "Right", "Right", "Right", "Right", "Right", "Right",
        "Enter", "=",     "a",     "d",     "d",     "(",     "i",
    };
    for (keys) |key| {
        _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, key);
    }

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Focus I6  Hover none Editing I6") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "Formula  I6 : =add(i") != null);
}

test "terminal cells full lowercase formula typing does not crash on H5" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells lowercase formula failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const keys = [_][]const u8{
        "Down",  "Down",  "Down",  "Down",  "Down",
        "Right", "Right", "Right", "Right", "Right", "Right", "Right",
        "Enter", "=",     "m",     "u",     "l",     "(",     "f",     "5",
        ",",     " ",     "g",     "5",     ")",
    };
    for (keys) |key| {
        _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, key);
    }

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Focus H5  Hover none Editing H5") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "Formula  H5 : =mul(f5, g5)") != null);
}

test "terminal cells uppercase references compute correctly after commit" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells uppercase reference failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const keys = [_][]const u8{
        "Down",  "Down",  "Down",  "Down",  "Down",
        "Right", "Right", "Right", "Right", "Right", "Right", "Right",
        "Enter", "=",     "m",     "u",     "l",     "(",     "F",     "5",
        ",",     " ",     "G",     "5",     ")",     "Enter",
    };
    for (keys) |key| {
        _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, key);
    }

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Focus H5  Hover none Ready") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "| 5  |") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "| 18 ") != null);
}

test "terminal cells typing into empty cell then snapshot then Right keeps editing stable" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells right-after-typing failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const keys = [_][]const u8{
        "Down", "Down", "Down", "Down", "Down",
        "Right", "Right", "Right", "Right", "Right",
        "Enter", "3",
    };
    for (keys) |key| {
        _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, key);
    }

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);

    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Right");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "Editing F5") != null);
    try std.testing.expect(std.mem.indexOf(u8, render, "Formula  F5 : 3") != null);
}

test "terminal cells coordinate mouse double click then type then enter commits edit" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells coordinate failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);
    var edit_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.label_double_click_index != null) {
            edit_region = region;
            break;
        }
    }
    try std.testing.expect(edit_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const region = edit_region.?;
    try dispatchHeadlessTerminalMouse(std.testing.allocator, &runtime, &input_state, region.x, region.y, .double_click);
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Backspace");
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "7");
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Enter");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "0 7 17 32") != null);
}

test "terminal cells coordinate path still commits after snapshot between typing and enter" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try boon.headless.runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells snapshot coordinate failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var runtime = session_value;
    defer runtime.deinit();

    const regions = (try runtime.terminalHitRegionsAlloc(std.testing.allocator)).?;
    defer std.testing.allocator.free(regions);
    var edit_region: ?boon.headless.TerminalHitRegion = null;
    for (regions) |region| {
        if (region.label_double_click_index != null) {
            edit_region = region;
            break;
        }
    }
    try std.testing.expect(edit_region != null);

    var input_state = TerminalInputState{};
    defer input_state.deinit(std.testing.allocator);

    const region = edit_region.?;
    try dispatchHeadlessTerminalMouse(std.testing.allocator, &runtime, &input_state, region.x, region.y, .double_click);
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Backspace");
    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "7");

    const snapshot = try runtime.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "<7>") != null);

    _ = try dispatchHeadlessTerminalNamedKey(std.testing.allocator, &runtime, &input_state, "Enter");

    const render = try runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(render);
    try std.testing.expect(std.mem.indexOf(u8, render, "0 7 17 32") != null);
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
    var rendered_any = false;
    for (themes, 0..) |theme, index| {
        const payload = physicalStateJsonAlloc(allocator, source, theme, "Light") catch continue;
        defer allocator.free(payload);
        const trimmed = std.mem.trimEnd(u8, payload, "\n");
        if (rendered_any and index != 0) try out.writer.writeByte(',');
        try writeJsonEscapedString(&out.writer, theme);
        try out.writer.writeByte(':');
        try out.writer.writeAll(trimmed);
        rendered_any = true;
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

fn executeHeadlessScriptAction(
    allocator: std.mem.Allocator,
    runtime: *boon.headless.Session,
    input_state: *TerminalInputState,
    action: std.json.Value,
) !void {
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
    if (std.mem.eql(u8, name, "press_key")) {
        if (parts.len != 2) return error.InvalidHeadlessScript;
        _ = try dispatchHeadlessTerminalNamedKey(allocator, runtime, input_state, try jsonString(parts[1]));
        return;
    }
    if (std.mem.eql(u8, name, "mouse_move")) {
        if (parts.len != 3) return error.InvalidHeadlessScript;
        try dispatchHeadlessTerminalMouse(allocator, runtime, input_state, try jsonIndex(parts[1]), try jsonIndex(parts[2]), .move);
        return;
    }
    if (std.mem.eql(u8, name, "mouse_click")) {
        if (parts.len != 3) return error.InvalidHeadlessScript;
        try dispatchHeadlessTerminalMouse(allocator, runtime, input_state, try jsonIndex(parts[1]), try jsonIndex(parts[2]), .click);
        return;
    }
    if (std.mem.eql(u8, name, "mouse_double_click")) {
        if (parts.len != 3) return error.InvalidHeadlessScript;
        try dispatchHeadlessTerminalMouse(allocator, runtime, input_state, try jsonIndex(parts[1]), try jsonIndex(parts[2]), .double_click);
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
    const args = [_][]const u8{ "boon-zig", "--version" };
    try std.testing.expectEqual(.version, try parseArgs(std.testing.allocator, &args));
}

test "parseArgs accepts parse path" {
    const args = [_][]const u8{ "boon-zig", "parse", "examples/upstream/counter/counter.bn" };
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .parse => |path| try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", path),
        else => return error.ExpectedParseCommand,
    }
}

test "parseArgs accepts hir path" {
    const args = [_][]const u8{ "boon-zig", "hir", "examples/upstream/counter/counter.bn" };
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .hir => |path| try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", path),
        else => return error.ExpectedHirCommand,
    }
}

test "parseArgs accepts physical-state path" {
    const args = [_][]const u8{ "boon-zig", "physical-state", "examples/upstream/todo_mvc_physical/RUN.bn" };
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
    const args = [_][]const u8{ "boon-zig", "flow", "examples/upstream/counter/counter.bn" };
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .flow => |path| try std.testing.expectEqualStrings("examples/upstream/counter/counter.bn", path),
        else => return error.ExpectedFlowCommand,
    }
}

test "parseArgs accepts verify-upstream-pin" {
    const args = [_][]const u8{ "boon-zig", "verify-upstream-pin" };
    try std.testing.expectEqual(.verify_upstream_pin, try parseArgs(std.testing.allocator, &args));
}

test "parseArgs accepts example shorthand" {
    const args = [_][]const u8{ "boon-zig", "example", "cells", "--trace" };
    const command = try parseArgs(std.testing.allocator, &args);
    switch (command) {
        .example => |terminal_args| {
            try std.testing.expectEqualStrings("examples/terminal/cells/cells.bn", terminal_args.path);
            try std.testing.expect(terminal_args.trace);
        },
        else => return error.ExpectedExampleCommand,
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
    const args = [_][]const u8{ "boon-zig", "nope" };
    try std.testing.expectError(error.UnknownCommand, parseArgs(std.testing.allocator, &args));
}
