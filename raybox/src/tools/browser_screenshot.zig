const std = @import("std");
const common = @import("image_tool_common.zig");

const Args = struct {
    web_dir: []const u8 = "zig-out/web",
    screenshot_path: []const u8 = "zig-out/verification/browser_canvas/run_playground_web.png",
    report_path: []const u8 = "zig-out/reports/browser_screenshot.json",
};

pub fn main(process_init: std.process.Init) !u8 {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = parseArgs(process_init.minimal.args.vector) catch |err| {
        if (err != error.HelpRequested) printHelp();
        return if (err == error.HelpRequested) 0 else 2;
    };
    const html_path = try std.fs.path.join(allocator, &.{ args.web_dir, "boon-playground-raybox.html" });
    defer allocator.free(html_path);
    if (!fileExists(html_path)) {
        try writeBlocked(allocator, args.report_path, "missing web build");
        std.debug.print("missing web build in {s}\n", .{args.web_dir});
        return 1;
    }

    try common.makeParents(args.screenshot_path);
    try common.makeParents(args.report_path);

    const chrome = try findChrome(process_init, allocator);
    defer allocator.free(chrome);
    const user_data_dir = try makeUserDataDir(allocator);
    defer {
        removeTree(process_init, allocator, user_data_dir);
        allocator.free(user_data_dir);
    }
    const url = try fileUrl(process_init, allocator, html_path);
    defer allocator.free(url);

    const user_data_arg = try std.fmt.allocPrint(allocator, "--user-data-dir={s}", .{user_data_dir});
    defer allocator.free(user_data_arg);
    const screenshot_arg = try std.fmt.allocPrint(allocator, "--screenshot={s}", .{args.screenshot_path});
    defer allocator.free(screenshot_arg);
    // This capture is headless and should not map a visible window. If this
    // tool gains a visible/manual browser mode, launch Chrome through
    // `cosmic-background-launch --`.
    const argv = [_][]const u8{
        chrome,
        "--headless=new",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--enable-unsafe-swiftshader",
        "--use-angle=swiftshader",
        "--allow-file-access-from-files",
        "--enable-logging=stderr",
        "--v=0",
        "--window-size=1940,1100",
        "--timeout=60000",
        user_data_arg,
        screenshot_arg,
        url,
    };
    const result = try std.process.run(allocator, process_init.io, .{
        .argv = &argv,
        .stdout_limit = .limited(512 * 1024),
        .stderr_limit = .limited(512 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const output = try std.mem.concat(allocator, u8, &.{ result.stdout, result.stderr });
    defer allocator.free(output);
    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                try writeBlockedWithTail(allocator, args.report_path, "chrome exited nonzero", output);
                std.debug.print("chrome exited with status {d}\n", .{code});
                return 1;
            }
        },
        else => {
            try writeBlockedWithTail(allocator, args.report_path, "chrome did not exit cleanly", output);
            return 1;
        },
    }

    const info = common.analyze(allocator, args.screenshot_path, .{}) catch |err| {
        try writeBlockedWithTail(allocator, args.report_path, @errorName(err), output);
        return 1;
    };
    const stats = analyzePngStats(process_init, allocator, args.screenshot_path) catch |err| {
        try writeBlockedWithTail(allocator, args.report_path, @errorName(err), output);
        return 1;
    };
    const runtime_failure_seen = hasRuntimeFailure(output);
    try writeDone(allocator, args.report_path, info, stats, runtime_failure_seen, output);
    if (runtime_failure_seen) {
        std.debug.print("browser screenshot captured but runtime failure was seen\n", .{});
        return 1;
    }
    std.debug.print("browser screenshot captured: {s} ({d}x{d}, {d:.2} MiB)\n", .{ args.screenshot_path, info.width, info.height, info.mib() });
    return 0;
}

fn parseArgs(argv: []const [*:0]const u8) !Args {
    if (argv.len > 1) {
        const first = std.mem.span(argv[1]);
        if (std.mem.eql(u8, first, "--help") or std.mem.eql(u8, first, "-h")) return error.HelpRequested;
    }
    if (argv.len > 4) return error.TooManyArguments;
    return .{
        .web_dir = if (argv.len > 1) std.mem.span(argv[1]) else "zig-out/web",
        .screenshot_path = if (argv.len > 2) std.mem.span(argv[2]) else "zig-out/verification/browser_canvas/run_playground_web.png",
        .report_path = if (argv.len > 3) std.mem.span(argv[3]) else "zig-out/reports/browser_screenshot.json",
    };
}

fn printHelp() void {
    std.debug.print(
        \\Usage: zig build browser-screenshot -- [web-dir] [screenshot-path] [report-path]
        \\
        \\Captures the wasm playground canvas through headless Chrome without Node.
        \\
    , .{});
}

fn findChrome(process_init: std.process.Init, allocator: std.mem.Allocator) ![]u8 {
    if (std.process.Environ.getPosix(process_init.minimal.environ, "RAYBOX_CHROME")) |env| {
        if (env.len != 0) return allocator.dupe(u8, env);
    }
    const names = [_][]const u8{
        "google-chrome",
        "chromium-browser",
        "chromium",
        "/usr/bin/google-chrome",
        "/usr/bin/chromium-browser",
        "/snap/bin/chromium",
    };
    for (names) |name| {
        if (std.mem.indexOfScalar(u8, name, '/') != null) {
            if (fileExists(name)) return allocator.dupe(u8, name);
            continue;
        }
        const argv = [_][]const u8{ "sh", "-c", try std.fmt.allocPrint(allocator, "command -v {s}", .{name}) };
        defer allocator.free(argv[2]);
        const result = std.process.run(allocator, process_init.io, .{
            .argv = &argv,
            .stdout_limit = .limited(16 * 1024),
            .stderr_limit = .limited(16 * 1024),
        }) catch continue;
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        if (result.term == .exited and result.term.exited == 0) {
            const resolved = std.mem.trim(u8, result.stdout, " \t\r\n");
            if (resolved.len != 0) return allocator.dupe(u8, resolved);
        }
    }
    return error.ChromeNotFound;
}

fn fileUrl(process_init: std.process.Init, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const absolute = if (std.fs.path.isAbsolute(path))
        try allocator.dupe(u8, path)
    else blk: {
        const cwd = try std.process.currentPathAlloc(process_init.io, allocator);
        defer allocator.free(cwd);
        break :blk try std.fs.path.join(allocator, &.{ cwd, path });
    };
    defer allocator.free(absolute);
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("file://");
    for (absolute) |byte| switch (byte) {
        ' ' => try out.writer.writeAll("%20"),
        '#' => try out.writer.writeAll("%23"),
        '?' => try out.writer.writeAll("%3F"),
        else => try out.writer.writeByte(byte),
    };
    return out.toOwnedSlice();
}

fn makeUserDataDir(allocator: std.mem.Allocator) ![]u8 {
    var attempt: usize = 0;
    while (attempt < 1000) : (attempt += 1) {
        const path = try std.fmt.allocPrint(allocator, "/tmp/raybox-chrome-zig-{d}-{d}", .{ c_getpid(), attempt });
        errdefer allocator.free(path);
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        if (c_mkdir(path_z.ptr, 0o700) == 0) return path;
        allocator.free(path);
    }
    return error.TempDirCreateFailed;
}

fn removeTree(process_init: std.process.Init, allocator: std.mem.Allocator, path: []const u8) void {
    const argv = [_][]const u8{ "rm", "-rf", path };
    const result = std.process.run(allocator, process_init.io, .{
        .argv = &argv,
        .stdout_limit = .limited(1),
        .stderr_limit = .limited(1),
    }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

fn fileExists(path: []const u8) bool {
    const path_z = std.heap.page_allocator.dupeZ(u8, path) catch return false;
    defer std.heap.page_allocator.free(path_z);
    const file = c_fopen(path_z.ptr, "rb") orelse return false;
    _ = c_fclose(file);
    return true;
}

const PngStats = struct {
    distinct_colors: u64 = 0,
    non_black_pixels: u64 = 0,
    clay_shell_pixels: u64 = 0,
    physical_preview_pixels: u64 = 0,
};

fn analyzePngStats(process_init: std.process.Init, allocator: std.mem.Allocator, path: []const u8) !PngStats {
    const argv = [_][]const u8{ "convert", path, "-format", "%c", "histogram:info:-" };
    const result = try std.process.run(allocator, process_init.io, .{
        .argv = &argv,
        .stdout_limit = .limited(4 * 1024 * 1024),
        .stderr_limit = .limited(128 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.HistogramFailed,
        else => return error.HistogramFailed,
    }
    var stats: PngStats = .{};
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const count = std.fmt.parseUnsigned(u64, std.mem.trim(u8, line[0..colon], " \t"), 10) catch continue;
        const open = std.mem.indexOfScalarPos(u8, line, colon, '(') orelse continue;
        const close = std.mem.indexOfScalarPos(u8, line, open, ')') orelse continue;
        var components = std.mem.splitScalar(u8, line[open + 1 .. close], ',');
        const r = parseComponent(components.next() orelse continue) orelse continue;
        const g = parseComponent(components.next() orelse continue) orelse continue;
        const b = parseComponent(components.next() orelse continue) orelse continue;
        stats.distinct_colors += 1;
        if (r != 0 or g != 0 or b != 0) stats.non_black_pixels += count;
        if (closeColor(r, g, b, 36, 40, 48) or
            closeColor(r, g, b, 28, 32, 38) or
            closeColor(r, g, b, 45, 53, 65))
        {
            stats.clay_shell_pixels += count;
        }
        if (closeColor(r, g, b, 245, 242, 237) or
            closeColor(r, g, b, 255, 252, 247) or
            closeColor(r, g, b, 199, 107, 59) or
            closeColor(r, g, b, 82, 133, 217))
        {
            stats.physical_preview_pixels += count;
        }
    }
    return stats;
}

fn parseComponent(text: []const u8) ?u16 {
    return std.fmt.parseUnsigned(u16, std.mem.trim(u8, text, " \t"), 10) catch null;
}

fn closeColor(r: u16, g: u16, b: u16, tr: u16, tg: u16, tb: u16) bool {
    return absDiff(r, tr) <= 2 and absDiff(g, tg) <= 2 and absDiff(b, tb) <= 2;
}

fn absDiff(a: u16, b: u16) u16 {
    return if (a > b) a - b else b - a;
}

fn writeDone(allocator: std.mem.Allocator, report_path: []const u8, info: common.ImageInfo, stats: PngStats, runtime_failure_seen: bool, output: []const u8) !void {
    var report = std.Io.Writer.Allocating.init(allocator);
    defer report.deinit();
    const w = &report.writer;
    try w.writeAll("{\n  \"status\": \"DONE\",\n  \"message\": \"browser screenshot captured\",\n  \"screenshot\": \"");
    try common.writeJsonStringContent(w, info.path);
    try w.print("\",\n  \"width\": {d},\n  \"height\": {d},\n  \"bytes\": {d},\n  \"mib\": {d:.2},\n  \"distinct_colors\": {d},\n  \"non_black_pixels\": {d},\n  \"clay_shell_pixels\": {d},\n  \"physical_preview_pixels\": {d},\n  \"runtime_failure_seen\": {}", .{
        info.width,
        info.height,
        info.bytes,
        info.mib(),
        stats.distinct_colors,
        stats.non_black_pixels,
        stats.clay_shell_pixels,
        stats.physical_preview_pixels,
        runtime_failure_seen,
    });
    if (runtime_failure_seen) {
        try w.writeAll(",\n  \"runtime_failure_output_tail\": \"");
        try common.writeJsonStringContent(w, tail(output));
        try w.writeAll("\"");
    }
    try w.writeAll("\n}\n");
    const bytes = try report.toOwnedSlice();
    defer allocator.free(bytes);
    try common.writeFile(report_path, bytes);
}

fn writeBlocked(allocator: std.mem.Allocator, report_path: []const u8, message: []const u8) !void {
    try writeBlockedWithTail(allocator, report_path, message, "");
}

fn writeBlockedWithTail(allocator: std.mem.Allocator, report_path: []const u8, message: []const u8, output: []const u8) !void {
    var report = std.Io.Writer.Allocating.init(allocator);
    defer report.deinit();
    const w = &report.writer;
    try w.writeAll("{\n  \"status\": \"BLOCKED\",\n  \"message\": \"");
    try common.writeJsonStringContent(w, message);
    try w.writeAll("\"");
    if (output.len != 0) {
        try w.writeAll(",\n  \"output_tail\": \"");
        try common.writeJsonStringContent(w, tail(output));
        try w.writeAll("\"");
    }
    try w.writeAll("\n}\n");
    const bytes = try report.toOwnedSlice();
    defer allocator.free(bytes);
    try common.writeFile(report_path, bytes);
}

fn hasRuntimeFailure(output: []const u8) bool {
    const needles = [_][]const u8{
        "failed to initialize Boon playground runtime",
        "Aborted",
        "RuntimeError",
        "OutOfMemory",
        "segmentation fault",
    };
    for (needles) |needle| {
        if (std.mem.indexOf(u8, output, needle) != null) return true;
    }
    return false;
}

fn tail(output: []const u8) []const u8 {
    const max = 8192;
    if (output.len <= max) return output;
    return output[output.len - max ..];
}

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(file: *anyopaque) c_int;
extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern fn getpid() c_int;

const c_fopen = fopen;
const c_fclose = fclose;
const c_mkdir = mkdir;
const c_getpid = getpid;
