pub const window_width: i32 = 1940;
pub const window_height: i32 = 1100;

pub const top_bar_height: f32 = 88;
pub const outer_padding: f32 = 24;
pub const content_gap: f32 = 24;
pub const sidebar_width: f32 = 560;
pub const sidebar_padding: f32 = 28;
pub const examples_column_width: f32 = 496;
pub const source_panel_width: f32 = 560;
pub const preview_left: f32 = outer_padding + sidebar_width + content_gap + source_panel_width + content_gap + 20;

pub const tab_columns: usize = 3;
pub const tab_width: f32 = 154;
pub const tab_height: f32 = 40;
pub const tab_gap: f32 = 8;
pub const tab_start_x: f32 = outer_padding + sidebar_padding;
pub const tab_start_y: f32 = top_bar_height + outer_padding + sidebar_padding + 46;
pub const tab_font_size: u16 = 20;

pub const source_title_font_size: u16 = 24;
pub const source_font_size: u16 = 24;
pub const source_panel_height: f32 = 860;
pub const source_visible_lines: usize = 24;
pub const source_preview_columns: usize = 42;

pub fn tabRows(example_count: usize) usize {
    return (example_count + tab_columns - 1) / tab_columns;
}
