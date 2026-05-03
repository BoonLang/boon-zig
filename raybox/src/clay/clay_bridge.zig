const std = @import("std");

const font_manager = @import("../text/font_manager.zig");
const geometry = @import("../render/geometry.zig");
const playground_layout = @import("playground_layout");

pub const c = @cImport({
    @cInclude("clay.h");
});

pub const ClayBridge = struct {
    allocator: std.mem.Allocator,
    memory: []u8,
    arena: c.Clay_Arena,
    context: *c.Clay_Context,
    fonts: *font_manager.FontManager,
    last_error: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, fonts: *font_manager.FontManager, width: f32, height: f32) !ClayBridge {
        const min_size = c.Clay_MinMemorySize();
        const capacity: usize = @max(@as(usize, min_size), 4 * 1024 * 1024);
        const memory = try allocator.alloc(u8, capacity);
        errdefer allocator.free(memory);
        const arena = c.Clay_CreateArenaWithCapacityAndMemory(capacity, memory.ptr);
        const context = c.Clay_Initialize(arena, .{ .width = width, .height = height }, .{
            .errorHandlerFunction = errorHandler,
            .userData = null,
        }) orelse return error.ClayInitFailed;
        c.Clay_SetMeasureTextFunction(measureText, fonts);
        c.Clay_SetCullingEnabled(false);
        return .{
            .allocator = allocator,
            .memory = memory,
            .arena = arena,
            .context = context,
            .fonts = fonts,
        };
    }

    pub fn deinit(self: *ClayBridge) void {
        self.allocator.free(self.memory);
        self.* = undefined;
    }

    pub fn beginFrame(self: *ClayBridge, input: InputFrame, width: f32, height: f32, dt: f32) void {
        c.Clay_SetCurrentContext(self.context);
        c.Clay_SetLayoutDimensions(.{ .width = width, .height = height });
        c.Clay_SetPointerState(.{ .x = input.pointer_x, .y = input.pointer_y }, input.pointer_down);
        c.Clay_UpdateScrollContainers(false, .{ .x = 0, .y = 0 }, dt);
        c.Clay_BeginLayout();
    }

    pub fn endFrame(self: *ClayBridge, dt: f32) c.Clay_RenderCommandArray {
        c.Clay_SetCurrentContext(self.context);
        return c.Clay_EndLayout(dt);
    }
};

pub const InputFrame = struct {
    pointer_x: f32 = 0,
    pointer_y: f32 = 0,
    pointer_down: bool = false,
};

pub const ShellStats = struct {
    example_name: []const u8,
    example_names: []const []const u8 = &.{},
    selected_example_index: usize = 0,
    source_title: []const u8 = "",
    source_preview: []const u8 = "",
    source_scroll_line: usize = 0,
    frame_index: u64,
    command_count: usize,
    trace_count: usize,
};

pub fn declarePlaygroundShell(stats: ShellStats) void {
    element(.{
        .layout = layout(.{
            .width = grow(),
            .height = grow(),
            .direction = c.CLAY_TOP_TO_BOTTOM,
            .padding = padding(0),
            .gap = 0,
        }),
        .backgroundColor = color(15, 18, 22, 255),
    });

    element(.{
        .layout = layout(.{
            .width = grow(),
            .height = fixed(playground_layout.top_bar_height),
            .direction = c.CLAY_LEFT_TO_RIGHT,
            .padding = paddingXY(28, 18),
            .gap = 18,
            .align_y = c.CLAY_ALIGN_Y_CENTER,
        }),
        .backgroundColor = color(25, 29, 35, 255),
        .border = border(color(69, 78, 94, 255), 1),
    });
    text("boon-playground-raybox", 0, 30, color(246, 248, 252, 255));
    text(stats.example_name, 0, 24, color(185, 199, 220, 255));
    element(.{ .layout = layout(.{ .width = grow(), .height = fixed(1) }) });
    close();
    shellButton("Previous");
    shellButton("Next");
    shellButton("Reload");
    close();

    element(.{
        .layout = layout(.{
            .width = grow(),
            .height = grow(),
            .direction = c.CLAY_LEFT_TO_RIGHT,
            .padding = padding(playground_layout.outer_padding),
            .gap = playground_layout.content_gap,
        }),
    });

    element(.{
        .layout = layout(.{
            .width = fixed(playground_layout.sidebar_width),
            .height = grow(),
            .direction = c.CLAY_TOP_TO_BOTTOM,
            .padding = padding(playground_layout.sidebar_padding),
            .gap = 14,
        }),
        .backgroundColor = color(28, 33, 40, 255),
        .cornerRadius = radius(8),
        .border = border(color(63, 72, 86, 255), 1),
    });
    text("Examples", 0, 34, color(245, 248, 252, 255));
    exampleTabs(stats.example_names, stats.selected_example_index);
    text("Playground Input", 0, 32, color(245, 248, 252, 255));
    inputHint(stats.example_name);
    element(.{ .layout = layout(.{ .width = grow(), .height = fixed(40), .direction = c.CLAY_LEFT_TO_RIGHT, .gap = 12 }) });
    statPill("frame", stats.frame_index);
    statPill("trace", stats.trace_count);
    close();
    close();

    element(.{
        .layout = layout(.{
            .width = fixed(playground_layout.source_panel_width),
            .height = grow(),
            .direction = c.CLAY_TOP_TO_BOTTOM,
            .padding = padding(playground_layout.sidebar_padding),
            .gap = 14,
        }),
        .backgroundColor = color(28, 33, 40, 255),
        .cornerRadius = radius(8),
        .border = border(color(63, 72, 86, 255), 1),
    });
    text("Boon Source", 0, 34, color(245, 248, 252, 255));
    sourcePanel(stats.source_title, stats.source_preview, stats.source_scroll_line);
    close();

    element(.{
        .layout = layout(.{
            .width = grow(),
            .height = grow(),
            .direction = c.CLAY_LEFT_TO_RIGHT,
        }),
        .backgroundColor = color(24, 27, 32, 0),
    });
    close();
    close();
    close();
    _ = stats.command_count;
}

fn exampleTabs(names: []const []const u8, selected: usize) void {
    const columns: usize = playground_layout.tab_columns;
    const tab_width: f32 = playground_layout.tab_width;
    const tab_height: f32 = playground_layout.tab_height;
    const rows = playground_layout.tabRows(names.len);
    element(.{
        .layout = layout(.{
            .width = grow(),
            .height = fixed(@as(f32, @floatFromInt(rows)) * (tab_height + playground_layout.tab_gap)),
            .direction = c.CLAY_TOP_TO_BOTTOM,
            .gap = playground_layout.tab_gap,
        }),
    });
    var index: usize = 0;
    while (index < names.len) {
        element(.{ .layout = layout(.{ .width = grow(), .height = fixed(tab_height), .direction = c.CLAY_LEFT_TO_RIGHT, .gap = playground_layout.tab_gap }) });
        for (0..columns) |_| {
            if (index < names.len) {
                const is_selected = index == selected;
                element(.{
                    .layout = layout(.{ .width = fixed(tab_width), .height = fixed(tab_height), .padding = paddingXY(12, 10), .align_y = c.CLAY_ALIGN_Y_CENTER }),
                    .backgroundColor = if (is_selected) color(82, 133, 217, 255) else color(43, 51, 63, 255),
                    .cornerRadius = radius(6),
                    .border = border(if (is_selected) color(174, 205, 255, 255) else color(73, 84, 101, 255), 1),
                });
                text(tabLabel(names[index]), 0, playground_layout.tab_font_size, color(242, 247, 255, 255));
                close();
            } else {
                element(.{ .layout = layout(.{ .width = fixed(tab_width), .height = fixed(tab_height) }) });
                close();
            }
            index += 1;
        }
        close();
    }
    close();
}

fn tabLabel(name: []const u8) []const u8 {
    return if (name.len > 15) name[0..15] else name;
}

fn inputHint(example_name: []const u8) void {
    if (std.mem.eql(u8, example_name, "pong")) {
        text("Keyboard: Up/Down, Enter, Space, R", 0, 24, color(218, 229, 244, 255));
        text("Use on-preview controls or keyboard", 0, 24, color(218, 229, 244, 255));
    } else if (std.mem.eql(u8, example_name, "cells") or std.mem.eql(u8, example_name, "cells_dynamic")) {
        text("Grid examples are render-only in v0", 0, 24, color(218, 229, 244, 255));
        text("Use tabs, Previous/Next, or F5", 0, 24, color(218, 229, 244, 255));
    } else {
        text("Click preview input, then type", 0, 24, color(218, 229, 244, 255));
        text("Buttons and checkboxes are clickable", 0, 24, color(218, 229, 244, 255));
    }
}

fn sourcePanel(title: []const u8, preview: []const u8, scroll_line: usize) void {
    text(if (title.len == 0) "current example" else title, 1, playground_layout.source_title_font_size, color(190, 203, 222, 255));
    text("PageUp/PageDown scroll source", 0, 22, color(160, 177, 201, 255));
    element(.{
        .layout = layout(.{
            .width = grow(),
            .height = fixed(playground_layout.source_panel_height),
            .direction = c.CLAY_TOP_TO_BOTTOM,
            .padding = padding(14),
            .gap = 2,
        }),
        .backgroundColor = color(17, 21, 27, 255),
        .cornerRadius = radius(6),
        .border = border(color(54, 64, 78, 255), 1),
    });
    defer close();
    var lines = std.mem.splitScalar(u8, preview, '\n');
    var skipped: usize = 0;
    while (skipped < scroll_line) : (skipped += 1) {
        _ = lines.next() orelse break;
    }
    var count: usize = 0;
    while (count < playground_layout.source_visible_lines) : (count += 1) {
        const line = lines.next() orelse break;
        text(line, 1, playground_layout.source_font_size, color(214, 224, 238, 255));
    }
}

fn shellButton(label: []const u8) void {
    element(.{
        .layout = layout(.{
            .width = fixed(150),
            .height = fixed(52),
            .padding = paddingXY(18, 12),
            .align_y = c.CLAY_ALIGN_Y_CENTER,
        }),
        .backgroundColor = color(57, 69, 86, 255),
        .cornerRadius = radius(8),
        .border = border(color(103, 123, 151, 255), 1),
    });
    defer close();
    text(label, 0, 22, color(246, 249, 253, 255));
}

fn statPill(label: []const u8, value: anytype) void {
    _ = value;
    element(.{
        .layout = layout(.{ .width = fixed(150), .height = fixed(40), .padding = paddingXY(16, 8) }),
        .backgroundColor = color(45, 53, 65, 255),
        .cornerRadius = radius(8),
    });
    defer close();
    text(label, 1, 20, color(226, 234, 246, 255));
}

pub fn element(decl: c.Clay_ElementDeclaration) void {
    c.Clay__OpenElement();
    c.Clay__ConfigureOpenElement(decl);
}

pub fn close() void {
    c.Clay__CloseElement();
}

pub fn text(bytes: []const u8, font_id: u16, size: u16, text_color: c.Clay_Color) void {
    c.Clay__OpenTextElement(.{
        .isStaticallyAllocated = false,
        .length = @intCast(bytes.len),
        .chars = bytes.ptr,
    }, .{
        .textColor = text_color,
        .fontId = font_id,
        .fontSize = size,
        .lineHeight = size + 4,
        .wrapMode = c.CLAY_TEXT_WRAP_NONE,
    });
}

pub const LayoutOptions = struct {
    width: c.Clay_SizingAxis = grow(),
    height: c.Clay_SizingAxis = grow(),
    direction: c.Clay_LayoutDirection = c.CLAY_LEFT_TO_RIGHT,
    padding: c.Clay_Padding = .{},
    gap: u16 = 0,
    align_x: c.Clay_LayoutAlignmentX = c.CLAY_ALIGN_X_LEFT,
    align_y: c.Clay_LayoutAlignmentY = c.CLAY_ALIGN_Y_TOP,
};

pub fn layout(options: LayoutOptions) c.Clay_LayoutConfig {
    return .{
        .sizing = .{ .width = options.width, .height = options.height },
        .padding = options.padding,
        .childGap = options.gap,
        .childAlignment = .{ .x = options.align_x, .y = options.align_y },
        .layoutDirection = options.direction,
    };
}

pub fn fixed(value: f32) c.Clay_SizingAxis {
    return .{ .size = .{ .minMax = .{ .min = value, .max = value } }, .type = c.CLAY__SIZING_TYPE_FIXED };
}

pub fn grow() c.Clay_SizingAxis {
    return .{ .size = .{ .minMax = .{ .min = 0, .max = 0 } }, .type = c.CLAY__SIZING_TYPE_GROW };
}

pub fn padding(value: u16) c.Clay_Padding {
    return .{ .left = value, .right = value, .top = value, .bottom = value };
}

pub fn paddingXY(x: u16, y: u16) c.Clay_Padding {
    return .{ .left = x, .right = x, .top = y, .bottom = y };
}

pub fn radius(value: f32) c.Clay_CornerRadius {
    return .{ .topLeft = value, .topRight = value, .bottomLeft = value, .bottomRight = value };
}

pub fn color(r: f32, g: f32, b: f32, a: f32) c.Clay_Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn border(border_color: c.Clay_Color, width: u16) c.Clay_BorderElementConfig {
    return .{
        .color = border_color,
        .width = .{ .left = width, .right = width, .top = width, .bottom = width, .betweenChildren = 0 },
    };
}

pub fn boundingRect(box: c.Clay_BoundingBox) geometry.Rect {
    return .{ .x = box.x, .y = box.y, .w = box.width, .h = box.height };
}

pub fn colorPremul(clay_color: c.Clay_Color) geometry.ColorPremul {
    return geometry.ColorPremul.rgba(clay_color.r / 255.0, clay_color.g / 255.0, clay_color.b / 255.0, clay_color.a / 255.0);
}

fn measureText(slice: c.Clay_StringSlice, config: [*c]c.Clay_TextElementConfig, user_data: ?*anyopaque) callconv(.c) c.Clay_Dimensions {
    const fonts: *font_manager.FontManager = @ptrCast(@alignCast(user_data.?));
    const text_slice = slice.chars[0..@intCast(slice.length)];
    const font = if (config.*.fontId == 1) fonts.coreFont(.mono) else fonts.coreFont(.inter);
    const measured = fonts.measure(text_slice, font, @floatFromInt(config.*.fontSize));
    return .{ .width = measured.width, .height = measured.height };
}

fn errorHandler(error_data: c.Clay_ErrorData) callconv(.c) void {
    _ = error_data;
}

test "Clay bridge can produce shell render commands" {
    var fonts = try font_manager.FontManager.init(std.testing.allocator);
    defer fonts.deinit();
    var bridge = try ClayBridge.init(std.testing.allocator, &fonts, 1280, 800);
    defer bridge.deinit();
    bridge.beginFrame(.{}, 1280, 800, 1.0 / 60.0);
    declarePlaygroundShell(.{ .example_name = "todo_mvc_physical", .frame_index = 1, .command_count = 0, .trace_count = 12 });
    const commands = bridge.endFrame(1.0 / 60.0);
    try std.testing.expect(commands.length > 0);
}
