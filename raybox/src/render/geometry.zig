const std = @import("std");

const batcher_mod = @import("batcher.zig");
const colors = @import("colors.zig");

pub const Batcher = batcher_mod.Batcher;
pub const ColorPremul = colors.ColorPremul;

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn right(self: Rect) f32 {
        return self.x + self.w;
    }

    pub fn bottom(self: Rect) f32 {
        return self.y + self.h;
    }
};

pub const CornerRadius = struct {
    top_left: f32 = 0,
    top_right: f32 = 0,
    bottom_right: f32 = 0,
    bottom_left: f32 = 0,

    pub fn uniform(radius: f32) CornerRadius {
        return .{
            .top_left = radius,
            .top_right = radius,
            .bottom_right = radius,
            .bottom_left = radius,
        };
    }
};

pub const BorderWidth = struct {
    left: f32 = 0,
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
};

pub fn emitRect(batch: *Batcher, rect: Rect, color: ColorPremul) !void {
    try emitQuad(batch, rect, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, color);
}

pub fn emitImageQuad(batch: *Batcher, rect: Rect, uv: Rect, color: ColorPremul) !void {
    const uv0 = Vec2{ .x = uv.x, .y = uv.y };
    const uv1 = Vec2{ .x = uv.x + uv.w, .y = uv.y + uv.h };
    try emitQuad(batch, rect, uv0, uv1, color);
}

pub fn emitLine(batch: *Batcher, a: Vec2, b: Vec2, width: f32, color: ColorPremul) !void {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len <= 0.001) return;
    const half = width * 0.5;
    const nx = -dy / len * half;
    const ny = dx / len * half;
    const packed_color = color.packRgba8();
    const base = try batch.addVertex(.{ .pos = .{ a.x + nx, a.y + ny }, .uv = .{ 0, 0 }, .color = packed_color });
    _ = try batch.addVertex(.{ .pos = .{ b.x + nx, b.y + ny }, .uv = .{ 0, 0 }, .color = packed_color });
    _ = try batch.addVertex(.{ .pos = .{ b.x - nx, b.y - ny }, .uv = .{ 0, 0 }, .color = packed_color });
    _ = try batch.addVertex(.{ .pos = .{ a.x - nx, a.y - ny }, .uv = .{ 0, 0 }, .color = packed_color });
    try batch.addIndex(base + 0);
    try batch.addIndex(base + 1);
    try batch.addIndex(base + 2);
    try batch.addIndex(base + 0);
    try batch.addIndex(base + 2);
    try batch.addIndex(base + 3);
}

pub fn emitRoundedRect(batch: *Batcher, rect: Rect, radius: CornerRadius, color: ColorPremul) !void {
    const segments_per_corner = 12;
    const max_radius = @min(rect.w, rect.h) * 0.5;
    const radii = [_]f32{
        @min(radius.top_right, max_radius),
        @min(radius.bottom_right, max_radius),
        @min(radius.bottom_left, max_radius),
        @min(radius.top_left, max_radius),
    };
    if (radii[0] == 0 and radii[1] == 0 and radii[2] == 0 and radii[3] == 0) {
        return emitRect(batch, rect, color);
    }

    const packed_color = color.packRgba8();
    const center_index = try batch.addVertex(.{
        .pos = .{ rect.x + rect.w * 0.5, rect.y + rect.h * 0.5 },
        .uv = .{ 0, 0 },
        .color = packed_color,
    });

    var ring = std.ArrayListUnmanaged(u32).empty;
    defer ring.deinit(batch.allocator);

    const centers = [_]Vec2{
        .{ .x = rect.right() - radii[0], .y = rect.y + radii[0] },
        .{ .x = rect.right() - radii[1], .y = rect.bottom() - radii[1] },
        .{ .x = rect.x + radii[2], .y = rect.bottom() - radii[2] },
        .{ .x = rect.x + radii[3], .y = rect.y + radii[3] },
    };
    const starts = [_]f32{ -std.math.pi / 2.0, 0, std.math.pi / 2.0, std.math.pi };

    for (0..4) |corner| {
        const r = radii[corner];
        for (0..segments_per_corner + 1) |step| {
            if (corner != 0 and step == 0) continue;
            const t = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(segments_per_corner));
            const angle = starts[corner] + t * (std.math.pi / 2.0);
            const pos = if (r == 0)
                cornerPoint(rect, corner)
            else
                Vec2{
                    .x = centers[corner].x + @cos(angle) * r,
                    .y = centers[corner].y + @sin(angle) * r,
                };
            const idx = try batch.addVertex(.{
                .pos = .{ pos.x, pos.y },
                .uv = .{ 0, 0 },
                .color = packed_color,
            });
            try ring.append(batch.allocator, idx);
        }
    }

    for (ring.items, 0..) |idx, i| {
        const next = ring.items[(i + 1) % ring.items.len];
        try batch.addIndex(center_index);
        try batch.addIndex(idx);
        try batch.addIndex(next);
    }
}

pub fn emitBorder(batch: *Batcher, rect: Rect, radius: CornerRadius, width: BorderWidth, color: ColorPremul) !void {
    _ = radius;
    if (width.top > 0) {
        try emitRect(batch, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = width.top }, color);
    }
    if (width.bottom > 0) {
        try emitRect(batch, .{ .x = rect.x, .y = rect.bottom() - width.bottom, .w = rect.w, .h = width.bottom }, color);
    }
    if (width.left > 0) {
        try emitRect(batch, .{ .x = rect.x, .y = rect.y + width.top, .w = width.left, .h = rect.h - width.top - width.bottom }, color);
    }
    if (width.right > 0) {
        try emitRect(batch, .{ .x = rect.right() - width.right, .y = rect.y + width.top, .w = width.right, .h = rect.h - width.top - width.bottom }, color);
    }
}

pub fn emitCutoutRoundedRect(
    batch: *Batcher,
    outer: Rect,
    inner: Rect,
    outer_radius: CornerRadius,
    inner_radius: CornerRadius,
    color: ColorPremul,
) !void {
    _ = outer_radius;
    _ = inner_radius;
    try emitRect(batch, .{ .x = outer.x, .y = outer.y, .w = outer.w, .h = inner.y - outer.y }, color);
    try emitRect(batch, .{ .x = outer.x, .y = inner.bottom(), .w = outer.w, .h = outer.bottom() - inner.bottom() }, color);
    try emitRect(batch, .{ .x = outer.x, .y = inner.y, .w = inner.x - outer.x, .h = inner.h }, color);
    try emitRect(batch, .{ .x = inner.right(), .y = inner.y, .w = outer.right() - inner.right(), .h = inner.h }, color);
}

fn emitQuad(batch: *Batcher, rect: Rect, uv0: Vec2, uv1: Vec2, color: ColorPremul) !void {
    const packed_color = color.packRgba8();
    const base = try batch.addVertex(.{ .pos = .{ rect.x, rect.y }, .uv = .{ uv0.x, uv0.y }, .color = packed_color });
    _ = try batch.addVertex(.{ .pos = .{ rect.right(), rect.y }, .uv = .{ uv1.x, uv0.y }, .color = packed_color });
    _ = try batch.addVertex(.{ .pos = .{ rect.right(), rect.bottom() }, .uv = .{ uv1.x, uv1.y }, .color = packed_color });
    _ = try batch.addVertex(.{ .pos = .{ rect.x, rect.bottom() }, .uv = .{ uv0.x, uv1.y }, .color = packed_color });
    try batch.addIndex(base + 0);
    try batch.addIndex(base + 1);
    try batch.addIndex(base + 2);
    try batch.addIndex(base + 0);
    try batch.addIndex(base + 2);
    try batch.addIndex(base + 3);
}

fn cornerPoint(rect: Rect, corner: usize) Vec2 {
    return switch (corner) {
        0 => .{ .x = rect.right(), .y = rect.y },
        1 => .{ .x = rect.right(), .y = rect.bottom() },
        2 => .{ .x = rect.x, .y = rect.bottom() },
        else => .{ .x = rect.x, .y = rect.y },
    };
}

test "emitRect writes one quad" {
    var batch = Batcher.init(std.testing.allocator);
    defer batch.deinit();

    try emitRect(&batch, .{ .x = 0, .y = 0, .w = 10, .h = 20 }, ColorPremul.rgba(1, 1, 1, 1));
    try std.testing.expectEqual(@as(usize, 4), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 6), batch.indices.items.len);
}

test "emitRoundedRect writes fan geometry" {
    var batch = Batcher.init(std.testing.allocator);
    defer batch.deinit();

    try emitRoundedRect(&batch, .{ .x = 0, .y = 0, .w = 100, .h = 50 }, .uniform(8), ColorPremul.rgba(0.2, 0.3, 0.4, 1));
    try std.testing.expect(batch.vertices.items.len > 4);
    try std.testing.expect(batch.indices.items.len > 6);
}

test "emitBorder supports independent side widths" {
    var batch = Batcher.init(std.testing.allocator);
    defer batch.deinit();

    try emitBorder(
        &batch,
        .{ .x = 0, .y = 0, .w = 100, .h = 80 },
        .uniform(0),
        .{ .left = 1, .top = 2, .right = 3, .bottom = 4 },
        ColorPremul.rgba(1, 0, 0, 1),
    );
    try std.testing.expectEqual(@as(usize, 16), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 24), batch.indices.items.len);
}
