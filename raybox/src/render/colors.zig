const std = @import("std");

pub const ColorPremul = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) ColorPremul {
        const alpha = clamp01(a);
        return .{
            .r = clamp01(r) * alpha,
            .g = clamp01(g) * alpha,
            .b = clamp01(b) * alpha,
            .a = alpha,
        };
    }

    pub fn packRgba8(self: ColorPremul) u32 {
        const r: u32 = @intFromFloat(@round(clamp01(self.r) * 255.0));
        const g: u32 = @intFromFloat(@round(clamp01(self.g) * 255.0));
        const b: u32 = @intFromFloat(@round(clamp01(self.b) * 255.0));
        const a: u32 = @intFromFloat(@round(clamp01(self.a) * 255.0));
        return r | (g << 8) | (b << 16) | (a << 24);
    }
};

fn clamp01(value: f32) f32 {
    return @min(1.0, @max(0.0, value));
}

test "colors premultiply before packing" {
    const c = ColorPremul.rgba(1, 0.5, 0.25, 0.5);
    try std.testing.expectEqual(@as(u32, 0x807F4080), c.packRgba8());
}
