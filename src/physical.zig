const std = @import("std");
const flow_ir = @import("flow_ir.zig");

pub const SceneSpec = struct {
    node_id: flow_ir.NodeId,
    root: flow_ir.NodeId,
    lights: ?flow_ir.NodeId = null,
    geometry: ?flow_ir.NodeId = null,
    materials: ?flow_ir.NodeId = null,
    colors: ?flow_ir.NodeId = null,

    pub fn hasPhysicalInputs(self: SceneSpec) bool {
        return self.lights != null or self.geometry != null or self.materials != null or self.colors != null;
    }
};

pub const PendingFeature = enum {
    model_cut,
    boolean_subtraction,
    cavity_generation,
    physical_lighting,
    material_propagation,

    pub fn label(self: PendingFeature) []const u8 {
        return switch (self) {
            .model_cut => "Model/cut(from, remove)",
            .boolean_subtraction => "boolean subtraction",
            .cavity_generation => "automatic cavity generation",
            .physical_lighting => "physical lighting",
            .material_propagation => "material/elevation/depth/corner/theme propagation",
        };
    }
};

pub const PendingFeatureUse = struct {
    node_id: flow_ir.NodeId,
    path: []const u8,
    feature: PendingFeature,
};

pub const GeometryPlan = union(enum) {
    none,
    model_cut: CutSpec,
    unresolved_user_call: []const u8,
    unresolved_builtin: []const u8,
    unresolved_node_kind: []const u8,

    pub fn label(self: GeometryPlan) []const u8 {
        return switch (self) {
            .none => "none",
            .model_cut => "Model/cut(from, remove)",
            .unresolved_user_call => |name| name,
            .unresolved_builtin => |path| path,
            .unresolved_node_kind => |kind| kind,
        };
    }
};

pub const CutSpec = struct {
    node_id: flow_ir.NodeId,
    from: flow_ir.NodeId,
    remove: flow_ir.NodeId,
};

pub const OperandSummary = struct {
    kind: []const u8,
    shape: ?[]const u8 = null,
    depth: ?f64 = null,
    wall: ?f64 = null,

    pub fn formatAlloc(self: OperandSummary, allocator: std.mem.Allocator) ![]u8 {
        if (self.shape) |shape| {
            if (self.depth) |depth| {
                if (self.wall) |wall| {
                    return std.fmt.allocPrint(allocator, "{s}(shape={s},depth={d},wall={d})", .{ self.kind, shape, depth, wall });
                }
                return std.fmt.allocPrint(allocator, "{s}(shape={s},depth={d})", .{ self.kind, shape, depth });
            }
            return std.fmt.allocPrint(allocator, "{s}(shape={s})", .{ self.kind, shape });
        }
        return try allocator.dupe(u8, self.kind);
    }
};

pub const GeometryResult = union(enum) {
    none,
    cut: CutResult,
    unresolved: []const u8,

    pub fn label(self: GeometryResult) []const u8 {
        return switch (self) {
            .none => "none",
            .cut => "cut",
            .unresolved => |name| name,
        };
    }
};

pub const GeometryPrimitive = union(enum) {
    none,
    cavity_rect: CavityRect,
    unresolved: []const u8,

    pub fn label(self: GeometryPrimitive) []const u8 {
        return switch (self) {
            .none => "none",
            .cavity_rect => "cavity_rect",
            .unresolved => |name| name,
        };
    }
};

pub const GeometryRaster = union(enum) {
    none,
    depth_strip: DepthStrip,
    unresolved: []const u8,

    pub fn label(self: GeometryRaster) []const u8 {
        return switch (self) {
            .none => "none",
            .depth_strip => "depth_strip",
            .unresolved => |name| name,
        };
    }
};

pub const GeometryDisplay = union(enum) {
    none,
    ascii_strip: AsciiStrip,
    unresolved: []const u8,

    pub fn label(self: GeometryDisplay) []const u8 {
        return switch (self) {
            .none => "none",
            .ascii_strip => "ascii_strip",
            .unresolved => |name| name,
        };
    }
};

pub const CutResult = struct {
    from: OperandSummary,
    remove: OperandSummary,
    cavity_depth: ?f64 = null,
    remaining_depth: ?f64 = null,
    wall_thickness: ?f64 = null,
    height_field: ?CutHeightField = null,

    pub fn formatAlloc(self: CutResult, allocator: std.mem.Allocator) ![]u8 {
        const from = try self.from.formatAlloc(allocator);
        defer allocator.free(from);
        const remove = try self.remove.formatAlloc(allocator);
        defer allocator.free(remove);
        if (self.cavity_depth) |cavity_depth| {
            if (self.remaining_depth) |remaining_depth| {
                if (self.wall_thickness) |wall_thickness| {
                    return std.fmt.allocPrint(
                        allocator,
                        "cut from={s} remove={s} cavity_depth={d} remaining_depth={d} wall={d}",
                        .{ from, remove, cavity_depth, remaining_depth, wall_thickness },
                    );
                }
                return std.fmt.allocPrint(
                    allocator,
                    "cut from={s} remove={s} cavity_depth={d} remaining_depth={d}",
                    .{ from, remove, cavity_depth, remaining_depth },
                );
            }
            if (self.wall_thickness) |wall_thickness| {
                return std.fmt.allocPrint(
                    allocator,
                    "cut from={s} remove={s} cavity_depth={d} wall={d}",
                    .{ from, remove, cavity_depth, wall_thickness },
                );
            }
            return std.fmt.allocPrint(
                allocator,
                "cut from={s} remove={s} cavity_depth={d}",
                .{ from, remove, cavity_depth },
            );
        }
        if (self.wall_thickness) |wall_thickness| {
            return std.fmt.allocPrint(
                allocator,
                "cut from={s} remove={s} wall={d}",
                .{ from, remove, wall_thickness },
            );
        }
        return std.fmt.allocPrint(allocator, "cut from={s} remove={s}", .{ from, remove });
    }
};

pub const CutHeightField = struct {
    rim_depth: f64,
    cavity_floor_depth: f64,
    wall_thickness: f64,

    pub fn heightAt(self: CutHeightField, normalized_x: f64) f64 {
        const x = std.math.clamp(@abs(normalized_x), 0.0, 1.0);
        const normalized_wall = std.math.clamp(self.wall_thickness / 10.0, 0.05, 0.45);
        const cavity_limit = 1.0 - normalized_wall;
        return if (x >= cavity_limit) self.rim_depth else self.cavity_floor_depth;
    }
};

pub const CavityRect = struct {
    outer_shape: ?[]const u8 = null,
    inner_shape: ?[]const u8 = null,
    rim_depth: f64,
    cavity_floor_depth: f64,
    wall_thickness: f64,

    pub fn sampleHeight(self: CavityRect, normalized_x: f64) f64 {
        const field = CutHeightField{
            .rim_depth = self.rim_depth,
            .cavity_floor_depth = self.cavity_floor_depth,
            .wall_thickness = self.wall_thickness,
        };
        return field.heightAt(normalized_x);
    }

    pub fn formatAlloc(self: CavityRect, allocator: std.mem.Allocator) ![]u8 {
        if (self.outer_shape) |outer_shape| {
            if (self.inner_shape) |inner_shape| {
                return std.fmt.allocPrint(
                    allocator,
                    "cavity_rect outer={s} inner={s} rim_depth={d} floor_depth={d} wall={d}",
                    .{ outer_shape, inner_shape, self.rim_depth, self.cavity_floor_depth, self.wall_thickness },
                );
            }
        }
        return std.fmt.allocPrint(
            allocator,
            "cavity_rect rim_depth={d} floor_depth={d} wall={d}",
            .{ self.rim_depth, self.cavity_floor_depth, self.wall_thickness },
        );
    }
};

pub const DepthStrip = struct {
    outer_shape: ?[]const u8 = null,
    inner_shape: ?[]const u8 = null,
    samples: [9]f64,

    pub fn formatAlloc(self: DepthStrip, allocator: std.mem.Allocator) ![]u8 {
        if (self.outer_shape) |outer_shape| {
            if (self.inner_shape) |inner_shape| {
                return std.fmt.allocPrint(
                    allocator,
                    "depth_strip outer={s} inner={s} samples={d},{d},{d},{d},{d},{d},{d},{d},{d}",
                    .{
                        outer_shape,
                        inner_shape,
                        self.samples[0],
                        self.samples[1],
                        self.samples[2],
                        self.samples[3],
                        self.samples[4],
                        self.samples[5],
                        self.samples[6],
                        self.samples[7],
                        self.samples[8],
                    },
                );
            }
        }
        return std.fmt.allocPrint(
            allocator,
            "depth_strip samples={d},{d},{d},{d},{d},{d},{d},{d},{d}",
            .{
                self.samples[0],
                self.samples[1],
                self.samples[2],
                self.samples[3],
                self.samples[4],
                self.samples[5],
                self.samples[6],
                self.samples[7],
                self.samples[8],
            },
        );
    }
};

pub const AsciiStrip = struct {
    outer_shape: ?[]const u8 = null,
    inner_shape: ?[]const u8 = null,
    glyphs: [9]u8,

    pub fn textAlloc(self: AsciiStrip, allocator: std.mem.Allocator) ![]u8 {
        const text = try allocator.alloc(u8, self.glyphs.len);
        @memcpy(text, &self.glyphs);
        return text;
    }

    pub fn formatAlloc(self: AsciiStrip, allocator: std.mem.Allocator) ![]u8 {
        const text = try self.textAlloc(allocator);
        defer allocator.free(text);
        if (self.outer_shape) |outer_shape| {
            if (self.inner_shape) |inner_shape| {
                return std.fmt.allocPrint(
                    allocator,
                    "ascii_strip outer={s} inner={s} glyphs={s}",
                    .{ outer_shape, inner_shape, text },
                );
            }
        }
        return std.fmt.allocPrint(allocator, "ascii_strip glyphs={s}", .{text});
    }
};

pub const ShadedStrip = struct {
    outer_shape: ?[]const u8 = null,
    inner_shape: ?[]const u8 = null,
    glyphs: [9]u8,

    pub fn textAlloc(self: ShadedStrip, allocator: std.mem.Allocator) ![]u8 {
        const text = try allocator.alloc(u8, self.glyphs.len);
        @memcpy(text, &self.glyphs);
        return text;
    }

    pub fn formatAlloc(self: ShadedStrip, allocator: std.mem.Allocator) ![]u8 {
        const text = try self.textAlloc(allocator);
        defer allocator.free(text);
        if (self.outer_shape) |outer_shape| {
            if (self.inner_shape) |inner_shape| {
                return std.fmt.allocPrint(
                    allocator,
                    "shaded_strip outer={s} inner={s} glyphs={s}",
                    .{ outer_shape, inner_shape, text },
                );
            }
        }
        return std.fmt.allocPrint(allocator, "shaded_strip glyphs={s}", .{text});
    }
};

pub const CavityPanel = struct {
    outer_shape: ?[]const u8 = null,
    inner_shape: ?[]const u8 = null,
    rows: [5][9]u8,

    pub fn textAlloc(self: CavityPanel, allocator: std.mem.Allocator) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);

        for (self.rows, 0..) |row, index| {
            if (index != 0) try output.append(allocator, '\n');
            try output.appendSlice(allocator, &row);
        }
        return try output.toOwnedSlice(allocator);
    }

    pub fn formatAlloc(self: CavityPanel, allocator: std.mem.Allocator) ![]u8 {
        const text = try self.textAlloc(allocator);
        defer allocator.free(text);
        if (self.outer_shape) |outer_shape| {
            if (self.inner_shape) |inner_shape| {
                return std.fmt.allocPrint(
                    allocator,
                    "cavity_panel outer={s} inner={s}\n{s}",
                    .{ outer_shape, inner_shape, text },
                );
            }
        }
        return std.fmt.allocPrint(allocator, "cavity_panel\n{s}", .{text});
    }
};

pub const ShadedPanel = struct {
    outer_shape: ?[]const u8 = null,
    inner_shape: ?[]const u8 = null,
    rows: [5][9]u8,

    pub fn textAlloc(self: ShadedPanel, allocator: std.mem.Allocator) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);

        for (self.rows, 0..) |row, index| {
            if (index != 0) try output.append(allocator, '\n');
            try output.appendSlice(allocator, &row);
        }
        return try output.toOwnedSlice(allocator);
    }

    pub fn formatAlloc(self: ShadedPanel, allocator: std.mem.Allocator) ![]u8 {
        const text = try self.textAlloc(allocator);
        defer allocator.free(text);
        if (self.outer_shape) |outer_shape| {
            if (self.inner_shape) |inner_shape| {
                return std.fmt.allocPrint(
                    allocator,
                    "shaded_panel outer={s} inner={s}\n{s}",
                    .{ outer_shape, inner_shape, text },
                );
            }
        }
        return std.fmt.allocPrint(allocator, "shaded_panel\n{s}", .{text});
    }
};

pub const PanelLighting = struct {
    light_count: u32,
    ambient_intensity: f64,
    peak_intensity: f64,
};

pub const PanelTone = enum {
    neutral,
    cool,
    warm,
    danger,

    pub fn label(self: PanelTone) []const u8 {
        return switch (self) {
            .neutral => "neutral",
            .cool => "cool",
            .warm => "warm",
            .danger => "danger",
        };
    }
};

pub const PanelMaterial = struct {
    gloss: f64 = 0,
    metal: f64 = 0,
    glow_intensity: f64 = 0,
    tone: PanelTone = .neutral,

    pub fn formatAlloc(self: PanelMaterial, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "material gloss={d} metal={d} glow={d} tone={s}",
            .{ self.gloss, self.metal, self.glow_intensity, self.tone.label() },
        );
    }
};

pub const LitPanel = struct {
    outer_shape: ?[]const u8 = null,
    inner_shape: ?[]const u8 = null,
    rows: [5][9]u8,
    material: ?PanelMaterial = null,

    pub fn textAlloc(self: LitPanel, allocator: std.mem.Allocator) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);

        for (self.rows, 0..) |row, index| {
            if (index != 0) try output.append(allocator, '\n');
            try output.appendSlice(allocator, &row);
        }
        return try output.toOwnedSlice(allocator);
    }

    pub fn formatAlloc(self: LitPanel, allocator: std.mem.Allocator) ![]u8 {
        const text = try self.textAlloc(allocator);
        defer allocator.free(text);
        const material = if (self.material) |summary| try summary.formatAlloc(allocator) else null;
        defer if (material) |summary| allocator.free(summary);
        if (self.outer_shape) |outer_shape| {
            if (self.inner_shape) |inner_shape| {
                if (material) |summary| {
                    return std.fmt.allocPrint(
                        allocator,
                        "lit_panel outer={s} inner={s} {s}\n{s}",
                        .{ outer_shape, inner_shape, summary, text },
                    );
                }
                return std.fmt.allocPrint(
                    allocator,
                    "lit_panel outer={s} inner={s}\n{s}",
                    .{ outer_shape, inner_shape, text },
                );
            }
        }
        if (material) |summary| {
            return std.fmt.allocPrint(allocator, "lit_panel {s}\n{s}", .{ summary, text });
        }
        return std.fmt.allocPrint(allocator, "lit_panel\n{s}", .{text});
    }
};

pub fn cutResultFromOperands(from: OperandSummary, remove: OperandSummary) CutResult {
    var result = CutResult{
        .from = from,
        .remove = remove,
        .cavity_depth = remove.depth,
        .wall_thickness = remove.wall,
    };
    if (from.depth) |from_depth| {
        if (remove.depth) |remove_depth| {
            const remaining_depth = @max(@as(f64, 0), from_depth - remove_depth);
            result.remaining_depth = remaining_depth;
            result.height_field = .{
                .rim_depth = from_depth,
                .cavity_floor_depth = remaining_depth,
                .wall_thickness = remove.wall orelse 1,
            };
        }
    }
    return result;
}

pub fn primitiveFromGeometryResult(result: GeometryResult) GeometryPrimitive {
    return switch (result) {
        .none => .none,
        .unresolved => |label| .{ .unresolved = label },
        .cut => |cut| blk: {
            const height_field = cut.height_field orelse break :blk .{ .unresolved = "cut without height_field" };
            break :blk .{ .cavity_rect = .{
                .outer_shape = cut.from.shape,
                .inner_shape = cut.remove.shape,
                .rim_depth = height_field.rim_depth,
                .cavity_floor_depth = height_field.cavity_floor_depth,
                .wall_thickness = height_field.wall_thickness,
            } };
        },
    };
}

pub fn rasterFromGeometryPrimitive(primitive: GeometryPrimitive) GeometryRaster {
    return switch (primitive) {
        .none => .none,
        .unresolved => |label| .{ .unresolved = label },
        .cavity_rect => |cavity| blk: {
            var samples: [9]f64 = undefined;
            for (&samples, 0..) |*sample, index| {
                const normalized_x = (@as(f64, @floatFromInt(index)) / 4.0) - 1.0;
                sample.* = cavity.sampleHeight(normalized_x);
            }
            break :blk .{ .depth_strip = .{
                .outer_shape = cavity.outer_shape,
                .inner_shape = cavity.inner_shape,
                .samples = samples,
            } };
        },
    };
}

pub fn displayFromGeometryRaster(raster: GeometryRaster) GeometryDisplay {
    return switch (raster) {
        .none => .none,
        .unresolved => |label| .{ .unresolved = label },
        .depth_strip => |strip| blk: {
            var glyphs: [9]u8 = undefined;
            const rim = strip.samples[0];
            const floor = strip.samples[4];
            const midpoint = (rim + floor) / 2.0;
            for (&glyphs, strip.samples) |*glyph, sample| {
                glyph.* = if (sample > midpoint) '#' else '.';
            }
            break :blk .{ .ascii_strip = .{
                .outer_shape = strip.outer_shape,
                .inner_shape = strip.inner_shape,
                .glyphs = glyphs,
            } };
        },
    };
}

pub fn shadedStripFromGeometryRaster(raster: GeometryRaster) ?ShadedStrip {
    return switch (raster) {
        .depth_strip => |strip| blk: {
            const rim = strip.samples[0];
            const floor = strip.samples[4];
            const midpoint = (rim + floor) / 2.0;

            var glyphs: [9]u8 = undefined;
            for (&glyphs, strip.samples, 0..) |*glyph, sample, index| {
                const prev = if (index == 0) sample else strip.samples[index - 1];
                const next = if (index + 1 >= strip.samples.len) sample else strip.samples[index + 1];
                glyph.* = if (sample > next + 0.1)
                    '\\'
                else if (sample > prev + 0.1)
                    '/'
                else if (sample > midpoint)
                    '#'
                else
                    '.';
            }

            break :blk .{
                .outer_shape = strip.outer_shape,
                .inner_shape = strip.inner_shape,
                .glyphs = glyphs,
            };
        },
        else => null,
    };
}

pub fn cavityPanelFromShadedStrip(shaded: ShadedStrip) CavityPanel {
    var rows: [5][9]u8 = undefined;
    rows[0] = [_]u8{' ', ' ', '#', '#', '#', '#', '#', ' ', ' '};
    rows[1] = shaded.glyphs;
    rows[2] = [_]u8{'|', '|', '.', '.', '.', '.', '.', '|', '|'};
    rows[3] = [_]u8{'|', '|', '.', '.', '.', '.', '.', '|', '|'};
    rows[4] = [_]u8{' ', ' ', '\\', '\\', '\\', '\\', '\\', ' ', ' '};
    return .{
        .outer_shape = shaded.outer_shape,
        .inner_shape = shaded.inner_shape,
        .rows = rows,
    };
}

pub fn shadedPanelFromCavityPanel(panel: CavityPanel) ShadedPanel {
    var rows = panel.rows;
    for (&rows) |*row| {
        for (row) |*cell| {
            cell.* = switch (cell.*) {
                '#' => '@',
                '.' => ':',
                '|' => '#',
                '\\' => 'v',
                else => cell.*,
            };
        }
    }
    return .{
        .outer_shape = panel.outer_shape,
        .inner_shape = panel.inner_shape,
        .rows = rows,
    };
}

fn fillGlyphForTone(base: u8, tone: PanelTone) u8 {
    return switch (tone) {
        .neutral => base,
        .cool => '~',
        .warm => ';',
        .danger => '!',
    };
}

pub fn litPanelFromShadedPanel(panel: ShadedPanel, lighting: PanelLighting, material: ?PanelMaterial) LitPanel {
    var rows = panel.rows;
    for (&rows) |*row| {
        for (row) |*cell| {
            cell.* = switch (cell.*) {
                '@' => if (lighting.peak_intensity >= 1.0) '*' else '+',
                ':' => if (lighting.ambient_intensity >= 0.35) '.' else ',',
                'v' => if (lighting.light_count >= 3) 'V' else 'v',
                else => cell.*,
            };
        }
    }
    if (material) |surface| {
        for (&rows) |*row| {
            for (row) |*cell| {
                cell.* = switch (cell.*) {
                    '*', '+' => if (surface.gloss >= 0.45) '=' else cell.*,
                    '.', ',' => fillGlyphForTone(cell.*, surface.tone),
                    '#' => if (surface.metal >= 0.25) 'M' else '#',
                    else => cell.*,
                };
            }
        }
    }
    return .{
        .outer_shape = panel.outer_shape,
        .inner_shape = panel.inner_shape,
        .rows = rows,
        .material = material,
    };
}

pub fn sceneSpecFromBuiltin(node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) ?SceneSpec {
    if (!std.mem.eql(u8, call.path, "Scene/new")) return null;
    const root = findNamed(call.named, "root") orelse if (call.positional.len != 0) call.positional[0] else return null;
    return .{
        .node_id = node_id,
        .root = root,
        .lights = findNamed(call.named, "lights"),
        .geometry = findNamed(call.named, "geometry"),
        .materials = findNamed(call.named, "materials"),
        .colors = findNamed(call.named, "colors"),
    };
}

pub fn pendingFeatureFromBuiltin(node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) ?PendingFeatureUse {
    if (std.mem.eql(u8, call.path, "Model/cut")) {
        return .{
            .node_id = node_id,
            .path = call.path,
            .feature = .model_cut,
        };
    }
    if (std.mem.eql(u8, call.path, "Scene/new")) {
        if (findNamed(call.named, "geometry") != null) {
            return .{
                .node_id = node_id,
                .path = call.path,
                .feature = .boolean_subtraction,
            };
        }
        if (findNamed(call.named, "lights") != null) {
            return .{
                .node_id = node_id,
                .path = call.path,
                .feature = .physical_lighting,
            };
        }
        if (findNamed(call.named, "materials") != null or findNamed(call.named, "colors") != null) {
            return .{
                .node_id = node_id,
                .path = call.path,
                .feature = .material_propagation,
            };
        }
    }
    return null;
}

pub fn geometryPlanFromNode(document: *const flow_ir.Document, node_id: flow_ir.NodeId) GeometryPlan {
    const node = document.nodes[node_id];
    return switch (node.kind) {
        .binding_ref => |binding_id| geometryPlanFromNode(document, document.bindings[binding_id].node),
        .builtin_call => |call| blk: {
            if (std.mem.eql(u8, call.path, "Model/cut")) {
                const from = findNamed(call.named, "from") orelse if (call.positional.len != 0) call.positional[0] else break :blk .{ .unresolved_builtin = call.path };
                const remove = findNamed(call.named, "remove") orelse if (call.positional.len >= 2) call.positional[1] else break :blk .{ .unresolved_builtin = call.path };
                break :blk .{ .model_cut = .{
                    .node_id = node_id,
                    .from = from,
                    .remove = remove,
                } };
            }
            break :blk .{ .unresolved_builtin = call.path };
        },
        .user_call => |call| .{ .unresolved_user_call = document.functions[call.function].name },
        .record => .{ .unresolved_node_kind = "record" },
        .list => .{ .unresolved_node_kind = "list" },
        .text => .{ .unresolved_node_kind = "text" },
        .atom => .{ .unresolved_node_kind = "atom" },
        .symbol => .{ .unresolved_node_kind = "symbol" },
        .number => .{ .unresolved_node_kind = "number" },
        else => .{ .unresolved_node_kind = @tagName(node.kind) },
    };
}

fn findNamed(named: []const flow_ir.NamedArg, name: []const u8) ?flow_ir.NodeId {
    for (named) |arg| {
        if (std.mem.eql(u8, arg.name, name)) return arg.value;
    }
    return null;
}

test "captures physical scene spec from Scene/new" {
    const call = flow_ir.BuiltinCall{
        .path = "Scene/new",
        .positional = &.{},
        .named = &.{
            .{ .name = "root", .value = 1 },
            .{ .name = "lights", .value = 2 },
            .{ .name = "materials", .value = 3 },
            .{ .name = "colors", .value = 4 },
        },
    };

    const spec = sceneSpecFromBuiltin(9, call).?;
    try std.testing.expectEqual(@as(flow_ir.NodeId, 9), spec.node_id);
    try std.testing.expectEqual(@as(flow_ir.NodeId, 1), spec.root);
    try std.testing.expectEqual(@as(?flow_ir.NodeId, 2), spec.lights);
    try std.testing.expectEqual(@as(?flow_ir.NodeId, 3), spec.materials);
    try std.testing.expectEqual(@as(?flow_ir.NodeId, 4), spec.colors);
    try std.testing.expect(spec.hasPhysicalInputs());
}

test "records pending physical renderer features" {
    const cut_call = flow_ir.BuiltinCall{
        .path = "Model/cut",
        .positional = &.{ 1, 2 },
        .named = &.{},
    };
    const cut_feature = pendingFeatureFromBuiltin(5, cut_call).?;
    try std.testing.expectEqualStrings("Model/cut(from, remove)", cut_feature.feature.label());

    const scene_call = flow_ir.BuiltinCall{
        .path = "Scene/new",
        .positional = &.{},
        .named = &.{
            .{ .name = "root", .value = 1 },
            .{ .name = "lights", .value = 2 },
        },
    };
    const scene_feature = pendingFeatureFromBuiltin(7, scene_call).?;
    try std.testing.expectEqualStrings("physical lighting", scene_feature.feature.label());
}

test "extracts model cut geometry plan from flow node" {
    const doc = flow_ir.Document{
        .arena = undefined,
        .bindings = &.{
            .{ .name = "geometry", .node = 0, .span = .{ .start = 0, .end = 0 } },
        },
        .functions = &.{},
        .nodes = &.{
            .{
                .span = .{ .start = 0, .end = 0 },
                .kind = .{ .builtin_call = .{
                    .path = "Model/cut",
                    .positional = &.{},
                    .named = &.{
                        .{ .name = "from", .value = 1 },
                        .{ .name = "remove", .value = 2 },
                    },
                } },
            },
            .{ .span = .{ .start = 0, .end = 0 }, .kind = .{ .record = &.{} } },
            .{ .span = .{ .start = 0, .end = 0 }, .kind = .{ .record = &.{} } },
        },
        .root_binding = null,
        .source_len = 0,
        .link_port_count = 0,
        .stateful_count = 0,
    };

    const plan = geometryPlanFromNode(&doc, 0);
    switch (plan) {
        .model_cut => |cut| {
            try std.testing.expectEqual(@as(flow_ir.NodeId, 0), cut.node_id);
            try std.testing.expectEqual(@as(flow_ir.NodeId, 1), cut.from);
            try std.testing.expectEqual(@as(flow_ir.NodeId, 2), cut.remove);
        },
        else => return error.UnexpectedGeometryPlan,
    }
}

test "formats cut geometry result" {
    const result: GeometryResult = .{ .cut = cutResultFromOperands(
        .{ .kind = "record", .shape = "Outer", .depth = 8 },
        .{ .kind = "record", .shape = "Inner", .depth = 5, .wall = 2 },
    ) };

    const rendered = try result.cut.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        "cut from=record(shape=Outer,depth=8) remove=record(shape=Inner,depth=5,wall=2) cavity_depth=5 remaining_depth=3 wall=2",
        rendered,
    );
}

test "cut geometry result derives cavity metrics" {
    const result = cutResultFromOperands(
        .{ .kind = "record", .shape = "Outer", .depth = 8 },
        .{ .kind = "record", .shape = "Inner", .depth = 5, .wall = 2 },
    );

    try std.testing.expectEqual(@as(?f64, 5), result.cavity_depth);
    try std.testing.expectEqual(@as(?f64, 3), result.remaining_depth);
    try std.testing.expectEqual(@as(?f64, 2), result.wall_thickness);
}

test "cut geometry result builds normalized height field" {
    const result = cutResultFromOperands(
        .{ .kind = "record", .shape = "Outer", .depth = 8 },
        .{ .kind = "record", .shape = "Inner", .depth = 5, .wall = 2 },
    );
    const height_field = result.height_field orelse return error.MissingHeightField;

    try std.testing.expectEqual(@as(f64, 3), height_field.heightAt(0));
    try std.testing.expectEqual(@as(f64, 8), height_field.heightAt(1));
    try std.testing.expectEqual(@as(f64, 8), height_field.heightAt(-1));
}

test "cut geometry result builds cavity primitive" {
    const result: GeometryResult = .{ .cut = cutResultFromOperands(
        .{ .kind = "record", .shape = "Outer", .depth = 8 },
        .{ .kind = "record", .shape = "Inner", .depth = 5, .wall = 2 },
    ) };
    const primitive = primitiveFromGeometryResult(result);

    switch (primitive) {
        .cavity_rect => |cavity| {
            try std.testing.expectEqualStrings("Outer", cavity.outer_shape.?);
            try std.testing.expectEqualStrings("Inner", cavity.inner_shape.?);
            try std.testing.expectEqual(@as(f64, 8), cavity.rim_depth);
            try std.testing.expectEqual(@as(f64, 3), cavity.cavity_floor_depth);
            try std.testing.expectEqual(@as(f64, 2), cavity.wall_thickness);
            try std.testing.expectEqual(@as(f64, 3), cavity.sampleHeight(0));
            try std.testing.expectEqual(@as(f64, 8), cavity.sampleHeight(1));
        },
        else => return error.ExpectedCavityPrimitive,
    }
}

test "cavity primitive builds depth strip raster" {
    const primitive: GeometryPrimitive = .{ .cavity_rect = .{
        .outer_shape = "Outer",
        .inner_shape = "Inner",
        .rim_depth = 8,
        .cavity_floor_depth = 3,
        .wall_thickness = 2,
    } };
    const raster = rasterFromGeometryPrimitive(primitive);

    switch (raster) {
        .depth_strip => |strip| {
            try std.testing.expectEqualStrings("Outer", strip.outer_shape.?);
            try std.testing.expectEqualStrings("Inner", strip.inner_shape.?);
            try std.testing.expectEqual(@as(f64, 8), strip.samples[0]);
            try std.testing.expectEqual(@as(f64, 3), strip.samples[4]);
            try std.testing.expectEqual(@as(f64, 8), strip.samples[8]);
        },
        else => return error.ExpectedDepthStripRaster,
    }
}

test "depth strip raster builds ascii display" {
    const raster: GeometryRaster = .{ .depth_strip = .{
        .outer_shape = "Outer",
        .inner_shape = "Inner",
        .samples = .{ 8, 8, 3, 3, 3, 3, 3, 8, 8 },
    } };
    const display = displayFromGeometryRaster(raster);

    switch (display) {
        .ascii_strip => |ascii| {
            try std.testing.expectEqualStrings("Outer", ascii.outer_shape.?);
            try std.testing.expectEqualStrings("Inner", ascii.inner_shape.?);
            const text = try ascii.textAlloc(std.testing.allocator);
            defer std.testing.allocator.free(text);
            try std.testing.expectEqualStrings("##.....##", text);
        },
        else => return error.ExpectedAsciiStripDisplay,
    }
}

test "depth strip raster builds shaded display" {
    const raster: GeometryRaster = .{ .depth_strip = .{
        .outer_shape = "Outer",
        .inner_shape = "Inner",
        .samples = .{ 8, 8, 3, 3, 3, 3, 3, 8, 8 },
    } };
    const shaded = shadedStripFromGeometryRaster(raster) orelse return error.ExpectedShadedStripDisplay;

    try std.testing.expectEqualStrings("Outer", shaded.outer_shape.?);
    try std.testing.expectEqualStrings("Inner", shaded.inner_shape.?);
    const text = try shaded.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("#\\...../#", text);
}

test "shaded strip builds cavity panel" {
    const shaded = ShadedStrip{
        .outer_shape = "Outer",
        .inner_shape = "Inner",
        .glyphs = [_]u8{'#', '\\', '.', '.', '.', '.', '.', '/', '#'},
    };
    const panel = cavityPanelFromShadedStrip(shaded);
    try std.testing.expectEqualStrings("Outer", panel.outer_shape.?);
    try std.testing.expectEqualStrings("Inner", panel.inner_shape.?);
    const text = try panel.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings(
        "  #####  \n#\\...../#\n||.....||\n||.....||\n  \\\\\\\\\\  ",
        text,
    );
}

test "cavity panel builds shaded panel" {
    const panel = CavityPanel{
        .outer_shape = "Outer",
        .inner_shape = "Inner",
        .rows = .{
            [_]u8{' ', ' ', '#', '#', '#', '#', '#', ' ', ' '},
            [_]u8{'#', '\\', '.', '.', '.', '.', '.', '/', '#'},
            [_]u8{'|', '|', '.', '.', '.', '.', '.', '|', '|'},
            [_]u8{'|', '|', '.', '.', '.', '.', '.', '|', '|'},
            [_]u8{' ', ' ', '\\', '\\', '\\', '\\', '\\', ' ', ' '},
        },
    };
    const shaded = shadedPanelFromCavityPanel(panel);
    try std.testing.expectEqualStrings("Outer", shaded.outer_shape.?);
    try std.testing.expectEqualStrings("Inner", shaded.inner_shape.?);
    const text = try shaded.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings(
        "  @@@@@  \n@v:::::/@\n##:::::##\n##:::::##\n  vvvvv  ",
        text,
    );
}

test "shaded panel builds lit panel from lighting summary" {
    const panel = ShadedPanel{
        .outer_shape = "Outer",
        .inner_shape = "Inner",
        .rows = .{
            [_]u8{' ', ' ', '@', '@', '@', '@', '@', ' ', ' '},
            [_]u8{'@', 'v', ':', ':', ':', ':', ':', '/', '@'},
            [_]u8{'#', '#', ':', ':', ':', ':', ':', '#', '#'},
            [_]u8{'#', '#', ':', ':', ':', ':', ':', '#', '#'},
            [_]u8{' ', ' ', 'v', 'v', 'v', 'v', 'v', ' ', ' '},
        },
    };
    const lit = litPanelFromShadedPanel(panel, .{
        .light_count = 3,
        .ambient_intensity = 0.4,
        .peak_intensity = 1.2,
    }, null);
    try std.testing.expectEqualStrings("Outer", lit.outer_shape.?);
    try std.testing.expectEqualStrings("Inner", lit.inner_shape.?);
    const text = try lit.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings(
        "  *****  \n*V...../*\n##.....##\n##.....##\n  VVVVV  ",
        text,
    );
}

test "lit panel applies material gloss metal and tone" {
    const panel = ShadedPanel{
        .outer_shape = "Outer",
        .inner_shape = "Inner",
        .rows = .{
            [_]u8{' ', ' ', '@', '@', '@', '@', '@', ' ', ' '},
            [_]u8{'@', 'v', ':', ':', ':', ':', ':', '/', '@'},
            [_]u8{'#', '#', ':', ':', ':', ':', ':', '#', '#'},
            [_]u8{'#', '#', ':', ':', ':', ':', ':', '#', '#'},
            [_]u8{' ', ' ', 'v', 'v', 'v', 'v', 'v', ' ', ' '},
        },
    };
    const lit = litPanelFromShadedPanel(panel, .{
        .light_count = 3,
        .ambient_intensity = 0.4,
        .peak_intensity = 1.2,
    }, .{
        .gloss = 0.7,
        .metal = 0.4,
        .glow_intensity = 0.1,
        .tone = .danger,
    });
    try std.testing.expectEqualStrings("Outer", lit.outer_shape.?);
    try std.testing.expectEqualStrings("Inner", lit.inner_shape.?);
    try std.testing.expectEqual(PanelTone.danger, lit.material.?.tone);
    const text = try lit.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings(
        "  =====  \n=V!!!!!/=\nMM!!!!!MM\nMM!!!!!MM\n  VVVVV  ",
        text,
    );
}
