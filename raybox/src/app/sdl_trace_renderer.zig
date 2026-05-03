const std = @import("std");
const raybox = @import("raybox");
const sdl = @import("sdl");

const batcher_mod = raybox.render.batcher;
const clay_bridge = raybox.clay.bridge;
const colors = raybox.render.colors;
const geometry = raybox.render.geometry;
const physical = raybox.render.physical_projection;
const font_manager = raybox.text.font_manager;

const c = sdl.c;

const max_vertices = 65536;
const max_indices = 131072;

pub const TraceRenderer = struct {
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    glyph_texture: ?*c.SDL_Texture = null,
    glyph_width: i32 = 0,
    glyph_height: i32 = 0,
    batch: batcher_mod.Batcher,
    text_batch: batcher_mod.Batcher,
    overlay_batch: batcher_mod.Batcher,
    sdl_vertices: std.ArrayListUnmanaged(c.SDL_Vertex) = .empty,
    sdl_indices: std.ArrayListUnmanaged(c_int) = .empty,

    pub fn init(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, fonts: ?*font_manager.FontManager) TraceRenderer {
        _ = fonts;
        return .{
            .allocator = allocator,
            .renderer = renderer,
            .batch = batcher_mod.Batcher.init(allocator),
            .text_batch = batcher_mod.Batcher.init(allocator),
            .overlay_batch = batcher_mod.Batcher.init(allocator),
        };
    }

    pub fn deinit(self: *TraceRenderer) void {
        self.sdl_indices.deinit(self.allocator);
        self.sdl_vertices.deinit(self.allocator);
        if (self.glyph_texture) |texture| c.SDL_DestroyTexture(texture);
        self.overlay_batch.deinit();
        self.text_batch.deinit();
        self.batch.deinit();
        self.* = undefined;
    }

    pub fn render(self: *TraceRenderer, trace: physical.RenderTrace, framebuffer_width: f32, framebuffer_height: f32) !void {
        self.batch.clearRetainingCapacity();
        self.text_batch.clearRetainingCapacity();
        self.overlay_batch.clearRetainingCapacity();
        try self.emitTrace(trace, .{ .x = 0, .y = 0, .w = framebuffer_width, .h = framebuffer_height }, null);
        try self.flush(framebuffer_width, framebuffer_height);
    }

    pub fn renderInRect(self: *TraceRenderer, trace: physical.RenderTrace, fonts: ?*font_manager.FontManager, rect: geometry.Rect, framebuffer_width: f32, framebuffer_height: f32) !void {
        self.batch.clearRetainingCapacity();
        self.text_batch.clearRetainingCapacity();
        self.overlay_batch.clearRetainingCapacity();
        try self.emitTrace(trace, rect, fonts);
        try self.flush(framebuffer_width, framebuffer_height);
        if (fonts) |font_ptr| try self.flushText(font_ptr, framebuffer_width, framebuffer_height);
        try self.flushOverlay(framebuffer_width, framebuffer_height);
    }

    pub fn renderClay(self: *TraceRenderer, commands: clay_bridge.c.Clay_RenderCommandArray, fonts: *font_manager.FontManager, framebuffer_width: f32, framebuffer_height: f32) !void {
        self.batch.clearRetainingCapacity();
        self.text_batch.clearRetainingCapacity();
        self.overlay_batch.clearRetainingCapacity();
        try self.emitClay(commands, fonts);
        try self.flush(framebuffer_width, framebuffer_height);
        try self.flushText(fonts, framebuffer_width, framebuffer_height);
    }

    fn flush(self: *TraceRenderer, framebuffer_width: f32, framebuffer_height: f32) !void {
        _ = framebuffer_width;
        _ = framebuffer_height;
        if (self.batch.vertices.items.len == 0 or self.batch.indices.items.len == 0) return;
        if (self.batch.vertices.items.len > max_vertices) return error.VertexCapacityExceeded;
        if (self.batch.indices.items.len > max_indices) return error.IndexCapacityExceeded;
        try self.flushBatch(&self.batch, null);
    }

    fn flushOverlay(self: *TraceRenderer, framebuffer_width: f32, framebuffer_height: f32) !void {
        _ = framebuffer_width;
        _ = framebuffer_height;
        if (self.overlay_batch.vertices.items.len == 0 or self.overlay_batch.indices.items.len == 0) return;
        if (self.overlay_batch.vertices.items.len > max_vertices) return error.VertexCapacityExceeded;
        if (self.overlay_batch.indices.items.len > max_indices) return error.IndexCapacityExceeded;
        try self.flushBatch(&self.overlay_batch, null);
    }

    fn emitTrace(self: *TraceRenderer, trace: physical.RenderTrace, target: geometry.Rect, fonts: ?*font_manager.FontManager) !void {
        try geometry.emitRect(&self.batch, target, trace.backgroundColor());

        const source_w = @as(f32, @floatFromInt(trace.viewport.width));
        const source_h = @as(f32, @floatFromInt(trace.viewport.height));
        const scale = @min(target.w / source_w, target.h / source_h);
        const origin = geometry.Vec2{
            .x = target.x + (target.w - source_w * scale) * 0.5,
            .y = target.y + (target.h - source_h * scale) * 0.5,
        };

        for (trace.commands) |command| {
            const base = command.base;
            const rect = mapRect(offsetRect(base.rect, base.offset), origin, scale);
            const radius = geometry.CornerRadius.uniform(base.radius.top_left * scale);
            switch (base.kind) {
                .shadow, .cutout_rounded_rect, .bevel, .glow, .caret, .selection => {
                    try geometry.emitRoundedRect(&self.batch, rect, radius, base.color);
                },
                .svg_circle => {
                    const width = @max(1.0, (if (base.outline_width > 0) base.outline_width else 2.0) * scale);
                    try geometry.emitBorder(&self.batch, rect, geometry.CornerRadius.uniform(rect.w * 0.5), .{ .left = width, .top = width, .right = width, .bottom = width }, base.color);
                },
                .svg_path => {
                    const width = @max(2.0, (if (base.outline_width > 0) base.outline_width else 3.0) * scale);
                    const a = geometry.Vec2{ .x = rect.x + rect.w * 0.24, .y = rect.y + rect.h * 0.55 };
                    const b = geometry.Vec2{ .x = rect.x + rect.w * 0.44, .y = rect.y + rect.h * 0.74 };
                    const check_c = geometry.Vec2{ .x = rect.x + rect.w * 0.78, .y = rect.y + rect.h * 0.28 };
                    try geometry.emitLine(&self.batch, a, b, width, base.color);
                    try geometry.emitLine(&self.batch, b, check_c, width, base.color);
                },
                .inner_shadow, .outline => {
                    const width = @max(1.0, (if (base.outline_width > 0) base.outline_width else 2.0) * scale);
                    try geometry.emitBorder(&self.batch, rect, radius, .{ .left = width, .top = width, .right = width, .bottom = width }, base.color);
                },
            }
            if (fonts) |font_ptr| {
                try self.emitTraceLabel(font_ptr, command, rect, scale);
            }
        }
    }

    fn emitTraceLabel(self: *TraceRenderer, fonts: *font_manager.FontManager, command: physical.TraceCommand, rect: geometry.Rect, scale: f32) !void {
        const kind = command.base.kind;
        const font = fonts.coreFont(.inter);
        const color = colors.ColorPremul.rgba(0.12, 0.14, 0.17, 1);
        if (std.mem.eql(u8, command.role, "terminal_text")) {
            if (command.label.len == 0) return;
            if (kind != .bevel) return;
            try self.drawMultiline(fonts, command.label, .{ .x = rect.x, .y = rect.y }, @max(18, command.text_size * scale), colors.ColorPremul.rgba(0.10, 0.12, 0.15, 1));
        } else if (std.mem.eql(u8, command.role, "plain_text")) {
            if (command.label.len == 0) return;
            if (kind != .bevel) return;
            try fonts.drawIntoBatch(&self.text_batch, command.label, .{ .x = rect.x, .y = rect.y }, .{
                .font = font,
                .size = @max(14, command.text_size * scale),
                .color = color,
            });
        } else if (std.mem.eql(u8, command.role, "title_text")) {
            if (command.label.len == 0) return;
            if (kind != .bevel) return;
            try fonts.drawIntoBatch(&self.text_batch, command.label, .{ .x = rect.x + 12 * scale, .y = rect.y + 4 * scale }, .{
                .font = font,
                .size = @max(30, command.text_size * scale * 0.82),
                .color = color,
            });
        } else if (std.mem.eql(u8, command.role, "button")) {
            if (command.label.len == 0) return;
            if (kind != .bevel) return;
            const size = if (command.text_size > 0) @max(15, command.text_size * scale) else @max(14, @min(20 * scale, rect.h * 0.48));
            try fonts.drawIntoBatch(&self.text_batch, command.label, .{ .x = rect.x + 14 * scale, .y = rect.y + @max(8, (rect.h - size) * 0.48) }, .{
                .font = font,
                .size = size,
                .color = color,
            });
        } else if (std.mem.eql(u8, command.role, "text_input")) {
            if (kind != .bevel) return;
            const size = if (command.text_size > 0) @max(16, command.text_size * scale) else @max(15, @min(22 * scale, rect.h * 0.48));
            const pos = geometry.Vec2{ .x = rect.x + 22 * scale, .y = rect.y + @max(12, (rect.h - size) * 0.48) };
            const input_color = colors.ColorPremul.rgba(0.24, 0.27, 0.32, 1);
            if (command.label.len != 0) {
                try fonts.drawIntoBatch(&self.text_batch, command.label, pos, .{
                    .font = font,
                    .size = size,
                    .color = input_color,
                });
            }
            if (command.caret_visible) {
                const measured = fonts.measure(command.caret_text, font, size);
                const caret_x = @min(rect.x + rect.w - 22 * scale, pos.x + measured.advance);
                try geometry.emitRect(&self.overlay_batch, .{
                    .x = caret_x,
                    .y = pos.y,
                    .w = @max(1, 2 * scale),
                    .h = @max(size, measured.height),
                }, colors.ColorPremul.rgba(0.08, 0.09, 0.11, 1));
            }
        } else if (std.mem.eql(u8, command.role, "checkbox")) {
            if (command.label.len == 0) return;
            if (kind != .svg_circle) return;
            try fonts.drawIntoBatch(&self.text_batch, command.label, .{ .x = rect.x + rect.w + 12 * scale, .y = rect.y + 2 * scale }, .{
                .font = font,
                .size = @max(15, 18 * scale),
                .color = color,
            });
        }
    }

    fn drawMultiline(self: *TraceRenderer, fonts: *font_manager.FontManager, text_bytes: []const u8, origin: geometry.Vec2, size: f32, color: colors.ColorPremul) !void {
        const font = fonts.coreFont(.mono);
        var y = origin.y;
        var cursor: usize = 0;
        while (cursor <= text_bytes.len) {
            const next = std.mem.indexOfScalarPos(u8, text_bytes, cursor, '\n') orelse text_bytes.len;
            const line = text_bytes[cursor..next];
            if (line.len != 0) {
                try fonts.drawIntoBatch(&self.text_batch, line, .{ .x = origin.x, .y = y }, .{
                    .font = font,
                    .size = size,
                    .color = color,
                });
            }
            if (next == text_bytes.len) break;
            y += size * 1.32;
            cursor = next + 1;
        }
    }

    fn flushText(self: *TraceRenderer, fonts: *font_manager.FontManager, framebuffer_width: f32, framebuffer_height: f32) !void {
        _ = framebuffer_width;
        _ = framebuffer_height;
        if (self.text_batch.vertices.items.len == 0 or self.text_batch.indices.items.len == 0) return;
        if (self.text_batch.vertices.items.len > max_vertices) return error.VertexCapacityExceeded;
        if (self.text_batch.indices.items.len > max_indices) return error.IndexCapacityExceeded;
        try self.ensureGlyphTexture(fonts);
        try self.flushBatch(&self.text_batch, self.glyph_texture);
    }

    fn ensureGlyphTexture(self: *TraceRenderer, fonts: *font_manager.FontManager) !void {
        const atlas_size = fonts.atlasSize();
        if (self.glyph_texture == null or self.glyph_width != atlas_size.width or self.glyph_height != atlas_size.height) {
            if (self.glyph_texture) |texture| c.SDL_DestroyTexture(texture);
            const texture = c.SDL_CreateTexture(
                self.renderer,
                c.SDL_PIXELFORMAT_RGBA32,
                c.SDL_TEXTUREACCESS_STREAMING,
                @max(1, atlas_size.width),
                @max(1, atlas_size.height),
            ) orelse return error.GlyphTextureCreateFailed;
            _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND_PREMULTIPLIED);
            _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_LINEAR);
            self.glyph_texture = texture;
            self.glyph_width = atlas_size.width;
            self.glyph_height = atlas_size.height;
            fonts.markAtlasClean();
            const pixels = fonts.atlasPixels();
            if (!c.SDL_UpdateTexture(texture, null, pixels.ptr, @intCast(@max(1, atlas_size.width) * 4))) {
                return error.GlyphTextureUpdateFailed;
            }
            return;
        }
        if (fonts.atlasDirty()) {
            const texture = self.glyph_texture orelse return error.GlyphTextureMissing;
            const pixels = fonts.atlasPixels();
            if (!c.SDL_UpdateTexture(texture, null, pixels.ptr, @intCast(@max(1, self.glyph_width) * 4))) {
                return error.GlyphTextureUpdateFailed;
            }
            fonts.markAtlasClean();
        }
    }

    fn flushBatch(self: *TraceRenderer, batch: *const batcher_mod.Batcher, texture: ?*c.SDL_Texture) !void {
        self.sdl_vertices.clearRetainingCapacity();
        self.sdl_indices.clearRetainingCapacity();
        try self.sdl_vertices.ensureTotalCapacity(self.allocator, batch.vertices.items.len);
        try self.sdl_indices.ensureTotalCapacity(self.allocator, batch.indices.items.len);
        for (batch.vertices.items) |vertex| {
            self.sdl_vertices.appendAssumeCapacity(.{
                .position = .{ .x = vertex.pos[0], .y = vertex.pos[1] },
                .color = colorFromPacked(vertex.color),
                .tex_coord = .{ .x = vertex.uv[0], .y = vertex.uv[1] },
            });
        }
        for (batch.indices.items) |index| {
            self.sdl_indices.appendAssumeCapacity(@intCast(index));
        }
        if (!c.SDL_RenderGeometry(
            self.renderer,
            texture,
            self.sdl_vertices.items.ptr,
            @intCast(self.sdl_vertices.items.len),
            self.sdl_indices.items.ptr,
            @intCast(self.sdl_indices.items.len),
        )) return error.RenderGeometryFailed;
    }

    fn emitClay(self: *TraceRenderer, commands: clay_bridge.c.Clay_RenderCommandArray, fonts: *font_manager.FontManager) !void {
        var index: i32 = 0;
        while (index < commands.length) : (index += 1) {
            const command = commands.internalArray[@intCast(index)];
            const rect = clay_bridge.boundingRect(command.boundingBox);
            switch (command.commandType) {
                clay_bridge.c.CLAY_RENDER_COMMAND_TYPE_RECTANGLE => {
                    const color = clay_bridge.colorPremul(command.renderData.rectangle.backgroundColor);
                    if (color.a > 0) try geometry.emitRoundedRect(&self.batch, rect, clayRadius(command.renderData.rectangle.cornerRadius), color);
                },
                clay_bridge.c.CLAY_RENDER_COMMAND_TYPE_BORDER => {
                    const width = command.renderData.border.width;
                    try geometry.emitBorder(
                        &self.batch,
                        rect,
                        clayRadius(command.renderData.border.cornerRadius),
                        .{
                            .left = @floatFromInt(width.left),
                            .top = @floatFromInt(width.top),
                            .right = @floatFromInt(width.right),
                            .bottom = @floatFromInt(width.bottom),
                        },
                        clay_bridge.colorPremul(command.renderData.border.color),
                    );
                },
                clay_bridge.c.CLAY_RENDER_COMMAND_TYPE_TEXT => {
                    const text_data = command.renderData.text;
                    const text_slice = text_data.stringContents.chars[0..@intCast(text_data.stringContents.length)];
                    const font = if (text_data.fontId == 1) fonts.coreFont(.mono) else fonts.coreFont(.inter);
                    try fonts.drawIntoBatch(&self.text_batch, text_slice, .{ .x = rect.x, .y = rect.y }, .{
                        .font = font,
                        .size = @floatFromInt(text_data.fontSize),
                        .color = clay_bridge.colorPremul(text_data.textColor),
                    });
                },
                else => {},
            }
        }
    }
};

fn clayRadius(radius: clay_bridge.c.Clay_CornerRadius) geometry.CornerRadius {
    return .{
        .top_left = radius.topLeft,
        .top_right = radius.topRight,
        .bottom_left = radius.bottomLeft,
        .bottom_right = radius.bottomRight,
    };
}

fn colorFromPacked(value: u32) c.SDL_FColor {
    const r: f32 = @floatFromInt(value & 0xff);
    const g: f32 = @floatFromInt((value >> 8) & 0xff);
    const b: f32 = @floatFromInt((value >> 16) & 0xff);
    const a: f32 = @floatFromInt((value >> 24) & 0xff);
    return .{
        .r = r / 255.0,
        .g = g / 255.0,
        .b = b / 255.0,
        .a = a / 255.0,
    };
}

fn offsetRect(rect: geometry.Rect, offset: geometry.Vec2) geometry.Rect {
    return .{ .x = rect.x + offset.x, .y = rect.y + offset.y, .w = rect.w, .h = rect.h };
}

fn mapRect(rect: geometry.Rect, origin: geometry.Vec2, scale: f32) geometry.Rect {
    return .{
        .x = origin.x + rect.x * scale,
        .y = origin.y + rect.y * scale,
        .w = rect.w * scale,
        .h = rect.h * scale,
    };
}
