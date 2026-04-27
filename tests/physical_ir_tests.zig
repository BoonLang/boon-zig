const std = @import("std");
const boon = @import("boon");

fn expectPhysicalGolden(source: []const u8, expected: []const u8) !void {
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected Physical IR golden failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const rendered = try boon.physical_ir.renderAlloc(std.testing.allocator, &program);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(expected, rendered);
}

test "Physical IR lowers canonical SOURCE leaves to source slots" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\hover: SOURCE
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 2), program.source_slots.len);
    try std.testing.expect(program.value_slots.len > 0);
    try std.testing.expect(program.dependency_edges.len > 0);
    try std.testing.expectEqual(@as(boon.physical_ir.SourceSlotId, 0), program.source_slots[0].id);
    try std.testing.expectEqualStrings("button.event.press", program.source_slots[0].semantic_id);
    try std.testing.expectEqualStrings("Pulse", program.source_slots[0].payload_type);
    const first_source = std.mem.indexOf(u8, source, "SOURCE").?;
    try std.testing.expectEqual(first_source, program.source_slots[0].source_span.start);
    try std.testing.expectEqual(first_source + "SOURCE".len, program.source_slots[0].source_span.end);
    try std.testing.expectEqual(@as(boon.physical_ir.SourceSlotId, 1), program.source_slots[1].id);
    try std.testing.expectEqualStrings("hover", program.source_slots[1].semantic_id);
    try std.testing.expectEqualStrings("Pulse", program.source_slots[1].payload_type);
    const second_source = std.mem.lastIndexOf(u8, source, "SOURCE").?;
    try std.testing.expectEqual(second_source, program.source_slots[1].source_span.start);
    try std.testing.expectEqual(second_source + "SOURCE".len, program.source_slots[1].source_span.end);
}

test "Physical IR renders canonical counter-style golden" {
    const source =
        \\increment_button: [event: [press: SOURCE] hovered: SOURCE]
        \\counter: 0
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR golden failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const rendered = try boon.physical_ir.renderAlloc(std.testing.allocator, &program);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        \\physical source_slots=2 value_slots=5 state_slots=0 instructions=5 edges=3
        \\source[0] increment_button.event.press : Pulse
        \\source[1] increment_button.hovered : Bool
        \\
    , rendered);
}

test "Physical IR renders canonical counter source golden" {
    const source =
        \\increment_button: [event: [press: SOURCE] hovered: SOURCE]
        \\counter:
        \\    LATEST {
        \\        0
        \\        increment_button.event.press |> THEN { 1 }
        \\    }
        \\    |> Math/sum()
        \\
    ;
    try expectPhysicalGolden(source,
        \\physical source_slots=2 value_slots=12 state_slots=0 instructions=12 edges=10
        \\source[0] increment_button.event.press : Pulse
        \\source[1] increment_button.hovered : Bool
        \\
    );
}

test "Physical IR renders canonical complex_counter source golden" {
    const source =
        \\sources: [
        \\    decrement_button: [event: [press: SOURCE] hovered: SOURCE]
        \\    increment_button: [event: [press: SOURCE] hovered: SOURCE]
        \\]
        \\counter: LATEST {
        \\    sources.decrement_button.event.press |> THEN { 0 - 1 }
        \\    sources.increment_button.event.press |> THEN { 0 + 1 }
        \\}
        \\
    ;
    try expectPhysicalGolden(source,
        \\physical source_slots=4 value_slots=26 state_slots=0 instructions=26 edges=24
        \\source[0] sources.decrement_button.event.press : Pulse
        \\source[1] sources.decrement_button.hovered : Bool
        \\source[2] sources.increment_button.event.press : Pulse
        \\source[3] sources.increment_button.hovered : Bool
        \\
    );
}

test "Physical IR renders canonical todo_mvc source slice golden" {
    const source =
        \\sources: [
        \\    new_todo: [event: [change: SOURCE key_down: SOURCE blur: SOURCE focus: SOURCE]]
        \\    filters: [
        \\        all: [event: [press: SOURCE] hovered: SOURCE]
        \\        active: [event: [press: SOURCE] hovered: SOURCE]
        \\        completed: [event: [press: SOURCE] hovered: SOURCE]
        \\    ]
        \\    remove_completed_button: [event: [press: SOURCE] hovered: SOURCE]
        \\    item: [
        \\        checkbox: [event: [click: SOURCE]]
        \\        title: [event: [double_click: SOURCE]]
        \\        edit: [event: [change: SOURCE key_down: SOURCE blur: SOURCE]]
        \\        remove: [event: [click: SOURCE]]
        \\    ]
        \\]
        \\
    ;
    try expectPhysicalGolden(source,
        \\physical source_slots=18 value_slots=39 state_slots=0 instructions=39 edges=38
        \\source[0] sources.new_todo.event.change : TextChange
        \\source[1] sources.new_todo.event.key_down : KeyEvent
        \\source[2] sources.new_todo.event.blur : Pulse
        \\source[3] sources.new_todo.event.focus : Pulse
        \\source[4] sources.filters.all.event.press : Pulse
        \\source[5] sources.filters.all.hovered : Bool
        \\source[6] sources.filters.active.event.press : Pulse
        \\source[7] sources.filters.active.hovered : Bool
        \\source[8] sources.filters.completed.event.press : Pulse
        \\source[9] sources.filters.completed.hovered : Bool
        \\source[10] sources.remove_completed_button.event.press : Pulse
        \\source[11] sources.remove_completed_button.hovered : Bool
        \\source[12] sources.item.checkbox.event.click : Pulse
        \\source[13] sources.item.title.event.double_click : Pulse
        \\source[14] sources.item.edit.event.change : TextChange
        \\source[15] sources.item.edit.event.key_down : KeyEvent
        \\source[16] sources.item.edit.event.blur : Pulse
        \\source[17] sources.item.remove.event.click : Pulse
        \\
    );
}

test "Physical IR renders physical TodoMVC store.sources and todo.sources golden" {
    const source =
        \\store: [
        \\    sources: [
        \\        filter_buttons: [
        \\            all: [event: [press: SOURCE] hovered: SOURCE]
        \\            active: [event: [press: SOURCE] hovered: SOURCE]
        \\            completed: [event: [press: SOURCE] hovered: SOURCE]
        \\        ]
        \\        remove_completed_button: [event: [press: SOURCE] hovered: SOURCE]
        \\        toggle_all_checkbox: [event: [click: SOURCE]]
        \\        new_todo_title_text_input: [
        \\            event: [
        \\                change: SOURCE
        \\                key_down: SOURCE
        \\            ]
        \\        ]
        \\    ]
        \\]
        \\
        \\todo: [
        \\    sources: [
        \\        remove_todo_button: [event: [press: SOURCE]]
        \\        editing_todo_title_element: [
        \\            event: [
        \\                change: SOURCE
        \\                key_down: SOURCE
        \\                blur: SOURCE
        \\            ]
        \\        ]
        \\        todo_title_element: [event: [double_click: SOURCE]]
        \\        todo_checkbox: [event: [click: SOURCE]]
        \\    ]
        \\]
        \\
        \\draft_title: 0 |> HOLD draft_title {
        \\    store.sources.new_todo_title_text_input.event.change
        \\}
        \\
        \\filter_press_count: 0 |> HOLD filter_press_count {
        \\    store.sources.filter_buttons.active.event.press |> THEN { filter_press_count + 1 }
        \\}
        \\
        \\removed_count: 0 |> HOLD removed_count {
        \\    todo.sources.remove_todo_button.event.press |> THEN { removed_count + 1 }
        \\}
        \\
        \\edit_title: 0 |> HOLD edit_title {
        \\    todo.sources.editing_todo_title_element.event.change
        \\}
        \\
    ;
    try expectPhysicalGolden(source,
        \\physical source_slots=17 value_slots=79 state_slots=4 instructions=79 edges=73
        \\source[0] store.sources.filter_buttons.all.event.press : Pulse
        \\source[1] store.sources.filter_buttons.all.hovered : Bool
        \\source[2] store.sources.filter_buttons.active.event.press : Pulse
        \\source[3] store.sources.filter_buttons.active.hovered : Bool
        \\source[4] store.sources.filter_buttons.completed.event.press : Pulse
        \\source[5] store.sources.filter_buttons.completed.hovered : Bool
        \\source[6] store.sources.remove_completed_button.event.press : Pulse
        \\source[7] store.sources.remove_completed_button.hovered : Bool
        \\source[8] store.sources.toggle_all_checkbox.event.click : Pulse
        \\source[9] store.sources.new_todo_title_text_input.event.change : TextChange
        \\source[10] store.sources.new_todo_title_text_input.event.key_down : KeyEvent
        \\source[11] todo.sources.remove_todo_button.event.press : Pulse
        \\source[12] todo.sources.editing_todo_title_element.event.change : TextChange
        \\source[13] todo.sources.editing_todo_title_element.event.key_down : KeyEvent
        \\source[14] todo.sources.editing_todo_title_element.event.blur : Pulse
        \\source[15] todo.sources.todo_title_element.event.double_click : Pulse
        \\source[16] todo.sources.todo_checkbox.event.click : Pulse
        \\state[0] hold.draft_title <- flow.n48
        \\state[1] hold.filter_press_count <- flow.n60
        \\state[2] hold.removed_count <- flow.n71
        \\state[3] hold.edit_title <- flow.n78
        \\
    );
}

test "Physical IR renders canonical list_map_block golden" {
    const source =
        \\items: LIST { 1 2 3 }
        \\filtered: items |> List/map(item, new: BLOCK {
        \\    should_show: item == 2
        \\    should_show |> WHILE {
        \\        True => item
        \\        False => SKIP
        \\    }
        \\})
        \\
    ;
    try expectPhysicalGolden(source,
        \\physical source_slots=0 value_slots=16 state_slots=0 instructions=16 edges=15
        \\
    );
}

test "Physical IR renders canonical while source golden" {
    const source =
        \\operation_button: [event: [press: SOURCE]]
        \\updating_result: operation_button.event.press |> WHILE {
        \\    Addition => 1
        \\    Subtraction => 2
        \\}
        \\
    ;
    try expectPhysicalGolden(source,
        \\physical source_slots=1 value_slots=11 state_slots=0 instructions=11 edges=9
        \\source[0] operation_button.event.press : Pulse
        \\
    );
}

test "Physical IR renders canonical text_interpolation_update source golden" {
    const source =
        \\toggle: [event: [press: SOURCE]]
        \\value: toggle.event.press |> THEN { True }
        \\label: TEXT { Value: {value} }
        \\
    ;
    try expectPhysicalGolden(source,
        \\physical source_slots=1 value_slots=12 state_slots=0 instructions=12 edges=9
        \\source[0] toggle.event.press : Pulse
        \\
    );
}

test "Physical IR freezes static source spreads" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\copy: [...button]
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR spread failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 2), program.source_slots.len);
    try std.testing.expectEqualStrings("button.event.press", program.source_slots[0].semantic_id);
    try std.testing.expectEqualStrings("copy.event.press", program.source_slots[1].semantic_id);
}

test "Physical IR rejects dynamic source spreads" {
    const source =
        \\copy: [...dynamic_sources()]
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedDynamicSourceShapeFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("dynamic source shape", failure.message),
    }
}

test "Physical IR rejects SOURCE in value expression" {
    const source =
        \\bad: SOURCE + 1
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedInvalidSourceFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("SOURCE marks a runtime source field and cannot be used as a normal value", failure.message),
    }
}

test "Physical IR rejects duplicate source paths" {
    const source =
        \\button: SOURCE
        \\button: SOURCE
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedDuplicateSourcePathFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("multiple active binders", failure.message),
    }
}

test "Physical IR rejects incompatible event namespace binding" {
    const source =
        \\button: [event: SOURCE]
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedIncompatibleSourceBindingFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("incompatible source binding", failure.message),
    }
}

test "Physical IR rejects unnormalized PASS and PASSED specials" {
    const source =
        \\value: PASS
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedPassLoweringFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("PASS/PASSED must be lowered before Physical Runtime execution", failure.message),
    }
}

test "Physical IR normalizes PASS/PASSED user call context before runtime" {
    const source =
        \\FUNCTION increment_from_pass(value) {
        \\    PASSED.event.press |> THEN { value + 1 }
        \\}
        \\
        \\button: [event: [press: SOURCE]]
        \\
        \\counter: 0 |> HOLD counter {
        \\    increment_from_pass(counter, PASS: button)
        \\}
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected PASS/PASSED normalization failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.source_slots.len);
    try std.testing.expect(program.source_slots[0].value_slot != null);
}

test "Physical IR rejects legacy LINK in canonical mode" {
    const source = "button: [event: [press: LINK]]\n";
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedCanonicalLinkFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("`LINK` was renamed to `SOURCE`; use `SOURCE` in canonical source mode", failure.message),
    }
}
