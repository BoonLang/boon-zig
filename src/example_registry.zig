pub const ExampleSpec = struct {
    name: []const u8,
    label: []const u8,
    path: []const u8,
    render_mode: RenderMode = .full,
};

pub const RenderMode = union(enum) {
    full,
    compact_grid: struct {
        max_row_items: usize,
        max_column_head_items: usize,
    },
};

pub const terminal_examples = [_]ExampleSpec{
    .{ .name = "counter", .label = "Counter", .path = "examples/terminal/counter/counter.bn" },
    .{ .name = "interval", .label = "Interval", .path = "examples/terminal/interval/interval.bn" },
    .{ .name = "cells", .label = "Cells", .path = "examples/terminal/cells/cells.bn", .render_mode = .{ .compact_grid = .{ .max_row_items = 2, .max_column_head_items = 2 } } },
    .{ .name = "cells_dynamic", .label = "CellsDyn", .path = "examples/terminal/cells_dynamic/cells_dynamic.bn", .render_mode = .{ .compact_grid = .{ .max_row_items = 2, .max_column_head_items = 2 } } },
    .{ .name = "todo_mvc", .label = "TodoMVC", .path = "examples/terminal/todo_mvc/todo_mvc.bn" },
    .{ .name = "pong", .label = "Pong", .path = "examples/terminal/pong/pong.bn" },
    .{ .name = "arkanoid", .label = "Arkanoid", .path = "examples/terminal/arkanoid/arkanoid.bn" },
    .{ .name = "temperature_converter", .label = "Temp", .path = "examples/terminal/temperature_converter/temperature_converter.bn" },
    .{ .name = "flight_booker", .label = "Flight", .path = "examples/terminal/flight_booker/flight_booker.bn" },
    .{ .name = "timer", .label = "Timer", .path = "examples/terminal/timer/timer.bn" },
    .{ .name = "crud", .label = "CRUD", .path = "examples/terminal/crud/crud.bn" },
    .{ .name = "circle_drawer", .label = "Circle", .path = "examples/terminal/circle_drawer/circle_drawer.bn" },
};

pub const multi_file_examples = [_]ExampleSpec{
    .{ .name = "todo_mvc_physical", .label = "Physical", .path = "examples/upstream/todo_mvc_physical/RUN.bn" },
};
