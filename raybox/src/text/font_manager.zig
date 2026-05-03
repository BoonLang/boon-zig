const std = @import("std");

const colors = @import("../render/colors.zig");
const geometry = @import("../render/geometry.zig");
const batcher_mod = @import("../render/batcher.zig");
const fontstash = @import("fontstash_backend.zig");

pub const FontId = fontstash.FontId;
pub const Dimensions = fontstash.Dimensions;

pub const CoreFont = enum {
    inter,
    mono,
    noto,
};

pub const AtlasSize = struct {
    width: i32,
    height: i32,
};

pub const TextStyle = struct {
    font: FontId,
    size: f32,
    color: colors.ColorPremul = colors.ColorPremul.rgba(1, 1, 1, 1),
    underline: bool = false,
    strikethrough: bool = false,
    selection: ?geometry.Rect = null,
    caret_x: ?f32 = null,
};

pub const FontManager = struct {
    allocator: std.mem.Allocator,
    stash: *fontstash.Backend,
    fonts: std.StringHashMap(FontId),
    core: CoreFonts,

    pub fn init(allocator: std.mem.Allocator) !FontManager {
        var manager = FontManager{
            .allocator = allocator,
            .stash = try fontstash.Backend.init(allocator, 1024, 1024),
            .fonts = std.StringHashMap(FontId).init(allocator),
            .core = undefined,
        };
        errdefer manager.deinit();

        const inter = try manager.loadFontBytes("Inter", inter_regular);
        const mono = try manager.loadFontBytes("JetBrains Mono", jetbrains_mono_regular);
        const noto = try manager.loadFontBytes("Noto Sans", noto_sans_regular);

        try manager.stash.addFallbackFont(inter, noto);
        try manager.stash.addFallbackFont(mono, noto);

        manager.core = .{
            .inter = inter,
            .mono = mono,
            .noto = noto,
        };
        return manager;
    }

    pub fn deinit(self: *FontManager) void {
        self.fonts.deinit();
        self.stash.deinit();
        self.* = undefined;
    }

    pub fn loadFontBytes(self: *FontManager, name: []const u8, bytes: []const u8) !FontId {
        var name_buffer: [128:0]u8 = undefined;
        if (name.len >= name_buffer.len) return error.FontNameTooLong;
        @memcpy(name_buffer[0..name.len], name);
        name_buffer[name.len] = 0;

        const font = try self.stash.addFontBytes(name_buffer[0..name.len :0], bytes);
        try self.fonts.put(name, font);
        return font;
    }

    pub fn requestFont(self: *FontManager, path: []const u8, name: []const u8) void {
        _ = self;
        _ = path;
        _ = name;
    }

    pub fn coreFont(self: *const FontManager, font: CoreFont) FontId {
        return switch (font) {
            .inter => self.core.inter,
            .mono => self.core.mono,
            .noto => self.core.noto,
        };
    }

    pub fn measure(self: *FontManager, text: []const u8, font: FontId, size: f32) Dimensions {
        return self.stash.measure(text, font, size);
    }

    pub fn draw(self: *FontManager, text: []const u8, pos: geometry.Vec2, style: TextStyle) void {
        self.stash.drawText(text, style.font, style.size, pos.x, pos.y, style.color.packRgba8());
    }

    pub fn drawIntoBatch(self: *FontManager, batch: *batcher_mod.Batcher, text: []const u8, pos: geometry.Vec2, style: TextStyle) !void {
        if (style.selection) |selection| {
            try geometry.emitRect(batch, selection, colors.ColorPremul.rgba(0.18, 0.42, 0.86, 0.35));
        }
        try self.stash.drawTextIntoBatch(batch, text, style.font, style.size, pos.x, pos.y, style.color.packRgba8());
        if (style.underline or style.strikethrough or style.caret_x != null) {
            const dims = self.measure(text, style.font, style.size);
            if (style.underline) {
                try geometry.emitRect(batch, .{ .x = pos.x, .y = pos.y + dims.height - 2.0, .w = dims.width, .h = 1.0 }, style.color);
            }
            if (style.strikethrough) {
                try geometry.emitRect(batch, .{ .x = pos.x, .y = pos.y + dims.height * 0.55, .w = dims.width, .h = 1.0 }, style.color);
            }
            if (style.caret_x) |caret_x| {
                try geometry.emitRect(batch, .{ .x = caret_x, .y = pos.y, .w = 1.0, .h = dims.height }, style.color);
            }
        }
    }

    pub fn atlasDirty(self: *const FontManager) bool {
        return self.stash.atlas_dirty;
    }

    pub fn atlasPixels(self: *const FontManager) []const u8 {
        return self.stash.atlasPixels();
    }

    pub fn atlasSize(self: *const FontManager) AtlasSize {
        return .{ .width = self.stash.atlas_width, .height = self.stash.atlas_height };
    }

    pub fn markAtlasClean(self: *FontManager) void {
        self.stash.atlas_dirty = false;
        self.stash.dirty_rect = .{};
    }
};

const CoreFonts = struct {
    inter: FontId,
    mono: FontId,
    noto: FontId,
};

const inter_regular = @embedFile("../../assets/fonts/Inter-Regular.ttf");
const jetbrains_mono_regular = @embedFile("../../assets/fonts/JetBrainsMono-Regular.ttf");
const noto_sans_regular = @embedFile("../../assets/fonts/NotoSans-Regular.ttf");

test "FontManager measures the required Czech UTF-8 string through FontStash" {
    var fonts = try FontManager.init(std.testing.allocator);
    defer fonts.deinit();

    const text = "Příliš žluťoučký kůň úpěl ďábelské ódy.";
    const dims = fonts.measure(text, fonts.coreFont(.inter), 18);
    try std.testing.expect(dims.width > 200);
    try std.testing.expect(dims.height > 10);
    try std.testing.expect(dims.advance >= dims.width);
    try std.testing.expect(fonts.atlasDirty());
}
