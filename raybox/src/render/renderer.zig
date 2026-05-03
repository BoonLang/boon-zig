const geometry = @import("geometry.zig");
const colors = @import("colors.zig");

pub const StableId = u64;

pub const CustomKind = enum(u32) {
    shadow,
    inner_shadow,
    cutout_rounded_rect,
    bevel,
    glow,
    outline,
    caret,
    selection,
    svg_circle,
    svg_path,
};

pub const RenderTraceCommand = struct {
    node_id: StableId,
    kind: CustomKind,
    rect: geometry.Rect,
    radius: geometry.CornerRadius,
    color: colors.ColorPremul,
    z: f32 = 0,
    blur_radius: f32 = 0,
    spread: f32 = 0,
    offset: geometry.Vec2 = .{},
    alpha: f32 = 1,
    outline_width: f32 = 0,
    icon_name: ?[]const u8 = null,
};
