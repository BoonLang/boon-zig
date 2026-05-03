const std = @import("std");

const batcher_mod = @import("../render/batcher.zig");

pub const FontId = i32;

pub const AtlasDirtyRect = struct {
    x0: i32 = 0,
    y0: i32 = 0,
    x1: i32 = 0,
    y1: i32 = 0,
};

pub const Backend = struct {
    allocator: std.mem.Allocator,
    context: *FONScontext,
    atlas_width: i32,
    atlas_height: i32,
    atlas_dirty: bool = false,
    dirty_rect: AtlasDirtyRect = .{},
    atlas_rgba: []u8 = &.{},
    active_batch: ?*batcher_mod.Batcher = null,
    active_error: ?anyerror = null,
    draw_vertices: usize = 0,
    last_error: ?FonsError = null,

    pub fn init(allocator: std.mem.Allocator, width: i32, height: i32) !*Backend {
        const backend = try allocator.create(Backend);
        errdefer allocator.destroy(backend);

        backend.* = .{
            .allocator = allocator,
            .context = undefined,
            .atlas_width = width,
            .atlas_height = height,
        };

        var params = FONSparams{
            .width = width,
            .height = height,
            .flags = FONS_ZERO_TOPLEFT,
            .userPtr = backend,
            .renderCreate = renderCreate,
            .renderResize = renderResize,
            .renderUpdate = renderUpdate,
            .renderDraw = renderDraw,
            .renderDelete = renderDelete,
        };

        const context = fonsCreateInternal(&params) orelse return error.FontstashInitFailed;
        backend.context = context;
        fonsSetErrorCallback(context, errorCallback, backend);
        return backend;
    }

    pub fn deinit(self: *Backend) void {
        fonsDeleteInternal(self.context);
        const allocator = self.allocator;
        allocator.free(self.atlas_rgba);
        allocator.destroy(self);
    }

    pub fn addFontBytes(self: *Backend, name: [:0]const u8, bytes: []const u8) !FontId {
        const font = fonsAddFontMem(
            self.context,
            name.ptr,
            @constCast(bytes.ptr),
            @intCast(bytes.len),
            0,
        );
        if (font == FONS_INVALID) return error.FontLoadFailed;
        return font;
    }

    pub fn addFallbackFont(self: *Backend, base: FontId, fallback: FontId) !void {
        if (fonsAddFallbackFont(self.context, base, fallback) == 0) {
            return error.FontFallbackFailed;
        }
    }

    pub fn measure(self: *Backend, text: []const u8, font: FontId, size: f32) Dimensions {
        var bounds = [_]f32{ 0, 0, 0, 0 };
        fonsPushState(self.context);
        defer fonsPopState(self.context);

        fonsSetFont(self.context, font);
        fonsSetSize(self.context, size);
        fonsSetAlign(self.context, FONS_ALIGN_LEFT | FONS_ALIGN_TOP);

        const start = text.ptr;
        const end = text.ptr + text.len;
        const advance = fonsTextBounds(self.context, 0, 0, start, end, &bounds);

        var ascender: f32 = 0;
        var descender: f32 = 0;
        var line_height: f32 = 0;
        fonsVertMetrics(self.context, &ascender, &descender, &line_height);

        return .{
            .width = @max(0, bounds[2] - bounds[0]),
            .height = @max(line_height, bounds[3] - bounds[1]),
            .advance = advance,
        };
    }

    pub fn drawText(self: *Backend, text: []const u8, font: FontId, size: f32, x: f32, y: f32, color_rgba8: u32) void {
        fonsPushState(self.context);
        defer fonsPopState(self.context);

        fonsSetFont(self.context, font);
        fonsSetSize(self.context, size);
        fonsSetColor(self.context, color_rgba8);
        fonsSetAlign(self.context, FONS_ALIGN_LEFT | FONS_ALIGN_TOP);
        _ = fonsDrawText(self.context, x, y, text.ptr, text.ptr + text.len);
    }

    pub fn drawTextIntoBatch(self: *Backend, batch: *batcher_mod.Batcher, text: []const u8, font: FontId, size: f32, x: f32, y: f32, color_rgba8: u32) !void {
        self.active_batch = batch;
        self.active_error = null;
        defer {
            self.active_batch = null;
            self.active_error = null;
        }

        self.drawText(text, font, size, x, y, color_rgba8);
        if (self.active_error) |err| return err;
    }

    pub fn atlasPixels(self: *const Backend) []const u8 {
        return self.atlas_rgba;
    }
};

pub const Dimensions = struct {
    width: f32,
    height: f32,
    advance: f32,
};

pub const FonsError = struct {
    code: i32,
    value: i32,
};

const FONS_INVALID = -1;
const FONS_ZERO_TOPLEFT = 1;
const FONS_ALIGN_LEFT = 1 << 0;
const FONS_ALIGN_TOP = 1 << 3;

const FONScontext = opaque {};

const FONSparams = extern struct {
    width: c_int,
    height: c_int,
    flags: u8,
    userPtr: ?*anyopaque,
    renderCreate: *const fn (?*anyopaque, c_int, c_int) callconv(.c) c_int,
    renderResize: *const fn (?*anyopaque, c_int, c_int) callconv(.c) c_int,
    renderUpdate: *const fn (?*anyopaque, [*c]c_int, [*c]const u8) callconv(.c) void,
    renderDraw: *const fn (?*anyopaque, [*c]const f32, [*c]const f32, [*c]const u32, c_int) callconv(.c) void,
    renderDelete: *const fn (?*anyopaque) callconv(.c) void,
};

extern fn fonsCreateInternal(params: *FONSparams) ?*FONScontext;
extern fn fonsDeleteInternal(context: *FONScontext) void;
extern fn fonsSetErrorCallback(context: *FONScontext, callback: *const fn (?*anyopaque, c_int, c_int) callconv(.c) void, user_ptr: ?*anyopaque) void;
extern fn fonsAddFontMem(context: *FONScontext, name: [*:0]const u8, data: [*]u8, data_size: c_int, free_data: c_int) c_int;
extern fn fonsAddFallbackFont(context: *FONScontext, base: c_int, fallback: c_int) c_int;
extern fn fonsPushState(context: *FONScontext) void;
extern fn fonsPopState(context: *FONScontext) void;
extern fn fonsSetSize(context: *FONScontext, size: f32) void;
extern fn fonsSetColor(context: *FONScontext, color: u32) void;
extern fn fonsSetAlign(context: *FONScontext, alignment: c_int) void;
extern fn fonsSetFont(context: *FONScontext, font: c_int) void;
extern fn fonsDrawText(context: *FONScontext, x: f32, y: f32, string: [*]const u8, end: [*]const u8) f32;
extern fn fonsTextBounds(context: *FONScontext, x: f32, y: f32, string: [*]const u8, end: [*]const u8, bounds: *[4]f32) f32;
extern fn fonsVertMetrics(context: *FONScontext, ascender: *f32, descender: *f32, line_height: *f32) void;

fn fromUserPtr(ptr: ?*anyopaque) *Backend {
    return @ptrCast(@alignCast(ptr.?));
}

fn renderCreate(ptr: ?*anyopaque, width: c_int, height: c_int) callconv(.c) c_int {
    const backend = fromUserPtr(ptr);
    backend.atlas_width = width;
    backend.atlas_height = height;
    const len = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * 4;
    backend.atlas_rgba = backend.allocator.alloc(u8, len) catch return 0;
    @memset(backend.atlas_rgba, 0);
    return 1;
}

fn renderResize(ptr: ?*anyopaque, width: c_int, height: c_int) callconv(.c) c_int {
    const backend = fromUserPtr(ptr);
    const len = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * 4;
    const resized = backend.allocator.realloc(backend.atlas_rgba, len) catch return 0;
    backend.atlas_rgba = resized;
    @memset(backend.atlas_rgba, 0);
    backend.atlas_width = width;
    backend.atlas_height = height;
    backend.atlas_dirty = true;
    backend.dirty_rect = .{ .x0 = 0, .y0 = 0, .x1 = width, .y1 = height };
    return 1;
}

fn renderUpdate(ptr: ?*anyopaque, rect: [*c]c_int, data: [*c]const u8) callconv(.c) void {
    const backend = fromUserPtr(ptr);
    backend.atlas_dirty = true;
    const pixel_count = @as(usize, @intCast(backend.atlas_width)) * @as(usize, @intCast(backend.atlas_height));
    if (backend.atlas_rgba.len >= pixel_count * 4) {
        for (0..pixel_count) |i| {
            const alpha = data[i];
            const out = i * 4;
            backend.atlas_rgba[out + 0] = alpha;
            backend.atlas_rgba[out + 1] = alpha;
            backend.atlas_rgba[out + 2] = alpha;
            backend.atlas_rgba[out + 3] = alpha;
        }
    }
    const update = AtlasDirtyRect{
        .x0 = rect[0],
        .y0 = rect[1],
        .x1 = rect[2],
        .y1 = rect[3],
    };
    if (backend.dirty_rect.x1 <= backend.dirty_rect.x0 or backend.dirty_rect.y1 <= backend.dirty_rect.y0) {
        backend.dirty_rect = update;
    } else {
        backend.dirty_rect = .{
            .x0 = @min(backend.dirty_rect.x0, update.x0),
            .y0 = @min(backend.dirty_rect.y0, update.y0),
            .x1 = @max(backend.dirty_rect.x1, update.x1),
            .y1 = @max(backend.dirty_rect.y1, update.y1),
        };
    }
}

fn renderDraw(ptr: ?*anyopaque, verts: [*c]const f32, tcoords: [*c]const f32, colors: [*c]const u32, nverts: c_int) callconv(.c) void {
    const backend = fromUserPtr(ptr);
    backend.draw_vertices += @intCast(nverts);
    const batch = backend.active_batch orelse return;
    var i: usize = 0;
    while (i < @as(usize, @intCast(nverts))) : (i += 1) {
        const index = batch.addVertex(.{
            .pos = .{ verts[i * 2 + 0], verts[i * 2 + 1] },
            .uv = .{ tcoords[i * 2 + 0], tcoords[i * 2 + 1] },
            .color = colors[i],
        }) catch |err| {
            backend.active_error = err;
            return;
        };
        batch.addIndex(index) catch |err| {
            backend.active_error = err;
            return;
        };
    }
}

fn renderDelete(ptr: ?*anyopaque) callconv(.c) void {
    _ = ptr;
}

fn errorCallback(ptr: ?*anyopaque, error_code: c_int, value: c_int) callconv(.c) void {
    const backend = fromUserPtr(ptr);
    backend.last_error = .{ .code = error_code, .value = value };
}
