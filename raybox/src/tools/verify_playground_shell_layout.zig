const std = @import("std");
const playground_layout = @import("playground_layout");

pub fn main() !void {
    try expect(playground_layout.window_width >= 1600, "playground window must leave room for readable sidebar and preview");
    try expect(playground_layout.window_height >= 1000, "playground window must leave room for source panel");
    try expect(playground_layout.sidebar_width >= 540, "playground examples panel must not collapse back to debug-panel width");
    try expect(playground_layout.examples_column_width >= 460, "playground examples column must keep three readable tab columns");
    try expect(playground_layout.source_panel_width >= 540, "playground source panel must stay wide enough to read code");
    try expect(playground_layout.tab_columns == 3, "playground example tabs use the tested three-column hit grid");
    try expect(playground_layout.tab_width >= 150, "playground example tabs must remain readable");
    try expect(playground_layout.tab_height >= 40, "playground example tabs must remain clickable");
    try expect(playground_layout.tab_font_size >= 18, "playground example tab text must remain readable");
    try expect(playground_layout.source_font_size >= 24, "playground source text must remain readable");
    try expect(playground_layout.source_panel_height >= 760, "playground source panel must show enough context");
    try expect(playground_layout.source_visible_lines >= 20, "playground source panel must render enough lines for visual debugging");
    try expect(playground_layout.source_preview_columns <= 44, "playground source preview lines must fit the source panel");
    try expect(playground_layout.preview_left >= playground_layout.outer_padding + playground_layout.sidebar_width + playground_layout.content_gap + playground_layout.source_panel_width + playground_layout.content_gap, "preview must start after info panels");

    const preview_width = @as(f32, @floatFromInt(playground_layout.window_width)) - playground_layout.preview_left - playground_layout.outer_padding;
    try expect(preview_width >= 700, "playground preview must keep enough width after info panels");
}

fn expect(condition: bool, message: []const u8) !void {
    if (!condition) {
        std.log.err("{s}", .{message});
        return error.PlaygroundShellLayoutVerificationFailed;
    }
}
