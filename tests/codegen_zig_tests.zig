const std = @import("std");
const boon = @import("boon");

test "Zig codegen emits counter source with numeric source dispatch" {
    const source =
        \\increment_button: [event: [press: SOURCE]]
        \\counter: 0 |> HOLD counter {
        \\    increment_button.event.press |> THEN { counter + 1 }
        \\}
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected Physical IR codegen fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const generated = try boon.codegen_zig.generateAlloc(std.testing.allocator, &program, .{
        .demo_event = .{ .source_slot_id = 0 },
        .source_path = "examples/source_physical/counter/counter.bn",
    });
    defer std.testing.allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "runtime.dispatchEvent") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "std.mem.eql") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "increment_button.event.press") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "semantic_source_map") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "examples/source_physical/counter/counter.bn") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".boon_start = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".generated_start = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "render_blueprint") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "const boon = @import(\"boon\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "generated_physical_program") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "runGeneratedPhysicalRuntimeAdapter") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "GeneratedRuntimeAdapterMismatch") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "switch (source_slot_id)") == null);
}

test "Zig codegen emits direct payload state updates for TodoMVC source lane" {
    const source =
        \\sources: [
        \\    new_todo: [
        \\        event: [
        \\            change: SOURCE
        \\            key_down: SOURCE
        \\        ]
        \\    ]
        \\
        \\    remove_completed_button: [
        \\        event: [press: SOURCE]
        \\        hovered: SOURCE
        \\    ]
        \\]
        \\
        \\draft_title: 0 |> HOLD draft_title {
        \\    sources.new_todo.event.change
        \\}
        \\
        \\submitted_count: 0 |> HOLD submitted_count {
        \\    sources.new_todo.event.key_down |> THEN { submitted_count + 1 }
        \\}
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected TodoMVC Physical IR codegen fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const generated = try boon.codegen_zig.generateAlloc(std.testing.allocator, &program, .{
        .demo_event = .{ .source_slot_id = 0, .payload = .{ .text = "Write tests" } },
    });
    defer std.testing.allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "sources.new_todo.event.change") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".payload = .{ .text = \"Write tests\" }") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "runtime.processQueuedEvents") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "runGeneratedPhysicalRuntimeAdapter") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "std.mem.eql") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "AppState") == null);
}

test "Zig codegen folds static List/latest initial state" {
    const source =
        \\latest: LIST {
        \\    1
        \\    2
        \\}
        \\|> List/latest()
        \\|> HOLD latest {
        \\    SKIP
        \\}
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected List/latest Physical IR codegen fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const generated = try boon.codegen_zig.generateAlloc(std.testing.allocator, &program, .{});
    defer std.testing.allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "generated_physical_program") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "physical_runtime.Runtime.initAlloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".list_latest") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "std.mem.eql") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "AppState") == null);
}

test "Zig codegen emits dynamic List/latest fan-in support coverage" {
    const source =
        \\latest: LIST {
        \\    1
        \\    2
        \\}
        \\|> List/latest()
        \\|> HOLD latest {
        \\    SKIP
        \\}
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected dynamic List/latest Physical IR codegen fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const generated = try boon.codegen_zig.generateAlloc(std.testing.allocator, &program, .{
        .source_path = "examples/source_physical/list_latest_regression/list_latest_regression.bn",
    });
    defer std.testing.allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "ListLatestFanIn") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "deliverDeterministic") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "ExpectedEmptyListLatest") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "ExpectedRemovedListLatestEvent") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "PayloadShapeMismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "remove:todo-1") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "switch (source_slot_id)") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "std.mem.eql") == null);
}

test "Zig codegen emits structured runtime plan for records lists branches and map scopes" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\
        \\person: [name: TEXT { Ada } score: 7]
        \\items: LIST { 1 2 }
        \\mapped: items |> List/map(item, new: [value: item])
        \\branch: button.event.press |> WHILE {
        \\    True => person
        \\    False => [name: TEXT { None } score: 0]
        \\}
        \\
    ;
    const outcome = try boon.physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected structured runtime plan Physical IR codegen fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const generated = try boon.codegen_zig.generateAlloc(std.testing.allocator, &program, .{
        .source_path = "fixtures/physical_runtime/structured_runtime_plan.bn",
    });
    defer std.testing.allocator.free(generated);

    try std.testing.expect(std.mem.indexOf(u8, generated, "const GeneratedRecord_") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "const GeneratedList_") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "const GeneratedBranchState_") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "const GeneratedListMapScope_") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "generated_runtime_plan") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "validateGeneratedRuntimePlan") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "generated_physical_instructions") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "physical_runtime.Runtime.initAlloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, ".item_binding = \"item\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "GeneratedDependencyEdge") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "std.mem.eql") == null);
}
