pub const SourceCommit = "c924d9f7d7e1c156604c9377e0487db48c278353";

pub const ExampleKind = enum { single_file, multi_file };
pub const ExampleSection = enum { main, other, debug, multi_file };

pub const Example = struct {
    name: []const u8,
    kind: ExampleKind,
    section: ExampleSection,
    registry_section: []const u8,
    root_path: []const u8,
    entry_file: []const u8,
};

pub const examples = [_]Example{
    .{ .name = "minimal", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/minimal", .entry_file = "minimal.bn" },
    .{ .name = "hello_world", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/hello_world", .entry_file = "hello_world.bn" },
    .{ .name = "interval", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/interval", .entry_file = "interval.bn" },
    .{ .name = "interval_hold", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/interval_hold", .entry_file = "interval_hold.bn" },
    .{ .name = "counter", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/counter", .entry_file = "counter.bn" },
    .{ .name = "complex_counter", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/complex_counter", .entry_file = "complex_counter.bn" },
    .{ .name = "counter_hold", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/counter_hold", .entry_file = "counter_hold.bn" },
    .{ .name = "fibonacci", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/fibonacci", .entry_file = "fibonacci.bn" },
    .{ .name = "layers", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/layers", .entry_file = "layers.bn" },
    .{ .name = "shopping_list", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/shopping_list", .entry_file = "shopping_list.bn" },
    .{ .name = "pages", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/pages", .entry_file = "pages.bn" },
    .{ .name = "todo_mvc", .kind = .single_file, .section = .main, .registry_section = "EXAMPLE_DATAS", .root_path = "examples/upstream/todo_mvc", .entry_file = "todo_mvc.bn" },
    .{ .name = "temperature_converter", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/temperature_converter", .entry_file = "temperature_converter.bn" },
    .{ .name = "crud", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/crud", .entry_file = "crud.bn" },
    .{ .name = "timer", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/timer", .entry_file = "timer.bn" },
    .{ .name = "flight_booker", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/flight_booker", .entry_file = "flight_booker.bn" },
    .{ .name = "circle_drawer", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/circle_drawer", .entry_file = "circle_drawer.bn" },
    .{ .name = "cells", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/cells", .entry_file = "cells.bn" },
    .{ .name = "cells_dynamic", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/cells_dynamic", .entry_file = "cells_dynamic.bn" },
    .{ .name = "latest", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/latest", .entry_file = "latest.bn" },
    .{ .name = "text_interpolation_update", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/text_interpolation_update", .entry_file = "text_interpolation_update.bn" },
    .{ .name = "then", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/then", .entry_file = "then.bn" },
    .{ .name = "when", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/when", .entry_file = "when.bn" },
    .{ .name = "while", .kind = .single_file, .section = .other, .registry_section = "OTHER_EXAMPLE_DATAS", .root_path = "examples/upstream/while", .entry_file = "while.bn" },
    .{ .name = "list_retain_reactive", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/list_retain_reactive", .entry_file = "list_retain_reactive.bn" },
    .{ .name = "list_map_external_dep", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/list_map_external_dep", .entry_file = "list_map_external_dep.bn" },
    .{ .name = "list_map_block", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/list_map_block", .entry_file = "list_map_block.bn" },
    .{ .name = "list_retain_count", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/list_retain_count", .entry_file = "list_retain_count.bn" },
    .{ .name = "list_object_state", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/list_object_state", .entry_file = "list_object_state.bn" },
    .{ .name = "list_retain_remove", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/list_retain_remove", .entry_file = "list_retain_remove.bn" },
    .{ .name = "filter_checkbox_bug", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/filter_checkbox_bug", .entry_file = "filter_checkbox_bug.bn" },
    .{ .name = "checkbox_test", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/checkbox_test", .entry_file = "checkbox_test.bn" },
    .{ .name = "chained_list_remove_bug", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/chained_list_remove_bug", .entry_file = "chained_list_remove_bug.bn" },
    .{ .name = "while_function_call", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/while_function_call", .entry_file = "while_function_call.bn" },
    .{ .name = "button_hover_test", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/button_hover_test", .entry_file = "button_hover_test.bn" },
    .{ .name = "button_hover_to_click_test", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/button_hover_to_click_test", .entry_file = "button_hover_to_click_test.bn" },
    .{ .name = "switch_hold_test", .kind = .single_file, .section = .debug, .registry_section = "DEBUG_EXAMPLE_DATAS", .root_path = "examples/upstream/switch_hold_test", .entry_file = "switch_hold_test.bn" },
    .{ .name = "todo_mvc_physical", .kind = .multi_file, .section = .multi_file, .registry_section = "MULTI_FILE_EXAMPLES", .root_path = "examples/upstream/todo_mvc_physical", .entry_file = "RUN.bn" },
};
