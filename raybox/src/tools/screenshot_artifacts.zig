const std = @import("std");
const common = @import("image_tool_common.zig");

const ModeConfig = struct {
    name: []const u8,
    source: []const u8,
    out: []const u8,
    manifest: []const u8,
};

const modes = [_]ModeConfig{
    .{ .name = "native", .source = "zig-out/manual", .out = "zig-out/screenshots/native", .manifest = "zig-out/reports/screenshot_native.json" },
    .{ .name = "browser", .source = "zig-out/verification/browser_canvas", .out = "zig-out/screenshots/browser", .manifest = "zig-out/reports/screenshot_browser.json" },
    .{ .name = "terminal", .source = "zig-out/terminal", .out = "zig-out/screenshots/terminal", .manifest = "zig-out/reports/screenshot_terminal.json" },
};

const Args = struct {
    mode: []const u8 = "all",
    source: ?[]const u8 = null,
    out: ?[]const u8 = null,
    manifest: ?[]const u8 = null,
    options: common.Options = .{},
    delete_oversized: bool = false,
};

pub fn main(process_init: std.process.Init) !u8 {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const args = try parseArgs(process_init.minimal.args.vector);
    if (!(std.mem.eql(u8, args.mode, "all") or findMode(args.mode) != null)) {
        std.debug.print("unknown mode: {s}\n", .{args.mode});
        return 2;
    }

    var any_blocked = false;
    if (std.mem.eql(u8, args.mode, "all")) {
        for (modes) |mode| any_blocked = (try processMode(process_init, allocator, mode, args)) or any_blocked;
    } else {
        any_blocked = try processMode(process_init, allocator, findMode(args.mode).?, args);
    }
    return if (any_blocked) 1 else 0;
}

fn processMode(process_init: std.process.Init, allocator: std.mem.Allocator, mode: ModeConfig, args: Args) !bool {
    const source = args.source orelse mode.source;
    const out_dir = args.out orelse mode.out;
    const manifest = args.manifest orelse mode.manifest;

    var images = std.ArrayList([]u8).empty;
    defer {
        for (images.items) |image| allocator.free(image);
        images.deinit(allocator);
    }
    try collectImages(process_init.io, allocator, source, &images);

    var report = std.Io.Writer.Allocating.init(allocator);
    defer report.deinit();
    const w = &report.writer;
    try w.print(
        "{{\n  \"status\": \"{s}\",\n  \"mode\": \"{s}\",\n  \"source\": \"",
        .{ if (images.items.len == 0) "NO_IMAGES" else "DONE", mode.name },
    );
    try common.writeJsonStringContent(w, source);
    try w.writeAll("\",\n  \"output_dir\": \"");
    try common.writeJsonStringContent(w, out_dir);
    try w.print("\",\n  \"max_bytes\": {d},\n  \"max_pixels\": {d},\n  \"max_edge\": {d},\n  \"quality\": {d},\n  \"images\": [\n", .{
        args.options.max_bytes,
        args.options.max_pixels,
        args.options.preview_edge,
        args.options.preview_quality,
    });

    var blocked = false;
    for (images.items, 0..) |image, i| {
        const info = try common.analyze(allocator, image, args.options);
        const relative = imageRelativePath(source, image);
        const preview_name = try previewName(allocator, relative);
        defer allocator.free(preview_name);
        const preview_path = try std.fs.path.join(allocator, &.{ out_dir, preview_name });
        defer allocator.free(preview_path);
        try common.makePreview(process_init, allocator, image, preview_path, args.options);
        const preview_info = try common.analyze(allocator, preview_path, args.options);
        var removed = false;
        if (!info.direct_upload_ok and args.delete_oversized) {
            common.deleteFile(image);
            removed = true;
        }
        if (!preview_info.direct_upload_ok) blocked = true;

        if (i != 0) try w.writeAll(",\n");
        try writeItemJson(w, info, preview_info, removed);
        std.debug.print("  {s}: {s} -> {s} ({d}x{d}, {d:.2} MiB)\n", .{
            if (info.direct_upload_ok) "ok" else "preview",
            image,
            preview_path,
            preview_info.width,
            preview_info.height,
            preview_info.mib(),
        });
    }
    try w.writeAll("\n  ]\n}\n");
    const report_bytes = try report.toOwnedSlice();
    defer allocator.free(report_bytes);
    try common.writeFile(manifest, report_bytes);
    std.debug.print("{s}: {s}; images={d}; output={s}; manifest={s}\n", .{ mode.name, if (images.items.len == 0) "NO_IMAGES" else "DONE", images.items.len, out_dir, manifest });
    return blocked;
}

fn collectImages(io: std.Io, allocator: std.mem.Allocator, source: []const u8, images: *std.ArrayList([]u8)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, source, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer dir.close(io);
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!common.isImagePath(entry.path)) continue;
        if (common.isAnalysisPreview(entry.path)) continue;
        try images.append(allocator, try std.fs.path.join(allocator, &.{ source, entry.path }));
    }
}

fn writeItemJson(w: *std.Io.Writer, info: common.ImageInfo, preview: common.ImageInfo, removed: bool) !void {
    try w.writeAll("    {\n      \"path\": \"");
    try common.writeJsonStringContent(w, info.path);
    try w.print("\",\n      \"format\": \"{s}\",\n      \"width\": {d},\n      \"height\": {d},\n      \"pixels\": {d},\n      \"bytes\": {d},\n      \"mib\": {d:.2},\n      \"estimated_base64_bytes\": {d},\n      \"estimated_base64_mib\": {d:.2},\n      \"direct_upload_ok\": {},\n      \"reasons\": [", .{
        info.format,
        info.width,
        info.height,
        info.pixels,
        info.bytes,
        info.mib(),
        info.base64_bytes,
        info.base64Mib(),
        info.direct_upload_ok,
    });
    var first = true;
    if (info.too_many_bytes) {
        try w.print("\"file bytes {d} > limit\"", .{info.bytes});
        first = false;
    }
    if (info.too_many_pixels) {
        if (!first) try w.writeAll(", ");
        try w.print("\"pixels {d} > limit\"", .{info.pixels});
    }
    try w.writeAll("],\n      \"preview\": {\n        \"path\": \"");
    try common.writeJsonStringContent(w, preview.path);
    try w.print("\",\n        \"format\": \"{s}\",\n        \"width\": {d},\n        \"height\": {d},\n        \"pixels\": {d},\n        \"bytes\": {d},\n        \"mib\": {d:.2},\n        \"estimated_base64_bytes\": {d},\n        \"estimated_base64_mib\": {d:.2},\n        \"direct_upload_ok\": {},\n        \"reasons\": []\n      }},\n      \"original_removed\": {}\n    }}", .{
        preview.format,
        preview.width,
        preview.height,
        preview.pixels,
        preview.bytes,
        preview.mib(),
        preview.base64_bytes,
        preview.base64Mib(),
        preview.direct_upload_ok,
        removed,
    });
}

fn parseArgs(argv: []const [*:0]const u8) !Args {
    var out = Args{};
    var index: usize = 1;
    if (index < argv.len and !std.mem.startsWith(u8, std.mem.span(argv[index]), "--")) {
        out.mode = std.mem.span(argv[index]);
        index += 1;
    }
    while (index < argv.len) : (index += 1) {
        const arg = std.mem.span(argv[index]);
        if (std.mem.eql(u8, arg, "--source")) {
            index += 1;
            out.source = try required(argv, index, "--source");
        } else if (std.mem.eql(u8, arg, "--out")) {
            index += 1;
            out.out = try required(argv, index, "--out");
        } else if (std.mem.eql(u8, arg, "--manifest")) {
            index += 1;
            out.manifest = try required(argv, index, "--manifest");
        } else if (std.mem.eql(u8, arg, "--max-bytes")) {
            index += 1;
            out.options.max_bytes = try parsePositive(u64, argv, index, "--max-bytes");
        } else if (std.mem.eql(u8, arg, "--max-pixels")) {
            index += 1;
            out.options.max_pixels = try parsePositive(u64, argv, index, "--max-pixels");
        } else if (std.mem.eql(u8, arg, "--max-edge")) {
            index += 1;
            out.options.preview_edge = try parsePositive(u32, argv, index, "--max-edge");
        } else if (std.mem.eql(u8, arg, "--quality")) {
            index += 1;
            out.options.preview_quality = try parsePositive(u8, argv, index, "--quality");
        } else if (std.mem.eql(u8, arg, "--delete-oversized")) {
            out.delete_oversized = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            return error.UnknownOption;
        }
    }
    return out;
}

fn findMode(name: []const u8) ?ModeConfig {
    for (modes) |mode| if (std.mem.eql(u8, mode.name, name)) return mode;
    return null;
}

fn required(argv: []const [*:0]const u8, index: usize, name: []const u8) ![]const u8 {
    if (index >= argv.len) {
        std.debug.print("{s} requires a value\n", .{name});
        return error.MissingArgument;
    }
    return std.mem.span(argv[index]);
}

fn parsePositive(comptime T: type, argv: []const [*:0]const u8, index: usize, name: []const u8) !T {
    const value = try required(argv, index, name);
    const parsed = try std.fmt.parseUnsigned(T, value, 10);
    if (parsed == 0) return error.InvalidArgument;
    return parsed;
}

fn imageRelativePath(source: []const u8, image: []const u8) []const u8 {
    if (std.mem.startsWith(u8, image, source)) {
        var rel = image[source.len..];
        while (std.mem.startsWith(u8, rel, "/")) rel = rel[1..];
        return rel;
    }
    return std.fs.path.basename(image);
}

fn previewName(allocator: std.mem.Allocator, relative: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    const stem = if (std.mem.lastIndexOfScalar(u8, relative, '.')) |dot| relative[0..dot] else relative;
    for (stem) |byte| {
        try out.writer.writeByte(if (byte == '/' or byte == '\\') '_' else byte);
    }
    try out.writer.writeAll(".analysis.jpg");
    return try out.toOwnedSlice();
}

fn printHelp() void {
    std.debug.print(
        \\Usage: zig build screenshot-artifacts -- <native|browser|terminal|all> [options]
        \\
        \\Creates bounded JPEG analysis previews and JSON manifests for screenshot artifacts.
        \\
        \\Options:
        \\  --source <dir>          Source image directory.
        \\  --out <dir>             Output preview directory.
        \\  --manifest <path>       Output JSON manifest path.
        \\  --max-bytes <n>         Direct-upload byte limit. Default: 8388608.
        \\  --max-pixels <n>        Direct-upload pixel limit. Default: 6000000.
        \\  --max-edge <n>          Preview max width/height. Default: 1600.
        \\  --quality <n>           JPEG preview quality. Default: 85.
        \\  --delete-oversized      Remove source images only after preview generation when direct_upload_ok=false.
        \\
    , .{});
}
