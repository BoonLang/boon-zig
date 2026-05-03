const std = @import("std");
const common = @import("image_tool_common.zig");

pub fn main(process_init: std.process.Init) !u8 {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const argv = process_init.minimal.args.vector;
    var options: common.Options = .{};
    var json = false;
    var preview: ?[]const u8 = null;
    var inputs = std.ArrayList([]const u8).empty;
    defer inputs.deinit(allocator);

    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        const arg = std.mem.span(argv[index]);
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.eql(u8, arg, "--max-bytes")) {
            index += 1;
            options.max_bytes = try parsePositive(u64, argv, index, "--max-bytes");
        } else if (std.mem.eql(u8, arg, "--max-pixels")) {
            index += 1;
            options.max_pixels = try parsePositive(u64, argv, index, "--max-pixels");
        } else if (std.mem.eql(u8, arg, "--preview")) {
            index += 1;
            preview = try required(argv, index, "--preview");
        } else if (std.mem.eql(u8, arg, "--preview-max-edge")) {
            index += 1;
            options.preview_edge = try parsePositive(u32, argv, index, "--preview-max-edge");
        } else if (std.mem.eql(u8, arg, "--preview-quality")) {
            index += 1;
            options.preview_quality = try parsePositive(u8, argv, index, "--preview-quality");
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return 0;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("unknown option: {s}\n", .{arg});
            return 2;
        } else {
            try inputs.append(allocator, arg);
        }
    }

    if (inputs.items.len == 0) {
        printHelp();
        return 2;
    }
    if (preview != null and inputs.items.len != 1) {
        std.debug.print("--preview can only be used with one input image\n", .{});
        return 2;
    }

    var infos = std.ArrayList(common.ImageInfo).empty;
    defer infos.deinit(allocator);
    for (inputs.items) |input| try infos.append(allocator, try common.analyze(allocator, input, options));

    var preview_info: ?common.ImageInfo = null;
    if (preview) |preview_path| {
        try common.makePreview(process_init, allocator, inputs.items[0], preview_path, options);
        preview_info = try common.analyze(allocator, preview_path, options);
    }

    if (json) {
        try printJson(infos.items, preview_info);
    } else {
        for (infos.items) |info| printInfo(info, options, preview_info);
    }

    var unsafe = false;
    for (infos.items) |info| unsafe = unsafe or !info.direct_upload_ok;
    if (unsafe and !(preview_info != null and preview_info.?.direct_upload_ok)) return 1;
    return 0;
}

fn printInfo(info: common.ImageInfo, options: common.Options, preview_info: ?common.ImageInfo) void {
    std.debug.print("{s}: {d}x{d} {s}, {d:.2} MiB, base64 ~= {d:.2} MiB\n", .{
        info.path,
        info.width,
        info.height,
        info.format,
        info.mib(),
        info.base64Mib(),
    });
    std.debug.print("  pixels={d} raw_rgba={d:.2} MiB direct_upload_ok={}\n", .{ info.pixels, info.rawRgbaMib(), info.direct_upload_ok });
    if (!info.direct_upload_ok) {
        const recommendation = common.recommendedPreview(info, options.preview_edge);
        std.debug.print("  block:", .{});
        if (info.too_many_bytes) std.debug.print(" file bytes {d} > {d};", .{ info.bytes, options.max_bytes });
        if (info.too_many_pixels) std.debug.print(" pixels {d} > {d};", .{ info.pixels, options.max_pixels });
        std.debug.print("\n  use: JPEG preview at <= {d}x{d} ({d}px max edge, quality {d})\n", .{ recommendation.width, recommendation.height, recommendation.max_edge, options.preview_quality });
        std.debug.print("  example: zig build image-preflight -- {s} --preview /tmp/{s}.preview.jpg\n", .{ info.path, basenameWithoutExtension(info.path) });
    }
    if (preview_info) |preview| {
        std.debug.print("  preview: {s}: {d}x{d}, {d:.2} MiB\n", .{ preview.path, preview.width, preview.height, preview.mib() });
    }
}

fn printJson(infos: []const common.ImageInfo, preview_info: ?common.ImageInfo) !void {
    var out = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll("{\n  \"images\": [\n");
    for (infos, 0..) |info, i| {
        if (i != 0) try w.writeAll(",\n");
        try writeInfoJson(w, info, preview_info);
    }
    try w.writeAll("\n  ]\n}\n");
    const bytes = try out.toOwnedSlice();
    defer std.heap.page_allocator.free(bytes);
    std.debug.print("{s}", .{bytes});
}

fn writeInfoJson(w: *std.Io.Writer, info: common.ImageInfo, preview_info: ?common.ImageInfo) !void {
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
        try w.print("\"file bytes {d}\"", .{info.bytes});
        first = false;
    }
    if (info.too_many_pixels) {
        if (!first) try w.writeAll(", ");
        try w.print("\"pixels {d}\"", .{info.pixels});
    }
    try w.writeAll("]");
    if (preview_info) |preview| {
        try w.writeAll(",\n      \"preview\": ");
        try writeInfoJsonInline(w, preview);
    }
    try w.writeAll("\n    }");
}

fn writeInfoJsonInline(w: *std.Io.Writer, info: common.ImageInfo) !void {
    try w.writeAll("{ \"path\": \"");
    try common.writeJsonStringContent(w, info.path);
    try w.print("\", \"format\": \"{s}\", \"width\": {d}, \"height\": {d}, \"bytes\": {d}, \"mib\": {d:.2}, \"direct_upload_ok\": {} }}", .{
        info.format,
        info.width,
        info.height,
        info.bytes,
        info.mib(),
        info.direct_upload_ok,
    });
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

fn basenameWithoutExtension(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| return base[0..dot];
    return base;
}

fn printHelp() void {
    std.debug.print(
        \\Usage: zig build image-preflight -- [options] <image...>
        \\
        \\Options:
        \\  --json                      Print machine-readable output.
        \\  --max-bytes <n>             Direct-upload byte limit. Default: 8388608.
        \\  --max-pixels <n>            Direct-upload pixel limit. Default: 6000000.
        \\  --preview <path>            Create a JPEG preview for one input using ImageMagick convert.
        \\  --preview-max-edge <n>      Preview max width/height. Default: 1600.
        \\  --preview-quality <n>       JPEG preview quality. Default: 85.
        \\
        \\If direct_upload_ok=false, do not upload the original. Use the printed JPEG preview recommendation.
        \\
    , .{});
}
