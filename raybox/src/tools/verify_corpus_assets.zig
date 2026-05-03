const std = @import("std");
const raybox = @import("raybox");

const svg_minimal = raybox.render.svg_minimal;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    _ = c_mkdir("zig-out", 0o777);
    _ = c_mkdir("zig-out/reports", 0o777);

    verify(allocator) catch |err| {
        try writeReport("BLOCKED", @errorName(err));
        std.debug.print("verify-corpus SVG/data URI check failed: {s}\n", .{@errorName(err)});
        return err;
    };
    try writeReport("DONE", "SVG/data URI corpus assets passed");
}

fn verify(allocator: std.mem.Allocator) !void {
    const active_svg = try readFile(allocator, "examples/upstream/todo_mvc_physical/assets/icons/checkbox_active.svg");
    defer allocator.free(active_svg);
    try parseSvgFile(allocator, "examples/upstream/todo_mvc_physical/assets/icons/checkbox_active.svg", active_svg);

    const completed_svg = try readFile(allocator, "examples/upstream/todo_mvc_physical/assets/icons/checkbox_completed.svg");
    defer allocator.free(completed_svg);
    try parseSvgFile(allocator, "examples/upstream/todo_mvc_physical/assets/icons/checkbox_completed.svg", completed_svg);

    const generated = try readFile(allocator, "examples/upstream/todo_mvc_physical/Generated/Assets.bn");
    defer allocator.free(generated);
    try parseGeneratedUri(allocator, generated, "checkbox_active");
    try parseGeneratedUri(allocator, generated, "checkbox_completed");
}

fn parseSvgFile(allocator: std.mem.Allocator, path: []const u8, source: []const u8) !void {
    var svg = svg_minimal.parse(allocator, source) catch |err| {
        std.debug.print("{s}: unsupported SVG syntax: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    defer svg.deinit(allocator);
    if (svg.shapes.len == 0) return error.EmptySvg;
}

fn parseGeneratedUri(allocator: std.mem.Allocator, generated: []const u8, name: []const u8) !void {
    const label = try std.fmt.allocPrint(allocator, "{s}: TEXT {{", .{name});
    defer allocator.free(label);
    const label_index = std.mem.indexOf(u8, generated, label) orelse return error.MissingGeneratedIcon;
    const data_start = std.mem.indexOfPos(u8, generated, label_index, "data:image/svg+xml;utf8,") orelse return error.MissingDataUri;
    const uri_start = data_start + "data:image/svg+xml;utf8,".len;
    const uri_end = std.mem.indexOfScalarPos(u8, generated, uri_start, '\n') orelse return error.MissingDataUri;
    const encoded = std.mem.trim(u8, generated[uri_start..uri_end], " \t\r\n");
    const decoded = try percentDecode(allocator, encoded);
    defer allocator.free(decoded);

    const synthetic_path = try std.fmt.allocPrint(allocator, "Generated/Assets.bn:{s}", .{name});
    defer allocator.free(synthetic_path);
    try parseSvgFile(allocator, synthetic_path, decoded);
}

fn percentDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    var index: usize = 0;
    while (index < encoded.len) {
        if (encoded[index] == '%') {
            if (index + 2 >= encoded.len) return error.InvalidPercentEncoding;
            const high = try hexValue(encoded[index + 1]);
            const low = try hexValue(encoded[index + 2]);
            try out.writer.writeByte((high << 4) | low);
            index += 3;
        } else {
            try out.writer.writeByte(encoded[index]);
            index += 1;
        }
    }
    return try out.toOwnedSlice();
}

fn hexValue(byte: u8) !u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => error.InvalidPercentEncoding,
    };
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const file = c_fopen(path_z.ptr, "rb") orelse return error.FileNotFound;
    defer _ = c_fclose(file);
    if (c_fseek(file, 0, 2) != 0) return error.FileSeekFailed;
    const end = c_ftell(file);
    if (end < 0) return error.FileTellFailed;
    const size: usize = @intCast(end);
    if (size > 4 * 1024 * 1024) return error.FileTooLarge;
    if (c_fseek(file, 0, 0) != 0) return error.FileSeekFailed;
    const bytes = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);
    if (c_fread(bytes.ptr, 1, size, file) != size) return error.FileReadFailed;
    return bytes;
}

fn writeReport(status: []const u8, message: []const u8) !void {
    var output = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer output.deinit();
    try output.writer.print("{{\n  \"status\": \"{s}\",\n  \"message\": \"{s}\"\n}}\n", .{ status, message });
    const bytes = try output.toOwnedSlice();
    defer std.heap.page_allocator.free(bytes);
    const file = c_fopen("zig-out/reports/corpus_assets.json", "wb") orelse return error.FileCreateFailed;
    defer _ = c_fclose(file);
    if (c_fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.FileWriteFailed;
}

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(file: *anyopaque) c_int;
extern fn fseek(file: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(file: *anyopaque) c_long;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;

const c_fopen = fopen;
const c_fclose = fclose;
const c_fseek = fseek;
const c_ftell = ftell;
const c_fread = fread;
const c_fwrite = fwrite;
const c_mkdir = mkdir;
