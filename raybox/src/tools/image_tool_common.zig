const std = @import("std");

pub const Options = struct {
    max_bytes: u64 = 8 * 1024 * 1024,
    max_pixels: u64 = 6_000_000,
    preview_edge: u32 = 1600,
    preview_quality: u8 = 85,
};

pub const ImageInfo = struct {
    path: []const u8,
    format: []const u8,
    width: u32,
    height: u32,
    pixels: u64,
    bytes: u64,
    base64_bytes: u64,
    direct_upload_ok: bool,
    too_many_bytes: bool,
    too_many_pixels: bool,

    pub fn mib(self: ImageInfo) f64 {
        return @as(f64, @floatFromInt(self.bytes)) / 1024.0 / 1024.0;
    }

    pub fn base64Mib(self: ImageInfo) f64 {
        return @as(f64, @floatFromInt(self.base64_bytes)) / 1024.0 / 1024.0;
    }

    pub fn rawRgbaMib(self: ImageInfo) f64 {
        const raw = @as(u64, self.width) * @as(u64, self.height) * 4;
        return @as(f64, @floatFromInt(raw)) / 1024.0 / 1024.0;
    }
};

pub const PreviewSize = struct {
    width: u32,
    height: u32,
    max_edge: u32,
};

const PrefixRead = struct {
    bytes: []u8,
    file_size: u64,
};

pub fn analyze(allocator: std.mem.Allocator, path: []const u8, options: Options) !ImageInfo {
    const prefix = try readPrefix(allocator, path, 2 * 1024 * 1024);
    defer allocator.free(prefix.bytes);
    const dims = try readDimensions(prefix.bytes, path);
    const pixels = @as(u64, dims.width) * @as(u64, dims.height);
    const base64_bytes = ((prefix.file_size + 2) / 3) * 4;
    const too_many_bytes = prefix.file_size > options.max_bytes;
    const too_many_pixels = pixels > options.max_pixels;
    return .{
        .path = path,
        .format = dims.format,
        .width = dims.width,
        .height = dims.height,
        .pixels = pixels,
        .bytes = prefix.file_size,
        .base64_bytes = base64_bytes,
        .direct_upload_ok = !too_many_bytes and !too_many_pixels,
        .too_many_bytes = too_many_bytes,
        .too_many_pixels = too_many_pixels,
    };
}

pub fn recommendedPreview(info: ImageInfo, max_edge: u32) PreviewSize {
    if (info.width <= max_edge and info.height <= max_edge) {
        return .{ .width = info.width, .height = info.height, .max_edge = max_edge };
    }
    const longest = @max(info.width, info.height);
    return .{
        .width = @max(1, @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(info.width)) * @as(f64, @floatFromInt(max_edge)) / @as(f64, @floatFromInt(longest)))))),
        .height = @max(1, @as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(info.height)) * @as(f64, @floatFromInt(max_edge)) / @as(f64, @floatFromInt(longest)))))),
        .max_edge = max_edge,
    };
}

pub fn makePreview(process_init: std.process.Init, allocator: std.mem.Allocator, input: []const u8, output: []const u8, options: Options) !void {
    try makeParents(output);
    const resize = try std.fmt.allocPrint(allocator, "{d}x{d}>", .{ options.preview_edge, options.preview_edge });
    defer allocator.free(resize);
    const quality = try std.fmt.allocPrint(allocator, "{d}", .{options.preview_quality});
    defer allocator.free(quality);
    const argv = [_][]const u8{
        "convert",
        input,
        "-auto-orient",
        "-resize",
        resize,
        "-strip",
        "-quality",
        quality,
        output,
    };
    const result = try std.process.run(allocator, process_init.io, .{
        .argv = &argv,
        .stdout_limit = .limited(128 * 1024),
        .stderr_limit = .limited(128 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("preview generation failed for {s}: {s}{s}\n", .{ input, result.stdout, result.stderr });
    return error.PreviewGenerationFailed;
}

pub fn makeParents(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        var cursor: usize = 0;
        if (dir.len > 0 and dir[0] == '/') cursor = 1;
        while (cursor <= dir.len) {
            const slash = std.mem.indexOfScalarPos(u8, dir, cursor, '/') orelse dir.len;
            if (slash > 0) {
                const segment = dir[0..slash];
                const segment_z = try std.heap.page_allocator.dupeZ(u8, segment);
                defer std.heap.page_allocator.free(segment_z);
                _ = c_mkdir(segment_z.ptr, 0o777);
            }
            if (slash == dir.len) break;
            cursor = slash + 1;
        }
    }
}

pub fn writeFile(path: []const u8, bytes: []const u8) !void {
    try makeParents(path);
    const path_z = try std.heap.page_allocator.dupeZ(u8, path);
    defer std.heap.page_allocator.free(path_z);
    const file = c_fopen(path_z.ptr, "wb") orelse return error.FileCreateFailed;
    defer _ = c_fclose(file);
    if (c_fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.FileWriteFailed;
}

pub fn deleteFile(path: []const u8) void {
    const path_z = std.heap.page_allocator.dupeZ(u8, path) catch return;
    defer std.heap.page_allocator.free(path_z);
    _ = c_unlink(path_z.ptr);
}

pub fn formatBytesMib(bytes: u64) f64 {
    return @as(f64, @floatFromInt(bytes)) / 1024.0 / 1024.0;
}

pub fn isImagePath(path: []const u8) bool {
    return endsWithIgnoreCase(path, ".png") or
        endsWithIgnoreCase(path, ".jpg") or
        endsWithIgnoreCase(path, ".jpeg") or
        endsWithIgnoreCase(path, ".webp");
}

pub fn isAnalysisPreview(path: []const u8) bool {
    return endsWithIgnoreCase(path, ".analysis.jpg") or endsWithIgnoreCase(path, ".analysis.jpeg");
}

pub fn writeJsonStringContent(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |byte| switch (byte) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => try writer.writeByte(byte),
    };
}

fn readPrefix(allocator: std.mem.Allocator, path: []const u8, max_prefix: usize) !PrefixRead {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const file = c_fopen(path_z.ptr, "rb") orelse return error.FileNotFound;
    defer _ = c_fclose(file);
    if (c_fseek(file, 0, 2) != 0) return error.FileSeekFailed;
    const end = c_ftell(file);
    if (end < 0) return error.FileTellFailed;
    const size: u64 = @intCast(end);
    if (c_fseek(file, 0, 0) != 0) return error.FileSeekFailed;
    const read_len: usize = @intCast(@min(size, max_prefix));
    const bytes = try allocator.alloc(u8, read_len);
    errdefer allocator.free(bytes);
    if (c_fread(bytes.ptr, 1, read_len, file) != read_len) return error.FileReadFailed;
    return .{ .bytes = bytes, .file_size = size };
}

const Dimensions = struct {
    format: []const u8,
    width: u32,
    height: u32,
};

fn readDimensions(bytes: []const u8, path: []const u8) !Dimensions {
    if (bytes.len >= 24 and std.mem.eql(u8, bytes[0..8], &.{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' })) {
        return .{
            .format = "png",
            .width = readU32Be(bytes[16..20]),
            .height = readU32Be(bytes[20..24]),
        };
    }
    if (bytes.len >= 10 and bytes[0] == 0xff and bytes[1] == 0xd8) {
        var offset: usize = 2;
        while (offset + 9 < bytes.len) {
            if (bytes[offset] != 0xff) break;
            const marker = bytes[offset + 1];
            const length = readU16Be(bytes[offset + 2 .. offset + 4]);
            if (length < 2) break;
            if ((marker >= 0xc0 and marker <= 0xc3) or
                (marker >= 0xc5 and marker <= 0xc7) or
                (marker >= 0xc9 and marker <= 0xcb) or
                (marker >= 0xcd and marker <= 0xcf))
            {
                return .{
                    .format = "jpeg",
                    .width = readU16Be(bytes[offset + 7 .. offset + 9]),
                    .height = readU16Be(bytes[offset + 5 .. offset + 7]),
                };
            }
            offset += 2 + length;
        }
    }
    if (bytes.len >= 30 and std.mem.eql(u8, bytes[0..4], "RIFF") and std.mem.eql(u8, bytes[8..12], "WEBP")) {
        if (readWebpDimensions(bytes)) |dims| return dims;
    }
    std.debug.print("{s}: unsupported or malformed image; supported formats: PNG, JPEG, WEBP\n", .{path});
    return error.UnsupportedImage;
}

fn readWebpDimensions(bytes: []const u8) ?Dimensions {
    const chunk = bytes[12..16];
    if (std.mem.eql(u8, chunk, "VP8X") and bytes.len >= 30) {
        return .{
            .format = "webp",
            .width = 1 + readU24Le(bytes[24..27]),
            .height = 1 + readU24Le(bytes[27..30]),
        };
    }
    if (std.mem.eql(u8, chunk, "VP8 ") and bytes.len >= 30) {
        return .{
            .format = "webp",
            .width = readU16Le(bytes[26..28]) & 0x3fff,
            .height = readU16Le(bytes[28..30]) & 0x3fff,
        };
    }
    if (std.mem.eql(u8, chunk, "VP8L") and bytes.len >= 25) {
        const bits = readU32Le(bytes[21..25]);
        return .{
            .format = "webp",
            .width = 1 + (bits & 0x3fff),
            .height = 1 + ((bits >> 14) & 0x3fff),
        };
    }
    return null;
}

fn readU24Le(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16);
}

fn readU16Be(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | @as(u16, bytes[1]);
}

fn readU16Le(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

fn readU32Be(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

fn readU32Le(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) |
        (@as(u32, bytes[3]) << 24);
}

fn endsWithIgnoreCase(value: []const u8, suffix: []const u8) bool {
    if (value.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(value[value.len - suffix.len ..], suffix);
}

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(file: *anyopaque) c_int;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn fseek(file: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(file: *anyopaque) c_long;
extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern fn unlink(path: [*:0]const u8) c_int;

const c_fopen = fopen;
const c_fclose = fclose;
const c_fread = fread;
const c_fwrite = fwrite;
const c_fseek = fseek;
const c_ftell = ftell;
const c_mkdir = mkdir;
const c_unlink = unlink;
