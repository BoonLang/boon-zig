const font_manager = @import("font_manager.zig");

pub const Dimensions = font_manager.Dimensions;
pub const FontId = font_manager.FontId;

pub fn measureText(
    fonts: *font_manager.FontManager,
    text: []const u8,
    font: FontId,
    size: f32,
) Dimensions {
    return fonts.measure(text, font, size);
}
