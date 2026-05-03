const std = @import("std");
const raybox = @import("raybox");
const font_manager = raybox.text.font_manager;

pub fn run(allocator: std.mem.Allocator) !Report {
    var fonts = try font_manager.FontManager.init(allocator);
    defer fonts.deinit();

    const czech = "Příliš žluťoučký kůň úpěl ďábelské ódy.";
    const inter = fonts.coreFont(.inter);
    const mono = fonts.coreFont(.mono);
    const noto = fonts.coreFont(.noto);

    const czech_dims = fonts.measure(czech, inter, 18);
    try expectRange("czech width", czech_dims.width, 200, 700);
    try expectRange("czech height", czech_dims.height, 12, 40);
    if (czech_dims.advance <= 0) return error.TextAdvanceNotPositive;

    const mono_dims = fonts.measure("0123456789", mono, 16);
    try expectRange("mono width", mono_dims.width, 60, 140);

    const fallback_dims = fonts.measure("Raybox text fallback", noto, 15);
    try expectRange("fallback width", fallback_dims.width, 100, 260);

    const draw_vertices_before = fonts.stash.draw_vertices;
    fonts.draw(czech, .{ .x = 8, .y = 24 }, .{
        .font = inter,
        .size = 18,
    });
    if (fonts.stash.draw_vertices <= draw_vertices_before) return error.NoTextVerticesDrawn;
    if (!fonts.atlasDirty()) return error.GlyphAtlasNotDirty;

    return .{
        .czech_width = czech_dims.width,
        .czech_height = czech_dims.height,
        .mono_width = mono_dims.width,
        .draw_vertices = fonts.stash.draw_vertices - draw_vertices_before,
        .atlas_width = fonts.stash.atlas_width,
        .atlas_height = fonts.stash.atlas_height,
    };
}

pub const Report = struct {
    czech_width: f32,
    czech_height: f32,
    mono_width: f32,
    draw_vertices: usize,
    atlas_width: i32,
    atlas_height: i32,
};

fn expectRange(label: []const u8, value: f32, min: f32, max: f32) !void {
    if (value < min or value > max) {
        std.debug.print("{s}: value {d:.3} outside [{d:.3}, {d:.3}]\n", .{ label, value, min, max });
        return error.TextMetricOutOfRange;
    }
}
