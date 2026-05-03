const std = @import("std");
const boon = @import("boon");

const colors = @import("colors.zig");
const geometry = @import("geometry.zig");
const renderer = @import("renderer.zig");

const bridge = boon.boon_runtime_host;

pub const Viewport = struct {
    width: usize = 1000,
    height: usize = 900,
    scale: f32 = 1.0,
};

pub const Theme = enum {
    professional,
    glassmorphism,
    neobrutalism,
    neumorphism,

    pub fn fromSemantic(semantic: SemanticTree) Theme {
        for (semantic.buttons) |button| {
            if (!button.outlined) continue;
            if (containsVisible(button.label, "Glass")) return .glassmorphism;
            if (containsVisible(button.label, "Brutalist")) return .neobrutalism;
            if (containsVisible(button.label, "Neumorphic")) return .neumorphism;
            if (containsVisible(button.label, "Professional")) return .professional;
        }
        return .professional;
    }

    pub fn name(self: Theme) []const u8 {
        return switch (self) {
            .professional => "professional",
            .glassmorphism => "glassmorphism",
            .neobrutalism => "neobrutalism",
            .neumorphism => "neumorphism",
        };
    }
};

pub const Mode = enum {
    light,
    dark,

    pub fn fromSemantic(semantic: SemanticTree) Mode {
        return if (containsVisible(semantic.rendered_text, "Light mode")) .dark else .light;
    }

    pub fn toggleLabel(self: Mode) []const u8 {
        return switch (self) {
            .light => "Dark mode",
            .dark => "Light mode",
        };
    }
};

pub const SemanticInput = struct {
    text: []u8,
    placeholder: []u8,
    focused: bool,
    disabled: bool,
    caret_visible: bool = true,
    handle: ?bridge.TextInputHandle = null,
};

pub const SemanticButton = struct {
    label: []u8,
    disabled: bool,
    outlined: bool,
    link: ?u64 = null,
    handle: ?bridge.ControlHandle = null,
};

pub const SemanticCheckbox = struct {
    label: []u8,
    checked: bool,
};

pub const SemanticSvgClick = struct {
    link: u64,
    handle: ?bridge.ControlHandle = null,
};

pub const SemanticSvgCircle = struct {
    cx: f32,
    cy: f32,
    r: f32,
};

pub const SemanticTree = struct {
    rendered_text: []u8,
    inputs: []SemanticInput,
    buttons: []SemanticButton,
    checkboxes: []SemanticCheckbox,
    svg_clicks: []SemanticSvgClick = &.{},
    svg_circles: []SemanticSvgCircle = &.{},

    pub fn fromDocument(allocator: std.mem.Allocator, document: bridge.DocumentSnapshot) !SemanticTree {
        return fromRuntimeRoot(allocator, document.values, document.root, document.events);
    }

    pub fn fromScene(allocator: std.mem.Allocator, scene: bridge.SceneSnapshot) !SemanticTree {
        return fromRuntimeRoot(allocator, scene.values, scene.root, scene.events);
    }

    pub fn fromRenderedText(allocator: std.mem.Allocator, text: []const u8) !SemanticTree {
        return .{
            .rendered_text = try readableRenderedTextAlloc(allocator, text),
            .inputs = @constCast(&[_]SemanticInput{}),
            .buttons = @constCast(&[_]SemanticButton{}),
            .checkboxes = @constCast(&[_]SemanticCheckbox{}),
            .svg_clicks = @constCast(&[_]SemanticSvgClick{}),
            .svg_circles = @constCast(&[_]SemanticSvgCircle{}),
        };
    }

    fn fromRuntimeRoot(allocator: std.mem.Allocator, values: []const bridge.RuntimeValue, root: bridge.ValueId, events: []const bridge.EventBinding) !SemanticTree {
        var inputs = std.ArrayList(SemanticInput).empty;
        var buttons = std.ArrayList(SemanticButton).empty;
        var checkboxes = std.ArrayList(SemanticCheckbox).empty;
        var svg_clicks = std.ArrayList(SemanticSvgClick).empty;
        var svg_circles = std.ArrayList(SemanticSvgCircle).empty;
        errdefer {
            freeInputs(allocator, inputs.items);
            freeButtons(allocator, buttons.items);
            freeCheckboxes(allocator, checkboxes.items);
            inputs.deinit(allocator);
            buttons.deinit(allocator);
            checkboxes.deinit(allocator);
            svg_clicks.deinit(allocator);
            svg_circles.deinit(allocator);
        }

        const raw_rendered = try renderedTextAlloc(allocator, values, root);
        defer allocator.free(raw_rendered);
        const rendered = try readableRenderedTextAlloc(allocator, raw_rendered);
        errdefer allocator.free(rendered);

        const visited = try allocator.alloc(bool, values.len);
        defer allocator.free(visited);
        @memset(visited, false);
        try collectSemanticValueById(allocator, values, events, root, visited, &inputs, &buttons, &checkboxes, &svg_clicks, &svg_circles);
        try collectSvgClickEvents(allocator, values, events, &svg_clicks);

        return .{
            .rendered_text = rendered,
            .inputs = try inputs.toOwnedSlice(allocator),
            .buttons = try buttons.toOwnedSlice(allocator),
            .checkboxes = try checkboxes.toOwnedSlice(allocator),
            .svg_clicks = try svg_clicks.toOwnedSlice(allocator),
            .svg_circles = try svg_circles.toOwnedSlice(allocator),
        };
    }

    pub fn deinit(self: *SemanticTree, allocator: std.mem.Allocator) void {
        allocator.free(self.rendered_text);
        freeInputs(allocator, self.inputs);
        freeButtons(allocator, self.buttons);
        freeCheckboxes(allocator, self.checkboxes);
        if (self.inputs.len != 0) allocator.free(self.inputs);
        if (self.buttons.len != 0) allocator.free(self.buttons);
        if (self.checkboxes.len != 0) allocator.free(self.checkboxes);
        if (self.svg_clicks.len != 0) allocator.free(self.svg_clicks);
        if (self.svg_circles.len != 0) allocator.free(self.svg_circles);
        self.* = undefined;
    }
};

pub const TraceCommand = struct {
    base: renderer.RenderTraceCommand,
    role: []const u8,
    label: []const u8 = "",
    text_size: f32 = 0,
    caret_visible: bool = false,
    caret_text: []const u8 = "",
};

pub const RenderTrace = struct {
    commands: []TraceCommand,
    theme: Theme,
    mode: Mode,
    viewport: Viewport,

    pub fn project(allocator: std.mem.Allocator, semantic: SemanticTree, viewport: Viewport) !RenderTrace {
        if (!usesPhysicalTodoLayout(semantic)) return projectGeneric(allocator, semantic, viewport);

        const theme = Theme.fromSemantic(semantic);
        const mode = Mode.fromSemantic(semantic);
        var commands = std.ArrayList(TraceCommand).empty;
        errdefer commands.deinit(allocator);

        const palette = Palette.forTheme(theme, mode);
        const card_radius: f32 = switch (theme) {
            .neobrutalism => 0,
            .neumorphism => 22,
            else => 12,
        };
        const card_shadow_blur: f32 = switch (theme) {
            .neumorphism => 36,
            .neobrutalism => 5,
            else => 15,
        };
        const card = geometry.Rect{ .x = 180, .y = 130, .w = 640, .h = 620 };
        try appendCommand(&commands, allocator, .shadow, "main_card", "", card, card_radius, palette.shadow, .{
            .z = 8,
            .blur_radius = card_shadow_blur,
            .offset = .{ .x = 0, .y = 12 },
            .alpha = palette.surface.a,
        });
        try appendCommand(&commands, allocator, .bevel, "main_card", "", card, card_radius, palette.highlight, .{ .z = 5, .alpha = palette.surface.a });

        const title = geometry.Rect{ .x = 250, .y = 62, .w = 500, .h = 92 };
        try appendCommand(&commands, allocator, .shadow, "title_text", "todos", title, 0, palette.shadow, .{ .z = 7, .blur_radius = 4, .offset = .{ .x = 0, .y = 3 }, .text_size = 100 });
        try appendCommand(&commands, allocator, .bevel, "title_text", "todos", title, 0, palette.title, .{ .z = 9, .text_size = 100 });

        for (semantic.inputs, 0..) |input, index| {
            const y = 176 + @as(f32, @floatFromInt(index)) * 58;
            const rect = geometry.Rect{ .x = 230, .y = y, .w = 540, .h = 48 };
            const label = if (input.placeholder.len != 0) input.placeholder else input.text;
            try appendCommand(&commands, allocator, .cutout_rounded_rect, "text_input", label, rect, 10, palette.surface, .{ .z = -2, .alpha = palette.surface.a });
            try appendCommand(&commands, allocator, .inner_shadow, "text_input", label, rect, 10, palette.shadow, .{ .z = -3, .blur_radius = 13, .spread = 1 });
            try appendCommand(&commands, allocator, .bevel, "text_input", label, rect, 10, palette.highlight, .{ .z = -1, .caret_visible = input.focused and input.caret_visible, .caret_text = input.text });
            if (input.focused) {
                try appendCommand(&commands, allocator, .glow, "text_input", label, rect, 12, palette.focus, .{ .z = 2, .blur_radius = 20, .alpha = 0.55 });
            }
        }

        var button_index: usize = 0;
        for (semantic.buttons) |button| {
            const row = button_index / 4;
            const col = button_index % 4;
            const rect = geometry.Rect{
                .x = 230 + @as(f32, @floatFromInt(col)) * 136,
                .y = 606 + @as(f32, @floatFromInt(row)) * 48,
                .w = 118,
                .h = 36,
            };
            const radius: f32 = if (theme == .neobrutalism) 0 else 8;
            try appendCommand(&commands, allocator, .shadow, "button", button.label, rect, radius, palette.shadow, .{ .z = 5, .blur_radius = 8, .offset = .{ .x = 0, .y = 4 } });
            try appendCommand(&commands, allocator, .bevel, "button", button.label, rect, radius, palette.highlight, .{ .z = 7 });
            if (button.outlined) {
                try appendCommand(&commands, allocator, .outline, "button", button.label, rect, radius, palette.focus, .{ .z = 8, .outline_width = 2 });
            }
            button_index += 1;
        }

        for (semantic.checkboxes, 0..) |checkbox, index| {
            const rect = geometry.Rect{ .x = 240, .y = 270 + @as(f32, @floatFromInt(index)) * 54, .w = 26, .h = 26 };
            try appendCommand(&commands, allocator, .cutout_rounded_rect, "checkbox", checkbox.label, rect, 6, palette.surface, .{ .z = -1, .alpha = palette.surface.a });
            try appendCommand(&commands, allocator, .inner_shadow, "checkbox", checkbox.label, rect, 6, palette.shadow, .{ .z = -2, .blur_radius = 9 });
            try appendCommandIcon(&commands, allocator, .svg_circle, "checkbox", checkbox.label, "checkbox_active", rect, 13, palette.focus, .{ .z = 0, .outline_width = 2 });
            if (checkbox.checked) {
                try appendCommandIcon(&commands, allocator, .svg_path, "checkbox", checkbox.label, "checkbox_completed", rect, 6, palette.focus, .{ .z = 1 });
            }
        }

        return .{
            .commands = try commands.toOwnedSlice(allocator),
            .theme = theme,
            .mode = mode,
            .viewport = viewport,
        };
    }

    pub fn deinit(self: *RenderTrace, allocator: std.mem.Allocator) void {
        if (self.commands.len != 0) allocator.free(self.commands);
        self.* = undefined;
    }

    pub fn backgroundColor(self: RenderTrace) colors.ColorPremul {
        return Palette.forTheme(self.theme, self.mode).background;
    }
};

fn usesPhysicalTodoLayout(semantic: SemanticTree) bool {
    if (semantic.inputs.len == 0) return false;
    for (semantic.buttons) |button| {
        if (containsVisible(button.label, "Professional")) return true;
        if (containsVisible(button.label, "Glass")) return true;
        if (containsVisible(button.label, "Brutalist")) return true;
        if (containsVisible(button.label, "Neumorphic")) return true;
    }
    return false;
}

fn usesGenericTodoLayout(semantic: SemanticTree) bool {
    if (semantic.inputs.len == 0 or semantic.checkboxes.len < 2 or semantic.buttons.len < 3) return false;
    var saw_all = false;
    var saw_active = false;
    var saw_completed = false;
    for (semantic.buttons) |button| {
        saw_all = saw_all or containsVisible(button.label, "All");
        saw_active = saw_active or containsVisible(button.label, "Active");
        saw_completed = saw_completed or containsVisible(button.label, "Completed");
    }
    return saw_all and saw_active and saw_completed;
}

fn projectGenericTodoLayout(allocator: std.mem.Allocator, semantic: SemanticTree, viewport: Viewport) !RenderTrace {
    const theme: Theme = .professional;
    const mode: Mode = .light;
    const palette = Palette.forTheme(theme, mode);
    var commands = std.ArrayList(TraceCommand).empty;
    errdefer commands.deinit(allocator);

    const card = geometry.Rect{ .x = 90, .y = 45, .w = 820, .h = 800 };
    try appendCommand(&commands, allocator, .shadow, "main_card", "", card, 12, palette.shadow, .{
        .z = 4,
        .blur_radius = 10,
        .offset = .{ .x = 0, .y = 10 },
    });
    try appendCommand(&commands, allocator, .bevel, "main_card", "", card, 12, palette.highlight, .{ .z = 5 });
    try appendCommand(&commands, allocator, .bevel, "title_text", "todos", .{ .x = 130, .y = 78, .w = 240, .h = 36 }, 0, colors.ColorPremul.rgba(0, 0, 0, 0), .{ .z = 9, .text_size = 30 });

    const input_x: f32 = 215;
    const input_w: f32 = 570;
    const input_start_y: f32 = 126;
    const input_h: f32 = 54;
    for (semantic.inputs, 0..) |input, index| {
        const y = input_start_y + @as(f32, @floatFromInt(index)) * 62;
        if (y + input_h > card.y + card.h - 96) break;
        const rect = geometry.Rect{ .x = input_x, .y = y, .w = input_w, .h = input_h };
        const label = inputLabelSlice(input, 54);
        try appendCommand(&commands, allocator, .cutout_rounded_rect, "text_input", label, rect, 4, palette.surface, .{ .z = 6, .alpha = palette.surface.a, .text_size = 20 });
        try appendCommand(&commands, allocator, .bevel, "text_input", label, rect, 4, palette.highlight, .{ .z = 7, .text_size = 20, .caret_visible = input.focused and input.caret_visible, .caret_text = visibleLabelSlice(input.text, 54) });
        if (input.focused) {
            try appendCommand(&commands, allocator, .outline, "text_input", label, rect, 4, palette.focus, .{ .z = 8, .outline_width = 2 });
        }
    }

    const row_start_y = input_start_y + @as(f32, @floatFromInt(@max(semantic.inputs.len, 1))) * 62 + 14;
    const row_h: f32 = 26;
    const footer_y: f32 = card.y + card.h - 46;
    const max_rows: usize = @intFromFloat(@max(0, @floor((footer_y - row_start_y - 10) / row_h)));

    if (semantic.checkboxes.len != 0) {
        const toggle_rect = geometry.Rect{ .x = 162, .y = input_start_y + 14, .w = 26, .h = 26 };
        try appendCommand(&commands, allocator, .cutout_rounded_rect, "checkbox", "", toggle_rect, 2, palette.surface, .{ .z = 6, .alpha = palette.surface.a });
        try appendCommandIcon(&commands, allocator, .svg_circle, "checkbox", "", "checkbox_active", toggle_rect, 13, palette.focus, .{ .z = 8, .outline_width = 2 });
        if (semantic.checkboxes[0].checked) {
            try appendCommandIcon(&commands, allocator, .svg_path, "checkbox", "", "checkbox_completed", toggle_rect, 6, palette.focus, .{ .z = 9 });
        }
    }

    var visible_rows: usize = 0;
    for (semantic.checkboxes[if (semantic.checkboxes.len == 0) 0 else 1..], 0..) |checkbox, item_index| {
        if (visible_rows >= max_rows) break;
        const y = row_start_y + @as(f32, @floatFromInt(item_index)) * row_h;
        const rect = geometry.Rect{ .x = 162, .y = y + 1, .w = 22, .h = 22 };
        const label = visibleLabelSlice(todoRowLabelFromRenderedText(semantic.rendered_text, item_index) orelse checkbox.label, 56);
        try appendCommand(&commands, allocator, .cutout_rounded_rect, "checkbox", label, rect, 2, palette.surface, .{ .z = 6, .alpha = palette.surface.a });
        try appendCommandIcon(&commands, allocator, .svg_circle, "checkbox", label, "checkbox_active", rect, 11, palette.focus, .{ .z = 8, .outline_width = 2 });
        if (checkbox.checked) {
            try appendCommandIcon(&commands, allocator, .svg_path, "checkbox", label, "checkbox_completed", rect, 6, palette.focus, .{ .z = 9 });
        }
        visible_rows += 1;
    }

    const count_label = todoFooterCountSlice(semantic.rendered_text);
    if (count_label.len != 0) {
        try appendCommand(&commands, allocator, .bevel, "plain_text", count_label, .{ .x = 140, .y = footer_y + 10, .w = 210, .h = 26 }, 0, colors.ColorPremul.rgba(0, 0, 0, 0), .{ .z = 9, .text_size = 24 });
    }

    for (semantic.buttons, 0..) |button, index| {
        if (index >= 3) break;
        const rect = geometry.Rect{
            .x = 230 + @as(f32, @floatFromInt(index)) * 154,
            .y = footer_y,
            .w = 132,
            .h = 44,
        };
        try appendCommand(&commands, allocator, .shadow, "button", button.label, rect, 6, palette.shadow, .{ .z = 5, .blur_radius = 8, .offset = .{ .x = 0, .y = 4 } });
        try appendCommand(&commands, allocator, .bevel, "button", button.label, rect, 6, palette.highlight, .{ .z = 7, .text_size = 18 });
        if (button.outlined) {
            try appendCommand(&commands, allocator, .outline, "button", button.label, rect, 6, palette.focus, .{ .z = 8, .outline_width = 2 });
        }
    }

    return .{
        .commands = try commands.toOwnedSlice(allocator),
        .theme = theme,
        .mode = mode,
        .viewport = viewport,
    };
}

fn projectGeneric(allocator: std.mem.Allocator, semantic: SemanticTree, viewport: Viewport) !RenderTrace {
    if (usesGenericTodoLayout(semantic)) return projectGenericTodoLayout(allocator, semantic, viewport);

    const theme: Theme = .professional;
    const mode: Mode = .light;
    const palette = Palette.forTheme(theme, mode);
    var commands = std.ArrayList(TraceCommand).empty;
    errdefer commands.deinit(allocator);

    const display_text = genericDisplayText(semantic);
    const display_line_count = displayTextLineCount(display_text);
    const terminal = display_line_count > 1;
    const card = if (terminal)
        geometry.Rect{ .x = 110, .y = 80, .w = 780, .h = 760 }
    else
        geometry.Rect{ .x = 160, .y = 120, .w = 680, .h = 620 };
    try appendCommand(&commands, allocator, .shadow, "main_card", "", card, 12, palette.shadow, .{
        .z = 4,
        .blur_radius = 10,
        .offset = .{ .x = 0, .y = 10 },
    });
    try appendCommand(&commands, allocator, .bevel, "main_card", "", card, 12, palette.highlight, .{ .z = 5 });

    if (display_text.len != 0) {
        const role: []const u8 = if (terminal) "terminal_text" else "plain_text";
        const rect = if (terminal)
            geometry.Rect{ .x = 150, .y = 120, .w = 700, .h = @min(500, @as(f32, @floatFromInt(display_line_count)) * 34) }
        else
            geometry.Rect{ .x = 210, .y = 168, .w = 580, .h = 56 };
        try appendCommand(&commands, allocator, .bevel, role, display_text, rect, 0, colors.ColorPremul.rgba(0, 0, 0, 0), .{ .z = 9, .text_size = if (terminal) 26 else 34 });
    }

    if (terminal and containsVisible(display_text, "PONG")) {
        const labels = [_][]const u8{ "up", "down", "serve", "tick", "restart" };
        for (labels, 0..) |label, index| {
            const rect = geometry.Rect{
                .x = 150 + @as(f32, @floatFromInt(index)) * 140,
                .y = 760,
                .w = 122,
                .h = 48,
            };
            try appendCommand(&commands, allocator, .shadow, "button", label, rect, 10, palette.shadow, .{ .z = 5, .blur_radius = 8, .offset = .{ .x = 0, .y = 4 } });
            try appendCommand(&commands, allocator, .bevel, "button", label, rect, 10, palette.highlight, .{ .z = 7 });
        }
    }

    const text_bottom: f32 = if (display_text.len == 0)
        168
    else if (terminal)
        120 + @min(500, @as(f32, @floatFromInt(display_line_count)) * 34)
    else
        224;
    const input_start_y: f32 = @max(270, text_bottom + 36);
    for (semantic.inputs, 0..) |input, index| {
        const y = input_start_y + @as(f32, @floatFromInt(index)) * 68;
        const rect = geometry.Rect{ .x = 230, .y = y, .w = 540, .h = 54 };
        const label = if (input.text.len != 0) input.text else input.placeholder;
        try appendCommand(&commands, allocator, .cutout_rounded_rect, "text_input", label, rect, 10, palette.surface, .{ .z = 6, .alpha = palette.surface.a, .text_size = 20 });
        try appendCommand(&commands, allocator, .inner_shadow, "text_input", label, rect, 10, palette.shadow, .{ .z = 5, .blur_radius = 10 });
        try appendCommand(&commands, allocator, .bevel, "text_input", label, rect, 10, palette.highlight, .{ .z = 7, .text_size = 20, .caret_visible = input.focused and input.caret_visible, .caret_text = input.text });
        if (input.focused) {
            try appendCommand(&commands, allocator, .outline, "text_input", label, rect, 10, palette.focus, .{ .z = 8, .outline_width = 2 });
        }
    }

    const button_gap: f32 = if (semantic.inputs.len == 0) 0 else 28;
    const dense_checkbox_list = semantic.inputs.len != 0 and semantic.checkboxes.len > 1 and semantic.buttons.len >= 2;
    const checkbox_start_y: f32 = if (dense_checkbox_list)
        input_start_y + @as(f32, @floatFromInt(semantic.inputs.len)) * 68 + 18
    else
        @max(
            input_start_y + @as(f32, @floatFromInt(semantic.inputs.len)) * 68 + button_gap,
            text_bottom + 44,
        );
    const checkbox_row_h: f32 = 48;
    for (semantic.checkboxes, 0..) |checkbox, index| {
        const rect = if (dense_checkbox_list and index > 0)
            geometry.Rect{ .x = 180, .y = 188 + @as(f32, @floatFromInt(index - 1)) * 34, .w = 26, .h = 26 }
        else
            geometry.Rect{ .x = 240, .y = checkbox_start_y + @as(f32, @floatFromInt(index)) * checkbox_row_h, .w = 26, .h = 26 };
        try appendCommand(&commands, allocator, .cutout_rounded_rect, "checkbox", checkbox.label, rect, 6, palette.surface, .{ .z = 6, .alpha = palette.surface.a });
        try appendCommandIcon(&commands, allocator, .svg_circle, "checkbox", checkbox.label, "checkbox_active", rect, 13, palette.focus, .{ .z = 8, .outline_width = 2 });
        if (checkbox.checked) {
            try appendCommandIcon(&commands, allocator, .svg_path, "checkbox", checkbox.label, "checkbox_completed", rect, 6, palette.focus, .{ .z = 9 });
        }
    }

    if (semantic.svg_clicks.len != 0 or semantic.svg_circles.len != 0) {
        const canvas = geometry.Rect{ .x = 270, .y = 330, .w = 460, .h = 300 };
        try appendCommand(&commands, allocator, .cutout_rounded_rect, "svg_canvas", "canvas", canvas, 8, colors.ColorPremul.rgba(0.93, 0.96, 1.0, 1), .{ .z = 4 });
        try appendCommand(&commands, allocator, .bevel, "svg_canvas", "", canvas, 8, palette.highlight, .{ .z = 5 });
        try appendCommand(&commands, allocator, .outline, "svg_canvas", "", canvas, 8, colors.ColorPremul.rgba(0.35, 0.45, 0.58, 1), .{ .z = 6, .outline_width = 2 });
        for (semantic.svg_circles) |circle| {
            const r = if (circle.r > 0) circle.r else 20;
            const rect = geometry.Rect{
                .x = canvas.x + circle.cx - r,
                .y = canvas.y + circle.cy - r,
                .w = r * 2,
                .h = r * 2,
            };
            try appendCommand(&commands, allocator, .bevel, "svg_drawn_circle", "", rect, r, colors.ColorPremul.rgba(0.20, 0.60, 0.86, 0.85), .{ .z = 7 });
            try appendCommand(&commands, allocator, .svg_circle, "svg_drawn_circle", "", rect, r, colors.ColorPremul.rgba(0.12, 0.24, 0.35, 1), .{ .z = 8, .outline_width = 2 });
        }
    }

    const checkbox_button_gap: f32 = if (semantic.checkboxes.len == 0) 0 else 22;
    const checkbox_flow_count: usize = if (dense_checkbox_list and semantic.checkboxes.len != 0) 1 else semantic.checkboxes.len;
    const button_start_y: f32 = @max(360, checkbox_start_y + @as(f32, @floatFromInt(checkbox_flow_count)) * checkbox_row_h + checkbox_button_gap);
    for (semantic.buttons, 0..) |button, index| {
        const row = index / 4;
        const col = index % 4;
        const rect = geometry.Rect{
            .x = 230 + @as(f32, @floatFromInt(col)) * 150,
            .y = button_start_y + @as(f32, @floatFromInt(row)) * 58,
            .w = 132,
            .h = 44,
        };
        try appendCommand(&commands, allocator, .shadow, "button", button.label, rect, 8, palette.shadow, .{ .z = 5, .blur_radius = 8, .offset = .{ .x = 0, .y = 4 } });
        try appendCommand(&commands, allocator, .bevel, "button", button.label, rect, 8, palette.highlight, .{ .z = 7, .text_size = 18 });
        if (button.outlined) {
            try appendCommand(&commands, allocator, .outline, "button", button.label, rect, 8, palette.focus, .{ .z = 8, .outline_width = 2 });
        }
    }

    return .{
        .commands = try commands.toOwnedSlice(allocator),
        .theme = theme,
        .mode = mode,
        .viewport = viewport,
    };
}

fn genericDisplayText(semantic: SemanticTree) []const u8 {
    const text = std.mem.trim(u8, semantic.rendered_text, " \t\r\n");
    if (semantic.buttons.len == 0) return text;
    var cursor: usize = 0;
    while (cursor < text.len) {
        if (text[cursor] == '[') {
            const close = std.mem.indexOfScalarPos(u8, text, cursor, ']') orelse return "";
            cursor = close + 1;
            continue;
        }
        const next_control = std.mem.indexOfScalarPos(u8, text, cursor, '[') orelse text.len;
        const segment = std.mem.trim(u8, text[cursor..next_control], " \t\r\n");
        if (segment.len != 0) {
            return segment;
        }
        cursor = next_control;
    }
    return "";
}

fn displayTextLineCount(text: []const u8) usize {
    if (text.len == 0) return 0;
    var count: usize = 1;
    for (text) |byte| {
        if (byte == '\n') count += 1;
    }
    return count;
}

fn inputLabelSlice(input: SemanticInput, max_bytes: usize) []const u8 {
    if (input.text.len != 0) return visibleLabelSlice(input.text, max_bytes);
    if (input.focused) return "";
    return visibleLabelSlice(input.placeholder, max_bytes);
}

fn visibleLabelSlice(label: []const u8, max_bytes: usize) []const u8 {
    const trimmed = std.mem.trim(u8, label, " \t\r\n");
    if (trimmed.len <= max_bytes) return trimmed;
    var end = max_bytes;
    while (end > 0 and (trimmed[end] & 0xc0) == 0x80) end -= 1;
    return trimmed[0..end];
}

fn todoFooterCountSlice(text: []const u8) []const u8 {
    const items_pos = std.mem.indexOf(u8, text, "itemsleft") orelse
        std.mem.indexOf(u8, text, "itemleft") orelse return "";
    var start = items_pos;
    while (start > 0 and std.ascii.isDigit(text[start - 1])) start -= 1;
    if (start == items_pos) return "";
    const suffix_len: usize = if (std.mem.startsWith(u8, text[items_pos..], "itemsleft")) "itemsleft".len else "itemleft".len;
    return text[start .. items_pos + suffix_len];
}

fn todoRowLabelFromRenderedText(text: []const u8, row_index: usize) ?[]const u8 {
    var current_row: usize = 0;
    var cursor: usize = 0;
    while (cursor <= text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, cursor, '\n') orelse text.len;
        defer cursor = line_end + 1;
        const line = std.mem.trim(u8, text[cursor..line_end], " \t\r\n");
        if (line.len == 0) continue;
        if (containsVisible(line, "todos")) continue;
        if (std.mem.indexOf(u8, line, "itemsleft") != null or std.mem.indexOf(u8, line, "itemleft") != null) continue;
        if (containsVisible(line, "Double-click")) continue;
        if (containsVisible(line, "Created by")) continue;
        if (containsVisible(line, "Part of")) continue;
        if (containsVisible(line, "All") and containsVisible(line, "Active") and containsVisible(line, "Completed")) continue;
        if (current_row == row_index) return line;
        current_row += 1;
    }
    return null;
}

const CommandOptions = struct {
    z: f32 = 0,
    blur_radius: f32 = 0,
    spread: f32 = 0,
    offset: geometry.Vec2 = .{},
    alpha: f32 = 1,
    outline_width: f32 = 0,
    text_size: f32 = 0,
    caret_visible: bool = false,
    caret_text: []const u8 = "",
};

fn appendCommand(
    list: *std.ArrayList(TraceCommand),
    allocator: std.mem.Allocator,
    kind: renderer.CustomKind,
    role: []const u8,
    label: []const u8,
    rect: geometry.Rect,
    radius: f32,
    color: colors.ColorPremul,
    options: CommandOptions,
) !void {
    try list.append(allocator, .{
        .base = .{
            .node_id = @intCast(list.items.len + 1),
            .kind = kind,
            .rect = rect,
            .radius = .uniform(radius),
            .color = color,
            .z = options.z,
            .blur_radius = options.blur_radius,
            .spread = options.spread,
            .offset = options.offset,
            .alpha = options.alpha,
            .outline_width = options.outline_width,
        },
        .role = role,
        .label = label,
        .text_size = options.text_size,
        .caret_visible = options.caret_visible,
        .caret_text = options.caret_text,
    });
}

fn appendCommandIcon(
    list: *std.ArrayList(TraceCommand),
    allocator: std.mem.Allocator,
    kind: renderer.CustomKind,
    role: []const u8,
    label: []const u8,
    icon_name: []const u8,
    rect: geometry.Rect,
    radius: f32,
    color: colors.ColorPremul,
    options: CommandOptions,
) !void {
    try list.append(allocator, .{
        .base = .{
            .node_id = @intCast(list.items.len + 1),
            .kind = kind,
            .rect = rect,
            .radius = .uniform(radius),
            .color = color,
            .z = options.z,
            .blur_radius = options.blur_radius,
            .spread = options.spread,
            .offset = options.offset,
            .alpha = options.alpha,
            .outline_width = options.outline_width,
            .icon_name = icon_name,
        },
        .role = role,
        .label = label,
        .text_size = options.text_size,
        .caret_visible = options.caret_visible,
        .caret_text = options.caret_text,
    });
}

const Palette = struct {
    background: colors.ColorPremul,
    surface: colors.ColorPremul,
    text: colors.ColorPremul,
    title: colors.ColorPremul,
    shadow: colors.ColorPremul,
    highlight: colors.ColorPremul,
    focus: colors.ColorPremul,

    fn forTheme(theme: Theme, mode: Mode) Palette {
        return switch (theme) {
            .professional => .{
                .background = if (mode == .light) colors.ColorPremul.rgba(0.96, 0.95, 0.93, 1) else colors.ColorPremul.rgba(0.08, 0.08, 0.09, 1),
                .surface = if (mode == .light) colors.ColorPremul.rgba(1, 0.99, 0.97, 1) else colors.ColorPremul.rgba(0.16, 0.16, 0.18, 1),
                .text = if (mode == .light) colors.ColorPremul.rgba(0.25, 0.23, 0.22, 1) else colors.ColorPremul.rgba(0.9, 0.88, 0.84, 1),
                .title = colors.ColorPremul.rgba(0.78, 0.42, 0.23, 1),
                .shadow = colors.ColorPremul.rgba(0.08, 0.07, 0.06, 0.36),
                .highlight = colors.ColorPremul.rgba(1, 0.95, 0.86, 0.55),
                .focus = colors.ColorPremul.rgba(0.32, 0.52, 0.85, 0.65),
            },
            .glassmorphism => .{
                .background = if (mode == .light) colors.ColorPremul.rgba(0.82, 0.88, 1, 1) else colors.ColorPremul.rgba(0.07, 0.08, 0.18, 1),
                .surface = if (mode == .light) colors.ColorPremul.rgba(0.82, 0.9, 1, 0.50) else colors.ColorPremul.rgba(0.28, 0.34, 0.52, 0.48),
                .text = colors.ColorPremul.rgba(0.92, 0.94, 1, 1),
                .title = colors.ColorPremul.rgba(0.58, 0.47, 1, 1),
                .shadow = colors.ColorPremul.rgba(0.02, 0.03, 0.08, 0.42),
                .highlight = colors.ColorPremul.rgba(1, 1, 1, 0.7),
                .focus = colors.ColorPremul.rgba(0.42, 0.72, 1, 0.72),
            },
            .neobrutalism => .{
                .background = colors.ColorPremul.rgba(1, 0.88, 0.25, 1),
                .surface = colors.ColorPremul.rgba(1, 0.96, 0.82, 1),
                .text = colors.ColorPremul.rgba(0.02, 0.02, 0.02, 1),
                .title = colors.ColorPremul.rgba(0.9, 0.05, 0.16, 1),
                .shadow = colors.ColorPremul.rgba(0, 0, 0, 0.75),
                .highlight = colors.ColorPremul.rgba(0.05, 0.05, 0.05, 1),
                .focus = colors.ColorPremul.rgba(0, 0.26, 1, 1),
            },
            .neumorphism => .{
                .background = colors.ColorPremul.rgba(0.86, 0.88, 0.91, 1),
                .surface = colors.ColorPremul.rgba(0.88, 0.9, 0.94, 1),
                .text = colors.ColorPremul.rgba(0.36, 0.38, 0.42, 1),
                .title = colors.ColorPremul.rgba(0.5, 0.53, 0.58, 1),
                .shadow = colors.ColorPremul.rgba(0.42, 0.45, 0.5, 0.35),
                .highlight = colors.ColorPremul.rgba(1, 1, 1, 0.75),
                .focus = colors.ColorPremul.rgba(0.48, 0.6, 0.78, 0.5),
            },
        };
    }
};

pub const PixelImage = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    pixels: []u8,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, clear_color: colors.ColorPremul) !PixelImage {
        const pixels = try allocator.alloc(u8, width * height * 4);
        var image = PixelImage{ .allocator = allocator, .width = width, .height = height, .pixels = pixels };
        image.clear(clear_color);
        return image;
    }

    pub fn deinit(self: *PixelImage) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn clear(self: *PixelImage, color: colors.ColorPremul) void {
        const rgba = unpackColor(color);
        var index: usize = 0;
        while (index < self.pixels.len) : (index += 4) {
            self.pixels[index + 0] = rgba.r;
            self.pixels[index + 1] = rgba.g;
            self.pixels[index + 2] = rgba.b;
            self.pixels[index + 3] = rgba.a;
        }
    }

    pub fn renderTrace(self: *PixelImage, trace: RenderTrace) void {
        const palette = Palette.forTheme(trace.theme, trace.mode);
        self.clear(palette.background);
        for (trace.commands) |command| {
            switch (command.base.kind) {
                .shadow => self.fillRect(offsetRect(command.base.rect, command.base.offset), command.base.color),
                .inner_shadow, .outline => self.strokeRect(command.base.rect, @max(1, command.base.outline_width), command.base.color),
                .cutout_rounded_rect, .bevel, .glow => self.fillRect(command.base.rect, command.base.color),
                .caret, .selection => self.fillRect(command.base.rect, command.base.color),
                .svg_circle => self.strokeCircle(command.base.rect, @max(1, command.base.outline_width), command.base.color),
                .svg_path => self.strokeCheck(command.base.rect, @max(2, command.base.outline_width + 1), command.base.color),
            }
        }
    }

    fn fillRect(self: *PixelImage, rect: geometry.Rect, color: colors.ColorPremul) void {
        const rgba = unpackColor(color);
        const x0 = clampInt(@as(i32, @intFromFloat(@floor(rect.x))), 0, @intCast(self.width));
        const y0 = clampInt(@as(i32, @intFromFloat(@floor(rect.y))), 0, @intCast(self.height));
        const x1 = clampInt(@as(i32, @intFromFloat(@ceil(rect.right()))), 0, @intCast(self.width));
        const y1 = clampInt(@as(i32, @intFromFloat(@ceil(rect.bottom()))), 0, @intCast(self.height));
        var y = y0;
        while (y < y1) : (y += 1) {
            var x = x0;
            while (x < x1) : (x += 1) {
                self.blendPixel(@intCast(x), @intCast(y), rgba);
            }
        }
    }

    fn strokeRect(self: *PixelImage, rect: geometry.Rect, width: f32, color: colors.ColorPremul) void {
        self.fillRect(.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = width }, color);
        self.fillRect(.{ .x = rect.x, .y = rect.bottom() - width, .w = rect.w, .h = width }, color);
        self.fillRect(.{ .x = rect.x, .y = rect.y, .w = width, .h = rect.h }, color);
        self.fillRect(.{ .x = rect.right() - width, .y = rect.y, .w = width, .h = rect.h }, color);
    }

    fn strokeCircle(self: *PixelImage, rect: geometry.Rect, width: f32, color: colors.ColorPremul) void {
        const rgba = unpackColor(color);
        const cx = rect.x + rect.w * 0.5;
        const cy = rect.y + rect.h * 0.5;
        const radius = @min(rect.w, rect.h) * 0.5 - width * 0.5;
        const half = width * 0.5;
        const x0 = clampInt(@as(i32, @intFromFloat(@floor(rect.x))), 0, @intCast(self.width));
        const y0 = clampInt(@as(i32, @intFromFloat(@floor(rect.y))), 0, @intCast(self.height));
        const x1 = clampInt(@as(i32, @intFromFloat(@ceil(rect.right()))), 0, @intCast(self.width));
        const y1 = clampInt(@as(i32, @intFromFloat(@ceil(rect.bottom()))), 0, @intCast(self.height));
        var y = y0;
        while (y < y1) : (y += 1) {
            var x = x0;
            while (x < x1) : (x += 1) {
                const dx = (@as(f32, @floatFromInt(x)) + 0.5) - cx;
                const dy = (@as(f32, @floatFromInt(y)) + 0.5) - cy;
                const distance = @sqrt(dx * dx + dy * dy);
                if (@abs(distance - radius) <= half) self.blendPixel(@intCast(x), @intCast(y), rgba);
            }
        }
    }

    fn strokeCheck(self: *PixelImage, rect: geometry.Rect, width: f32, color: colors.ColorPremul) void {
        const a = geometry.Vec2{ .x = rect.x + rect.w * 0.24, .y = rect.y + rect.h * 0.55 };
        const b = geometry.Vec2{ .x = rect.x + rect.w * 0.44, .y = rect.y + rect.h * 0.74 };
        const c = geometry.Vec2{ .x = rect.x + rect.w * 0.78, .y = rect.y + rect.h * 0.28 };
        self.strokeLine(a, b, width, color);
        self.strokeLine(b, c, width, color);
    }

    fn strokeLine(self: *PixelImage, a: geometry.Vec2, b: geometry.Vec2, width: f32, color: colors.ColorPremul) void {
        const rgba = unpackColor(color);
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len2 = dx * dx + dy * dy;
        if (len2 <= 0.001) return;
        const min_x = @min(a.x, b.x) - width;
        const min_y = @min(a.y, b.y) - width;
        const max_x = @max(a.x, b.x) + width;
        const max_y = @max(a.y, b.y) + width;
        const x0 = clampInt(@as(i32, @intFromFloat(@floor(min_x))), 0, @intCast(self.width));
        const y0 = clampInt(@as(i32, @intFromFloat(@floor(min_y))), 0, @intCast(self.height));
        const x1 = clampInt(@as(i32, @intFromFloat(@ceil(max_x))), 0, @intCast(self.width));
        const y1 = clampInt(@as(i32, @intFromFloat(@ceil(max_y))), 0, @intCast(self.height));
        var y = y0;
        while (y < y1) : (y += 1) {
            var x = x0;
            while (x < x1) : (x += 1) {
                const px = @as(f32, @floatFromInt(x)) + 0.5;
                const py = @as(f32, @floatFromInt(y)) + 0.5;
                const t = std.math.clamp(((px - a.x) * dx + (py - a.y) * dy) / len2, 0.0, 1.0);
                const proj_x = a.x + t * dx;
                const proj_y = a.y + t * dy;
                const ddx = px - proj_x;
                const ddy = py - proj_y;
                if (ddx * ddx + ddy * ddy <= width * width * 0.25) self.blendPixel(@intCast(x), @intCast(y), rgba);
            }
        }
    }

    fn blendPixel(self: *PixelImage, x: usize, y: usize, src: Rgba8) void {
        const index = (y * self.width + x) * 4;
        const alpha = @as(f32, @floatFromInt(src.a)) / 255.0;
        const inv = 1.0 - alpha;
        self.pixels[index + 0] = @intFromFloat(@round(@as(f32, @floatFromInt(src.r)) * alpha + @as(f32, @floatFromInt(self.pixels[index + 0])) * inv));
        self.pixels[index + 1] = @intFromFloat(@round(@as(f32, @floatFromInt(src.g)) * alpha + @as(f32, @floatFromInt(self.pixels[index + 1])) * inv));
        self.pixels[index + 2] = @intFromFloat(@round(@as(f32, @floatFromInt(src.b)) * alpha + @as(f32, @floatFromInt(self.pixels[index + 2])) * inv));
        self.pixels[index + 3] = 255;
    }
};

fn offsetRect(rect: geometry.Rect, offset: geometry.Vec2) geometry.Rect {
    return .{ .x = rect.x + offset.x, .y = rect.y + offset.y, .w = rect.w, .h = rect.h };
}

const Rgba8 = struct { r: u8, g: u8, b: u8, a: u8 };

fn unpackColor(color: colors.ColorPremul) Rgba8 {
    return .{
        .r = @intFromFloat(@round(std.math.clamp(color.r, 0, 1) * 255)),
        .g = @intFromFloat(@round(std.math.clamp(color.g, 0, 1) * 255)),
        .b = @intFromFloat(@round(std.math.clamp(color.b, 0, 1) * 255)),
        .a = @intFromFloat(@round(std.math.clamp(color.a, 0, 1) * 255)),
    };
}

fn clampInt(value: i32, min_value: i32, max_value: i32) i32 {
    return @min(max_value, @max(min_value, value));
}

pub fn pngAlloc(allocator: std.mem.Allocator, image: PixelImage) ![]u8 {
    var raw = std.ArrayList(u8).empty;
    defer raw.deinit(allocator);
    try raw.ensureTotalCapacity(allocator, (image.width * 3 + 1) * image.height);
    var y: usize = 0;
    while (y < image.height) : (y += 1) {
        try raw.append(allocator, 0);
        var x: usize = 0;
        while (x < image.width) : (x += 1) {
            const index = (y * image.width + x) * 4;
            try raw.appendSlice(allocator, image.pixels[index .. index + 3]);
        }
    }

    var zlib = std.ArrayList(u8).empty;
    defer zlib.deinit(allocator);
    try zlib.appendSlice(allocator, &.{ 0x78, 0x01 });
    var cursor: usize = 0;
    while (cursor < raw.items.len) {
        const block_size = @min(raw.items.len - cursor, 65535);
        const block_len: u16 = @intCast(block_size);
        try zlib.append(allocator, if (cursor + block_size >= raw.items.len) 1 else 0);
        try appendU16Le(&zlib, allocator, block_len);
        try appendU16Le(&zlib, allocator, ~block_len);
        try zlib.appendSlice(allocator, raw.items[cursor .. cursor + block_size]);
        cursor += block_size;
    }
    try appendU32Be(&zlib, allocator, adler32(raw.items));

    var png = std.ArrayList(u8).empty;
    defer png.deinit(allocator);
    try png.appendSlice(allocator, &.{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' });
    var ihdr: [13]u8 = undefined;
    writeU32Be(ihdr[0..4], @intCast(image.width));
    writeU32Be(ihdr[4..8], @intCast(image.height));
    ihdr[8] = 8;
    ihdr[9] = 2;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try appendChunk(&png, allocator, "IHDR", &ihdr);
    try appendChunk(&png, allocator, "IDAT", zlib.items);
    try appendChunk(&png, allocator, "IEND", &.{});
    return try png.toOwnedSlice(allocator);
}

fn appendChunk(png: *std.ArrayList(u8), allocator: std.mem.Allocator, kind: *const [4:0]u8, data: []const u8) !void {
    try appendU32Be(png, allocator, @intCast(data.len));
    const kind_bytes = kind[0..4];
    try png.appendSlice(allocator, kind_bytes);
    try png.appendSlice(allocator, data);
    var crc_input = std.ArrayList(u8).empty;
    defer crc_input.deinit(allocator);
    try crc_input.appendSlice(allocator, kind_bytes);
    try crc_input.appendSlice(allocator, data);
    try appendU32Be(png, allocator, crc32(crc_input.items));
}

fn appendU16Le(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    try list.append(allocator, @intCast(value & 0xff));
    try list.append(allocator, @intCast((value >> 8) & 0xff));
}

fn appendU32Be(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    writeU32Be(&buf, value);
    try list.appendSlice(allocator, &buf);
}

fn writeU32Be(buf: []u8, value: u32) void {
    buf[0] = @intCast((value >> 24) & 0xff);
    buf[1] = @intCast((value >> 16) & 0xff);
    buf[2] = @intCast((value >> 8) & 0xff);
    buf[3] = @intCast(value & 0xff);
}

fn adler32(bytes: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    for (bytes) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

fn crc32(bytes: []const u8) u32 {
    var crc: u32 = 0xffffffff;
    for (bytes) |byte| {
        crc ^= byte;
        var bit: u8 = 0;
        while (bit < 8) : (bit += 1) {
            const mask: u32 = 0 -% (crc & 1);
            crc = (crc >> 1) ^ (0xedb88320 & mask);
        }
    }
    return ~crc;
}

fn renderedTextAlloc(allocator: std.mem.Allocator, values: []const bridge.RuntimeValue, root_id: bridge.ValueId) ![]u8 {
    if (root_id >= values.len) return try allocator.dupe(u8, "");
    const root = values[root_id];
    switch (root) {
        .element => |element| {
            if (findElementField(element, "rendered_text")) |id| {
                if (id < values.len) return valueTextAlloc(allocator, values, values[id]);
            }
        },
        else => {},
    }
    return valueTextAlloc(allocator, values, root);
}

fn readableRenderedTextAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, text.len);

    var line_start: usize = 0;
    var wrote_line = false;
    while (line_start <= text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = text[line_start..line_end];
        if (!isInputMarkerLine(line) and !isShortDecorativeMarkerLine(line)) {
            if (wrote_line) try out.append(allocator, '\n');
            var previous: ?u8 = null;
            var cursor: usize = 0;
            while (cursor < line.len) {
                if (styleRunPrefixLength(line[cursor..])) |prefix_len| {
                    cursor += prefix_len;
                    continue;
                }
                if (cursor + 1 < line.len and line[cursor] == '<' and line[cursor + 1] == '>') {
                    const next = if (cursor + 2 < line.len) line[cursor + 2] else null;
                    if (previous) |prev| {
                        if (!std.ascii.isWhitespace(prev) and next != null and !std.ascii.isWhitespace(next.?)) {
                            try out.append(allocator, ' ');
                            previous = ' ';
                        }
                    }
                    cursor += 2;
                    continue;
                }
                const byte = line[cursor];
                if (byte >= 0x80) {
                    cursor += utf8SequenceLength(byte);
                    continue;
                }
                if (byte == '<' or byte == '>') {
                    cursor += 1;
                    continue;
                }
                if (previous) |prev| {
                    if (needsSyntheticDisplaySpace(prev, byte) or needsSemanticWordBoundary(out.items, line[cursor..])) {
                        try out.append(allocator, ' ');
                    }
                }
                try out.append(allocator, byte);
                previous = byte;
                cursor += 1;
            }
            wrote_line = true;
        }
        if (line_end == text.len) break;
        line_start = line_end + 1;
    }
    return try out.toOwnedSlice(allocator);
}

fn isInputMarkerLine(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    return trimmed.len >= 2 and trimmed[0] == '<' and trimmed[trimmed.len - 1] == '>';
}

fn isShortDecorativeMarkerLine(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0 or trimmed.len > 4) return false;
    for (trimmed) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '#' or byte == '.') return false;
    }
    return true;
}

fn needsSyntheticDisplaySpace(previous: u8, current: u8) bool {
    if (std.ascii.isWhitespace(previous) or std.ascii.isWhitespace(current)) return false;
    if (std.ascii.isLower(previous) and std.ascii.isDigit(current)) return true;
    if (std.ascii.isDigit(previous) and std.ascii.isLower(current)) return true;
    if (std.ascii.isLower(previous) and std.ascii.isUpper(current)) return true;
    return false;
}

fn needsSemanticWordBoundary(written: []const u8, remaining: []const u8) bool {
    return (std.mem.endsWith(u8, written, "items") and std.mem.startsWith(u8, remaining, "left"));
}

fn utf8SequenceLength(first_byte: u8) usize {
    if ((first_byte & 0b1110_0000) == 0b1100_0000) return 2;
    if ((first_byte & 0b1111_0000) == 0b1110_0000) return 3;
    if ((first_byte & 0b1111_1000) == 0b1111_0000) return 4;
    return 1;
}

fn collectSemanticValueById(
    allocator: std.mem.Allocator,
    values: []const bridge.RuntimeValue,
    events: []const bridge.EventBinding,
    id: bridge.ValueId,
    visited: []bool,
    inputs: *std.ArrayList(SemanticInput),
    buttons: *std.ArrayList(SemanticButton),
    checkboxes: *std.ArrayList(SemanticCheckbox),
    svg_clicks: *std.ArrayList(SemanticSvgClick),
    svg_circles: *std.ArrayList(SemanticSvgCircle),
) anyerror!void {
    if (id >= values.len) return;
    const index: usize = @intCast(id);
    if (visited[index]) return;
    visited[index] = true;
    try collectSemanticValue(allocator, values, events, values[index], visited, inputs, buttons, checkboxes, svg_clicks, svg_circles);
}

fn collectSemanticValue(
    allocator: std.mem.Allocator,
    values: []const bridge.RuntimeValue,
    events: []const bridge.EventBinding,
    value: bridge.RuntimeValue,
    visited: []bool,
    inputs: *std.ArrayList(SemanticInput),
    buttons: *std.ArrayList(SemanticButton),
    checkboxes: *std.ArrayList(SemanticCheckbox),
    svg_clicks: *std.ArrayList(SemanticSvgClick),
    svg_circles: *std.ArrayList(SemanticSvgCircle),
) anyerror!void {
    switch (value) {
        .list => |items| for (items) |id| {
            try collectSemanticValueById(allocator, values, events, id, visited, inputs, buttons, checkboxes, svg_clicks, svg_circles);
        },
        .record => |fields| for (fields) |field| {
            try collectSemanticValueById(allocator, values, events, field.value, visited, inputs, buttons, checkboxes, svg_clicks, svg_circles);
        },
        .element => |element| {
            if (std.mem.eql(u8, element.kind, "text_input")) {
                try inputs.append(allocator, .{
                    .text = try cleanControlTextAlloc(allocator, try valueFieldTextAlloc(allocator, values, element, "text")),
                    .placeholder = try cleanControlTextAlloc(allocator, try valueFieldTextAlloc(allocator, values, element, "placeholder")),
                    .focused = elementBoolField(values, element, "focused"),
                    .disabled = elementBoolField(values, element, "disabled"),
                    .caret_visible = true,
                    .handle = textInputHandle(events, values, element),
                });
            } else if (std.mem.eql(u8, element.kind, "button")) {
                const link = if (valueFieldNumber(values, element, "press_link")) |press_link|
                    @as(u64, @intFromFloat(press_link))
                else
                    null;
                try buttons.append(allocator, .{
                    .label = try valueFieldTextAlloc(allocator, values, element, "label"),
                    .disabled = elementBoolField(values, element, "disabled"),
                    .outlined = elementBoolField(values, element, "outlined") or elementHasSelectedStyle(values, element),
                    .link = link,
                    .handle = if (link) |button_link| buttonHandle(events, button_link) else null,
                });
            } else if (std.mem.eql(u8, element.kind, "checkbox")) {
                try checkboxes.append(allocator, .{
                    .label = try valueFieldTextAlloc(allocator, values, element, "label"),
                    .checked = elementBoolField(values, element, "checked"),
                });
            } else if (std.mem.eql(u8, element.kind, "svg_circle")) {
                try svg_circles.append(allocator, .{
                    .cx = @floatCast(valueFieldNumber(values, element, "cx") orelse 0),
                    .cy = @floatCast(valueFieldNumber(values, element, "cy") orelse 0),
                    .r = @floatCast(valueFieldNumber(values, element, "r") orelse 20),
                });
            } else if (std.mem.eql(u8, element.kind, "container")) {
                if (valueFieldNumber(values, element, "click_link")) |link| {
                    const width = valueFieldNumber(values, element, "width") orelse 0;
                    const height = valueFieldNumber(values, element, "height") orelse 0;
                    if (width > 0 and height > 0) {
                        const link_id: u64 = @intFromFloat(link);
                        try svg_clicks.append(allocator, .{ .link = link_id, .handle = svgClickHandle(events, link_id) });
                    }
                }
            }
            for (element.args) |field| {
                try collectSemanticValueById(allocator, values, events, field.value, visited, inputs, buttons, checkboxes, svg_clicks, svg_circles);
            }
        },
        else => {},
    }
}

fn collectSvgClickEvents(
    allocator: std.mem.Allocator,
    values: []const bridge.RuntimeValue,
    events: []const bridge.EventBinding,
    svg_clicks: *std.ArrayList(SemanticSvgClick),
) !void {
    for (events) |event| {
        if (!std.mem.eql(u8, event.event_name, "click")) continue;
        if (event.source_value >= values.len) continue;
        switch (values[event.source_value]) {
            .element => |element| if (std.mem.eql(u8, element.kind, "svg")) {
                try svg_clicks.append(allocator, .{ .link = event.id, .handle = event.handle });
            },
            else => {},
        }
    }
}

fn svgClickHandle(events: []const bridge.EventBinding, link: u64) ?bridge.ControlHandle {
    for (events) |event| {
        if (!std.mem.eql(u8, event.event_name, "click")) continue;
        if (event.id == link) return event.handle;
    }
    return null;
}

fn buttonHandle(events: []const bridge.EventBinding, link: u64) ?bridge.ControlHandle {
    for (events) |event| {
        if (!std.mem.eql(u8, event.event_name, "click")) continue;
        if (event.id == link) return event.handle;
    }
    return null;
}

fn textInputHandle(events: []const bridge.EventBinding, values: []const bridge.RuntimeValue, element: bridge.ElementNode) ?bridge.TextInputHandle {
    const change_link = elementLinkField(values, element, "change_link") orelse return null;
    const key_link = elementLinkField(values, element, "key_link") orelse change_link;
    const change = eventHandle(events, "change_text", change_link) orelse return null;
    const key = eventHandle(events, "key_down", key_link) orelse change;
    const blur = if (elementLinkField(values, element, "blur_link")) |link| eventHandle(events, "blur", link) else null;
    const focus = if (elementLinkField(values, element, "focus_link")) |link| eventHandle(events, "focus", link) else null;
    return .{
        .change = change,
        .key = key,
        .blur = blur,
        .focus = focus,
    };
}

fn eventHandle(events: []const bridge.EventBinding, event_name: []const u8, link: u64) ?bridge.ControlHandle {
    for (events) |event| {
        if (!std.mem.eql(u8, event.event_name, event_name)) continue;
        if (event.id == link) return event.handle;
    }
    return null;
}

fn elementLinkField(values: []const bridge.RuntimeValue, element: bridge.ElementNode, name: []const u8) ?u64 {
    if (valueFieldNumber(values, element, name)) |link| return @intFromFloat(link);
    return null;
}

fn valueFieldTextAlloc(allocator: std.mem.Allocator, values: []const bridge.RuntimeValue, element: bridge.ElementNode, name: []const u8) ![]u8 {
    const id = findElementField(element, name) orelse return try allocator.dupe(u8, "");
    if (id >= values.len) return try allocator.dupe(u8, "");
    return valueTextAlloc(allocator, values, values[id]);
}

fn valueFieldNumber(values: []const bridge.RuntimeValue, element: bridge.ElementNode, name: []const u8) ?f64 {
    const id = findElementField(element, name) orelse return null;
    if (id >= values.len) return null;
    return switch (values[id]) {
        .number => |number| number,
        else => null,
    };
}

fn cleanControlTextAlloc(allocator: std.mem.Allocator, raw: []u8) ![]u8 {
    defer allocator.free(raw);
    const prefixes = [_][]const u8{
        "DefaultColor0.2016Regular",
        "DefaultColor0.2016Bold",
        "DefaultColor0.2016Medium",
        "Italic0.68",
    };
    for (prefixes) |prefix| {
        if (std.mem.indexOf(u8, raw, prefix)) |index| {
            return try allocator.dupe(u8, raw[index + prefix.len ..]);
        }
    }
    return try allocator.dupe(u8, raw);
}

fn styleRunPrefixLength(text: []const u8) ?usize {
    const prefixes = [_][]const u8{
        "DefaultColor0.2016Regular",
        "DefaultColor0.2016Bold",
        "DefaultColor0.2016Medium",
        "Italic0.68",
    };
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, text, prefix)) return prefix.len;
    }
    return null;
}

fn valueTextAlloc(allocator: std.mem.Allocator, values: []const bridge.RuntimeValue, value: bridge.RuntimeValue) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try appendValueText(&out.writer, values, value);
    return try out.toOwnedSlice();
}

fn appendValueText(writer: *std.Io.Writer, values: []const bridge.RuntimeValue, value: bridge.RuntimeValue) !void {
    switch (value) {
        .none => {},
        .number => |number| try writer.print("{d}", .{number}),
        .bool => |boolean| try writer.writeAll(if (boolean) "True" else "False"),
        .text => |text| try writer.writeAll(text),
        .symbol => |symbol| try writer.writeAll(symbol),
        .list => |items| for (items) |id| {
            if (id < values.len) try appendValueText(writer, values, values[id]);
        },
        .record => |fields| for (fields) |field| {
            if (field.value < values.len) try appendValueText(writer, values, values[field.value]);
        },
        .element => |element| for (element.args) |field| {
            if (field.value < values.len) try appendValueText(writer, values, values[field.value]);
        },
    }
}

fn findElementField(element: bridge.ElementNode, name: []const u8) ?bridge.ValueId {
    for (element.args) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.value;
    }
    return null;
}

fn elementBoolField(values: []const bridge.RuntimeValue, element: bridge.ElementNode, name: []const u8) bool {
    if (findElementField(element, name)) |id| {
        if (id < values.len) return runtimeBool(values[id]);
    }
    if (findElementField(element, "settings")) |settings_id| {
        if (settings_id < values.len and runtimeRecordBoolField(values, values[settings_id], name)) return true;
    }
    if (std.mem.eql(u8, name, "checked")) {
        const icon_id = findElementField(element, "icon") orelse return false;
        if (icon_id < values.len) return runtimeValueHasCheckedIcon(values, values[icon_id]);
    }
    return false;
}

fn elementHasSelectedStyle(values: []const bridge.RuntimeValue, element: bridge.ElementNode) bool {
    const style_id = findElementField(element, "style") orelse return false;
    if (style_id >= values.len) return false;
    if (runtimeRecordNumberPath(values, values[style_id], &.{ "move", "closer" })) |closer| {
        if (closer > 0) return true;
    }
    if (runtimeRecordNumberPath(values, values[style_id], &.{ "material", "glow", "intensity" })) |intensity| {
        if (intensity > 0) return true;
    }
    return false;
}

fn runtimeBool(value: bridge.RuntimeValue) bool {
    return switch (value) {
        .bool => |b| b,
        .symbol => |symbol| std.mem.eql(u8, symbol, "True") or std.mem.eql(u8, symbol, "true") or std.mem.eql(u8, symbol, "checked"),
        .text => |text| std.mem.eql(u8, text, "True") or std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "checked"),
        else => false,
    };
}

fn runtimeRecordNumberPath(values: []const bridge.RuntimeValue, value: bridge.RuntimeValue, path: []const []const u8) ?f64 {
    if (path.len == 0) return switch (value) {
        .number => |number| number,
        else => null,
    };
    return switch (value) {
        .record => |fields| for (fields) |field| {
            if (std.mem.eql(u8, field.name, path[0]) and field.value < values.len) {
                return runtimeRecordNumberPath(values, values[field.value], path[1..]);
            }
        } else null,
        else => null,
    };
}

fn runtimeRecordBoolField(values: []const bridge.RuntimeValue, value: bridge.RuntimeValue, name: []const u8) bool {
    return switch (value) {
        .record => |fields| for (fields) |field| {
            if (std.mem.eql(u8, field.name, name) and field.value < values.len) return runtimeBool(values[field.value]);
        } else false,
        else => false,
    };
}

fn runtimeValueHasCheckedIcon(values: []const bridge.RuntimeValue, value: bridge.RuntimeValue) bool {
    return switch (value) {
        .text => |text| std.mem.indexOfScalar(u8, text, 'X') != null or std.mem.indexOfScalar(u8, text, 'x') != null,
        .symbol => |symbol| std.mem.indexOfScalar(u8, symbol, 'X') != null or std.mem.indexOfScalar(u8, symbol, 'x') != null,
        .list => |items| for (items) |id| {
            if (id < values.len and runtimeValueHasCheckedIcon(values, values[id])) return true;
        } else false,
        .record => |fields| for (fields) |field| {
            if (field.value < values.len and runtimeValueHasCheckedIcon(values, values[field.value])) return true;
        } else false,
        .element => |element| for (element.args) |field| {
            if (field.value < values.len and runtimeValueHasCheckedIcon(values, values[field.value])) return true;
        } else false,
        else => false,
    };
}

fn freeInputs(allocator: std.mem.Allocator, inputs: []SemanticInput) void {
    for (inputs) |input| {
        if (input.text.len != 0) allocator.free(input.text);
        if (input.placeholder.len != 0) allocator.free(input.placeholder);
    }
}

fn freeButtons(allocator: std.mem.Allocator, buttons: []SemanticButton) void {
    for (buttons) |button| if (button.label.len != 0) allocator.free(button.label);
}

fn freeCheckboxes(allocator: std.mem.Allocator, checkboxes: []SemanticCheckbox) void {
    for (checkboxes) |checkbox| if (checkbox.label.len != 0) allocator.free(checkbox.label);
}

pub fn containsVisible(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    var normalized_haystack: [512]u8 = undefined;
    var h_len: usize = 0;
    for (haystack) |byte| {
        if (!std.ascii.isAlphanumeric(byte)) continue;
        if (h_len >= normalized_haystack.len) break;
        normalized_haystack[h_len] = std.ascii.toLower(byte);
        h_len += 1;
    }
    var normalized_needle: [128]u8 = undefined;
    var n_len: usize = 0;
    for (needle) |byte| {
        if (!std.ascii.isAlphanumeric(byte)) continue;
        if (n_len >= normalized_needle.len) break;
        normalized_needle[n_len] = std.ascii.toLower(byte);
        n_len += 1;
    }
    return std.mem.indexOf(u8, normalized_haystack[0..h_len], normalized_needle[0..n_len]) != null;
}

test "physical projection emits required input commands" {
    const semantic = SemanticTree{
        .rendered_text = @constCast("todos Professional Glass Brutalist Neumorphic Dark mode"),
        .inputs = @constCast(&[_]SemanticInput{.{ .text = @constCast(""), .placeholder = @constCast("What needs to be done?"), .focused = true, .disabled = false }}),
        .buttons = @constCast(&[_]SemanticButton{.{ .label = @constCast("Professional"), .disabled = false, .outlined = true }}),
        .checkboxes = @constCast(&[_]SemanticCheckbox{}),
    };
    const trace = try RenderTrace.project(std.testing.allocator, semantic, .{});
    defer {
        var mutable = trace;
        mutable.deinit(std.testing.allocator);
    }
    var saw_inner_shadow = false;
    var saw_glow = false;
    for (trace.commands) |command| {
        if (command.base.kind == .inner_shadow and std.mem.eql(u8, command.role, "text_input")) saw_inner_shadow = true;
        if (command.base.kind == .glow and std.mem.eql(u8, command.role, "text_input")) saw_glow = true;
    }
    try std.testing.expect(saw_inner_shadow);
    try std.testing.expect(saw_glow);
}

test "generic TodoMVC projection keeps many rows above footer and caret inside input" {
    const typed_text = "rgrrhththththththththththththth";
    var checkboxes: [23]SemanticCheckbox = undefined;
    checkboxes[0] = .{ .label = @constCast("Toggle all"), .checked = false };
    for (checkboxes[1..], 0..) |*checkbox, index| {
        checkbox.* = .{ .label = @constCast("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), .checked = index % 2 == 0 };
    }
    const semantic = SemanticTree{
        .rendered_text = @constCast("todos22itemsleft[All][Active][Completed]"),
        .inputs = @constCast(&[_]SemanticInput{.{ .text = @constCast(typed_text), .placeholder = @constCast("What needs to be done?"), .focused = true, .disabled = false }}),
        .buttons = @constCast(&[_]SemanticButton{
            .{ .label = @constCast("All"), .disabled = false, .outlined = true },
            .{ .label = @constCast("Active"), .disabled = false, .outlined = false },
            .{ .label = @constCast("Completed"), .disabled = false, .outlined = false },
        }),
        .checkboxes = &checkboxes,
    };
    const trace = try RenderTrace.project(std.testing.allocator, semantic, .{});
    defer {
        var mutable = trace;
        mutable.deinit(std.testing.allocator);
    }
    var footer_top: ?f32 = null;
    var caret_seen = false;
    for (trace.commands) |command| {
        if (std.mem.eql(u8, command.role, "button") and command.base.kind == .bevel) {
            footer_top = if (footer_top) |top| @min(top, command.base.rect.y) else command.base.rect.y;
        }
    }
    const footer_y = footer_top orelse return error.MissingFooterButtons;
    for (trace.commands) |command| {
        if (std.mem.eql(u8, command.role, "checkbox")) {
            try std.testing.expect(command.base.rect.y + command.base.rect.h <= footer_y);
        }
        if (command.base.kind == .bevel and std.mem.eql(u8, command.role, "text_input") and command.caret_visible) {
            caret_seen = true;
            try std.testing.expectEqualStrings(typed_text, command.caret_text);
        }
        if (command.base.kind == .caret and std.mem.eql(u8, command.role, "text_input")) {
            return error.ProjectionCaretMustUseMeasuredTextRenderer;
        }
    }
    try std.testing.expect(caret_seen);
}

test "readable rendered text strips input markers" {
    const readable = try readableRenderedTextAlloc(std.testing.allocator, "Temperature Converter\n<> Celsius = <> Fahrenheit\n10is55\n>\nItalic0.68What 2itemsleft");
    defer std.testing.allocator.free(readable);
    try std.testing.expectEqualStrings("Temperature Converter\nCelsius = Fahrenheit\n10 is 55\nWhat 2 items left", readable);
}
