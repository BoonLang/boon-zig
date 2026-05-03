const std = @import("std");
const builtin = @import("builtin");
const raybox = @import("raybox");
const sdl = @import("sdl");

const physical = raybox.render.physical_projection;

const c = sdl.c;

pub fn writeFramebufferPng(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, path: []const u8, width: usize, height: usize) !void {
    if (builtin.os.tag == .emscripten) return error.FrameCaptureUnsupportedOnWeb;
    if (width == 0 or height == 0) return error.InvalidFramebufferSize;

    var image = try physical.PixelImage.init(allocator, width, height, .{ .r = 0, .g = 0, .b = 0, .a = 1 });
    defer image.deinit();

    const row_bytes = width * 4;
    const surface = c.SDL_RenderReadPixels(renderer, null) orelse return error.FramebufferReadFailed;
    defer c.SDL_DestroySurface(surface);
    const rgba = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_RGBA32) orelse return error.FramebufferConvertFailed;
    defer c.SDL_DestroySurface(rgba);
    if (rgba.*.w <= 0 or rgba.*.h <= 0 or rgba.*.pixels == null) return error.FramebufferReadFailed;
    const source_width: usize = @intCast(rgba.*.w);
    const source_height: usize = @intCast(rgba.*.h);
    if (source_width < width or source_height < height) return error.InvalidFramebufferSize;
    const raw: [*]const u8 = @ptrCast(rgba.*.pixels.?);
    const raw_slice = raw[0 .. @as(usize, @intCast(rgba.*.pitch)) * source_height];
    if (isSolidFramebuffer(raw_slice)) return error.BlankFramebuffer;

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const src_start = y * @as(usize, @intCast(rgba.*.pitch));
        @memcpy(image.pixels[y * row_bytes .. (y + 1) * row_bytes], raw[src_start .. src_start + row_bytes]);
    }

    const png = try physical.pngAlloc(allocator, image);
    defer allocator.free(png);
    try writeFileMakingParents(path, png);
}

fn isSolidFramebuffer(raw: []const u8) bool {
    if (raw.len < 4) return true;
    const r = raw[0];
    const g = raw[1];
    const b = raw[2];
    var index: usize = 4;
    while (index + 2 < raw.len) : (index += 4) {
        if (raw[index] != r or raw[index + 1] != g or raw[index + 2] != b) return false;
    }
    return true;
}

fn writeFileMakingParents(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        try makePath(dir);
    }
    try writeFile(path, bytes);
}

fn makePath(path: []const u8) !void {
    var buf: [1024:0]u8 = undefined;
    if (path.len >= buf.len) return error.PathTooLong;
    for (path, 0..) |byte, i| {
        buf[i] = byte;
        if (byte == '/' and i != 0) {
            buf[i] = 0;
            _ = c_mkdir(buf[0..i :0].ptr, 0o777);
            buf[i] = '/';
        }
    }
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = c_mkdir(buf[0..path.len :0].ptr, 0o777);
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    var path_buf: [1024:0]u8 = undefined;
    if (path.len >= path_buf.len) return error.PathTooLong;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const file = c_fopen(path_buf[0..path.len :0].ptr, "wb") orelse return error.FileCreateFailed;
    defer _ = c_fclose(file);
    if (c_fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.FileWriteFailed;
}

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(file: *anyopaque) c_int;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;

const c_fopen = fopen;
const c_fclose = fclose;
const c_fwrite = fwrite;
const c_mkdir = mkdir;
