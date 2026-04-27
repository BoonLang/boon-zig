const std = @import("std");
const physical_ir = @import("physical_ir.zig");

pub const DemoPayload = union(enum) {
    pulse,
    text: []const u8,
};

pub const DemoEvent = struct {
    source_slot_id: physical_ir.SourceSlotId,
    payload: DemoPayload = .pulse,
};

pub const Options = struct {
    demo_event: ?DemoEvent = null,
    source_path: []const u8 = "<memory>",
};

const GeneratedSpan = struct {
    start: usize,
    end: usize,
};

const HoldUpdate = union(enum) {
    direct_payload: physical_ir.SourceSlotId,
    increment: physical_ir.SourceSlotId,
};

const GeneratedState = struct {
    state_slot: physical_ir.StateSlot,
    initial_number: f64 = 0,
    update: ?HoldUpdate = null,
};

pub fn generateAlloc(
    allocator: std.mem.Allocator,
    program: *const physical_ir.PhysicalProgram,
    options: Options,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;

    const states = try collectStates(allocator, program);
    defer allocator.free(states);
    const dispatch_uses_payload = dispatchUsesPayload(states);
    const dispatch_has_updates = dispatchHasUpdates(states);
    const needs_list_latest = hasListLatest(program);

    const source_slot_spans = try allocator.alloc(GeneratedSpan, program.source_slots.len);
    defer allocator.free(source_slot_spans);

    try writer.writeAll(
        \\const std = @import("std");
        \\const boon = @import("boon");
        \\const physical_ir = boon.physical_ir;
        \\const physical_runtime = boon.physical_runtime;
        \\
        \\const RuntimeValue = union(enum) {
        \\    pulse,
        \\    number: f64,
        \\    text: []const u8,
        \\};
        \\
        \\const SourceSlot = struct {
        \\    id: u32,
        \\    semantic_id: []const u8,
        \\};
        \\
        \\const SourceMapEntry = struct {
        \\    semantic_id: []const u8,
        \\    source_path: []const u8,
        \\    boon_start: usize,
        \\    boon_end: usize,
        \\    generated_start: usize,
        \\    generated_end: usize,
        \\    source_slot_id: u32,
        \\};
        \\
        \\const RenderBlueprint = struct {
        \\    node_count: usize,
        \\};
        \\
        \\const source_slots = [_]SourceSlot{
        \\
    );
    for (program.source_slots, 0..) |slot, index| {
        const generated_start = output.written().len;
        try writer.print("    .{{ .id = {d}, .semantic_id = \"", .{slot.id});
        try writeEscapedZigString(writer, slot.semantic_id);
        try writer.writeAll("\" },\n");
        source_slot_spans[index] = .{ .start = generated_start, .end = output.written().len };
    }
    try writer.writeAll(
        \\};
        \\
        \\const semantic_source_map = [_]SourceMapEntry{
        \\
    );
    for (program.source_slots, 0..) |slot, index| {
        try writer.writeAll("    .{ .semantic_id = \"");
        try writeEscapedZigString(writer, slot.semantic_id);
        try writer.writeAll("\", .source_path = \"");
        try writeEscapedZigString(writer, options.source_path);
        try writer.print("\", .boon_start = {d}, .boon_end = {d}, .generated_start = {d}, .generated_end = {d}, .source_slot_id = {d} }},\n", .{
            slot.source_span.start,
            slot.source_span.end,
            source_slot_spans[index].start,
            source_slot_spans[index].end,
            slot.id,
        });
    }
    try writer.writeAll(
        \\};
        \\
    );
    try writer.print(
        \\const render_blueprint: RenderBlueprint = .{{ .node_count = {d} }};
        \\
        \\
    , .{program.render_blueprint.node_count});
    try writeGeneratedRuntimePlan(writer, program);
    try writeStaticPhysicalProgram(writer, program);
    try writePhysicalRuntimeAdapter(writer, options);
    try writer.writeAll(
        \\const AppState = struct {
        \\
    );
    for (states) |state| {
        try writer.print("    state_{d}: RuntimeValue = .{{ .number = {d} }},\n", .{ state.state_slot.id, state.initial_number });
    }
    try writer.writeAll(
        \\
        \\    fn dispatchEvent(self: *AppState, source_slot_id: u32, payload: RuntimeValue) void {
        \\
    );
    if (!dispatch_has_updates) {
        try writer.writeAll(
            \\        _ = self;
            \\        _ = source_slot_id;
            \\
        );
    }
    if (!dispatch_uses_payload) {
        try writer.writeAll(
            \\        _ = payload;
            \\
        );
    }
    if (dispatch_has_updates) {
        try writer.writeAll(
            \\        switch (source_slot_id) {
            \\
        );
        for (states) |state| {
            const update = state.update orelse continue;
            switch (update) {
                .direct_payload => |source_slot_id| {
                    try writer.print(
                        \\            {d} => self.state_{d} = payload,
                        \\
                    , .{ source_slot_id, state.state_slot.id });
                },
                .increment => |source_slot_id| {
                    try writer.print(
                        \\            {d} => switch (self.state_{d}) {{
                        \\                .number => |value| self.state_{d} = .{{ .number = value + 1 }},
                        \\                else => self.state_{d} = .{{ .number = 1 }},
                        \\            }},
                        \\
                    , .{ source_slot_id, state.state_slot.id, state.state_slot.id, state.state_slot.id });
                },
            }
        }
        try writer.writeAll(
            \\            else => {},
            \\        }
            \\
        );
    }
    try writer.writeAll(
        \\    }
        \\
        \\    fn writeSnapshot(self: *const AppState, writer: *std.Io.Writer) !void {
        \\
    );
    if (states.len == 0) {
        try writer.writeAll(
            \\        _ = self;
            \\        _ = writer;
            \\
        );
    }
    for (states) |state| {
        try writer.print("        try writer.writeAll(\"state[{d}]=\");\n", .{state.state_slot.id});
        try writer.print("        try writeRuntimeValue(writer, self.state_{d});\n", .{state.state_slot.id});
        try writer.writeAll("        try writer.writeByte('\\n');\n");
    }
    try writer.writeAll(
        \\    }
        \\};
        \\
        \\fn writeRuntimeValue(writer: *std.Io.Writer, value: RuntimeValue) !void {
        \\    switch (value) {
        \\        .pulse => try writer.writeAll("pulse"),
        \\        .number => |number| try writer.print("number:{d}", .{number}),
        \\        .text => |text| try writer.print("text:{s}", .{text}),
        \\    }
        \\}
        \\
    );
    if (needs_list_latest) try writeListLatestSupport(writer);
    try writer.writeAll(
        \\pub fn main(init: std.process.Init) !void {
        \\    _ = source_slots;
        \\    _ = semantic_source_map;
        \\    _ = render_blueprint;
        \\    _ = generated_runtime_plan;
        \\    try validateGeneratedRuntimePlan();
        \\    var app: AppState = .{};
        \\
    );
    if (needs_list_latest) {
        try writer.writeAll(
            \\    try runListLatestGeneratedSelfTests();
            \\
        );
    }
    if (options.demo_event) |event| {
        try writer.print("    app.dispatchEvent({d}, ", .{event.source_slot_id});
        try writeDemoPayload(writer, event.payload);
        try writer.writeAll(");\n");
    }
    try writer.writeAll(
        \\    try assertGeneratedRuntimeAdapterMatchesApp(std.heap.page_allocator, &app);
        \\    var stdout_buffer: [4096]u8 = undefined;
        \\    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        \\    try app.writeSnapshot(&stdout_writer.interface);
        \\    try stdout_writer.interface.flush();
        \\}
        \\
    );

    return try output.toOwnedSlice();
}

fn collectStates(allocator: std.mem.Allocator, program: *const physical_ir.PhysicalProgram) ![]GeneratedState {
    const states = try allocator.alloc(GeneratedState, program.state_slots.len);
    for (program.state_slots, 0..) |slot, index| {
        states[index] = .{
            .state_slot = slot,
            .initial_number = initialNumber(program, slot.flow_node) orelse 0,
            .update = inferHoldUpdate(program, slot.flow_node),
        };
    }
    return states;
}

fn dispatchUsesPayload(states: []const GeneratedState) bool {
    for (states) |state| {
        const update = state.update orelse continue;
        switch (update) {
            .direct_payload => return true,
            .increment => {},
        }
    }
    return false;
}

fn dispatchHasUpdates(states: []const GeneratedState) bool {
    for (states) |state| {
        if (state.update != null) return true;
    }
    return false;
}

fn hasListLatest(program: *const physical_ir.PhysicalProgram) bool {
    for (program.instructions) |instruction| {
        switch (instruction) {
            .list_latest => return true,
            else => {},
        }
    }
    return false;
}

fn initialNumber(program: *const physical_ir.PhysicalProgram, hold_node: physical_ir.ValueSlotId) ?f64 {
    const hold = holdInstruction(program, hold_node) orelse return null;
    return constantNumber(program, hold.initial);
}

fn constantNumber(program: *const physical_ir.PhysicalProgram, value_slot: physical_ir.ValueSlotId) ?f64 {
    const index: usize = value_slot;
    if (index >= program.instructions.len) return null;
    return switch (program.instructions[index]) {
        .load_number => |number| number.value,
        .list_latest => |latest| latestConstantNumber(program, latest.input),
        else => null,
    };
}

fn latestConstantNumber(program: *const physical_ir.PhysicalProgram, list_slot: physical_ir.ValueSlotId) ?f64 {
    const list_index: usize = list_slot;
    if (list_index >= program.instructions.len) return null;
    const list = switch (program.instructions[list_index]) {
        .load_list => |list| list,
        else => return null,
    };
    if (list.items.len == 0) return null;
    return constantNumber(program, list.items[list.items.len - 1]);
}

fn inferHoldUpdate(program: *const physical_ir.PhysicalProgram, hold_node: physical_ir.ValueSlotId) ?HoldUpdate {
    const hold = holdInstruction(program, hold_node) orelse return null;
    if (hold.updates.len == 0) return null;
    const update = hold.updates[0];
    if (sourceSlotForValueSlot(program, update)) |source_slot_id| return .{ .direct_payload = source_slot_id };

    const update_index: usize = update;
    if (update_index >= program.instructions.len) return null;
    switch (program.instructions[update_index]) {
        .then_value => |then_value| {
            const source_slot_id = sourceSlotForValueSlot(program, then_value.source) orelse return null;
            if (isIncrementOfState(program, then_value.value, hold.state_slot)) return .{ .increment = source_slot_id };
            return null;
        },
        else => return null,
    }
}

fn holdInstruction(program: *const physical_ir.PhysicalProgram, node: physical_ir.ValueSlotId) ?physical_ir.HoldInstruction {
    const index: usize = node;
    if (index >= program.instructions.len) return null;
    return switch (program.instructions[index]) {
        .hold => |hold| hold,
        else => null,
    };
}

fn sourceSlotForValueSlot(program: *const physical_ir.PhysicalProgram, value_slot: physical_ir.ValueSlotId) ?physical_ir.SourceSlotId {
    for (program.source_slots) |slot| {
        if (slot.value_slot == value_slot) return slot.id;
    }
    return null;
}

fn isIncrementOfState(
    program: *const physical_ir.PhysicalProgram,
    value_slot: physical_ir.ValueSlotId,
    state_slot: physical_ir.StateSlotId,
) bool {
    const index: usize = value_slot;
    if (index >= program.instructions.len) return false;
    const binary = switch (program.instructions[index]) {
        .binary => |binary| binary,
        else => return false,
    };
    if (binary.operator != .add) return false;

    const lhs_index: usize = binary.lhs;
    const rhs_index: usize = binary.rhs;
    if (lhs_index >= program.instructions.len or rhs_index >= program.instructions.len) return false;
    const lhs_is_state = switch (program.instructions[lhs_index]) {
        .load_state => |load| load.state_slot == state_slot,
        else => false,
    };
    const rhs_is_one = switch (program.instructions[rhs_index]) {
        .load_number => |number| number.value == 1,
        else => false,
    };
    return lhs_is_state and rhs_is_one;
}

fn writeGeneratedRuntimePlan(writer: *std.Io.Writer, program: *const physical_ir.PhysicalProgram) !void {
    const record_count = countRecordInstructions(program);
    const list_count = countListInstructions(program);
    const branch_count = countBranchInstructions(program);
    const list_map_count = countListMapInstructions(program);
    const dependency_count = program.dependency_edges.len;

    try writer.writeAll(
        \\const GeneratedRecordFieldSpec = struct {
        \\    name: []const u8,
        \\    value_slot_id: u32,
        \\};
        \\
        \\const GeneratedRecordShape = struct {
        \\    dst_slot_id: u32,
        \\    fields: []const GeneratedRecordFieldSpec,
        \\};
        \\
        \\const GeneratedListShape = struct {
        \\    dst_slot_id: u32,
        \\    item_slots: []const u32,
        \\};
        \\
        \\const GeneratedBranchArm = struct {
        \\    pattern_slot_id: u32,
        \\    result_slot_id: u32,
        \\};
        \\
        \\const GeneratedBranchActivation = struct {
        \\    dst_slot_id: u32,
        \\    input_slot_id: u32,
        \\    arms: []const GeneratedBranchArm,
        \\};
        \\
        \\const GeneratedListMapScope = struct {
        \\    dst_slot_id: u32,
        \\    input_slot_id: u32,
        \\    body_slot_id: ?u32,
        \\    item_binding: []const u8,
        \\};
        \\
        \\const GeneratedDependencyEdge = struct {
        \\    from: u32,
        \\    to: u32,
        \\};
        \\
        \\const GeneratedRuntimePlan = struct {
        \\    record_shapes: []const GeneratedRecordShape,
        \\    list_shapes: []const GeneratedListShape,
        \\    branch_activations: []const GeneratedBranchActivation,
        \\    list_map_scopes: []const GeneratedListMapScope,
        \\    dependency_edges: []const GeneratedDependencyEdge,
        \\};
        \\
    );

    for (program.instructions) |instruction| {
        switch (instruction) {
            .record => |record| {
                try writer.print("const GeneratedRecord_{d} = struct {{\n", .{record.dst});
                for (record.fields, 0..) |field, index| {
                    try writer.writeAll("    ");
                    try writeZigFieldIdentifier(writer, field.name, index);
                    try writer.writeAll(": RuntimeValue,\n");
                }
                try writer.writeAll("};\n\n");
            },
            .load_list => |list| {
                try writer.print(
                    \\const GeneratedList_{d} = struct {{
                    \\    items: []const RuntimeValue,
                    \\}};
                    \\
                    \\
                , .{list.dst});
            },
            .when => |when| {
                try writer.print(
                    \\const GeneratedBranchState_{d} = struct {{
                    \\    active_arm_index: ?usize = null,
                    \\    input_slot_id: u32 = {d},
                    \\}};
                    \\
                    \\
                , .{ when.dst, when.input });
            },
            .list_map => |map| {
                try writer.print(
                    \\const GeneratedListMapScope_{d} = struct {{
                    \\    item_id: u64,
                    \\    item_generation: u32,
                    \\
                , .{map.dst});
                try writer.writeAll("    ");
                try writeZigFieldIdentifier(writer, mappedItemName(program, map.body) orelse "item", 0);
                try writer.writeAll(
                    \\: RuntimeValue,
                    \\};
                    \\
                    \\
                );
            },
            else => {},
        }
    }

    for (program.instructions) |instruction| {
        switch (instruction) {
            .record => |record| {
                try writer.print("const generated_record_{d}_fields = [_]GeneratedRecordFieldSpec{{\n", .{record.dst});
                for (record.fields) |field| {
                    try writer.writeAll("    .{ .name = \"");
                    try writeEscapedZigString(writer, field.name);
                    try writer.print("\", .value_slot_id = {d} }},\n", .{field.value});
                }
                try writer.writeAll("};\n\n");
            },
            .load_list => |list| {
                try writer.print("const generated_list_{d}_items = [_]u32{{", .{list.dst});
                for (list.items) |item| try writer.print(" {d},", .{item});
                try writer.writeAll(" };\n\n");
            },
            .when => |when| {
                try writer.print("const generated_branch_{d}_arms = [_]GeneratedBranchArm{{\n", .{when.dst});
                for (when.arms) |arm| {
                    try writer.print("    .{{ .pattern_slot_id = {d}, .result_slot_id = {d} }},\n", .{ arm.pattern, arm.result });
                }
                try writer.writeAll("};\n\n");
            },
            else => {},
        }
    }

    try writer.writeAll("const generated_record_shapes = [_]GeneratedRecordShape{\n");
    for (program.instructions) |instruction| {
        if (instruction == .record) {
            const record = instruction.record;
            try writer.print("    .{{ .dst_slot_id = {d}, .fields = &generated_record_{d}_fields }},\n", .{ record.dst, record.dst });
        }
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("const generated_list_shapes = [_]GeneratedListShape{\n");
    for (program.instructions) |instruction| {
        if (instruction == .load_list) {
            const list = instruction.load_list;
            try writer.print("    .{{ .dst_slot_id = {d}, .item_slots = &generated_list_{d}_items }},\n", .{ list.dst, list.dst });
        }
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("const generated_branch_activations = [_]GeneratedBranchActivation{\n");
    for (program.instructions) |instruction| {
        if (instruction == .when) {
            const when = instruction.when;
            try writer.print("    .{{ .dst_slot_id = {d}, .input_slot_id = {d}, .arms = &generated_branch_{d}_arms }},\n", .{ when.dst, when.input, when.dst });
        }
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("const generated_list_map_scopes = [_]GeneratedListMapScope{\n");
    for (program.instructions) |instruction| {
        if (instruction == .list_map) {
            const map = instruction.list_map;
            try writer.print("    .{{ .dst_slot_id = {d}, .input_slot_id = {d}, .body_slot_id = ", .{ map.dst, map.input });
            if (map.body) |body| {
                try writer.print("{d}", .{body});
            } else {
                try writer.writeAll("null");
            }
            try writer.writeAll(", .item_binding = \"");
            try writeEscapedZigString(writer, mappedItemName(program, map.body) orelse "item");
            try writer.writeAll("\" },\n");
        }
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("const generated_dependency_edges = [_]GeneratedDependencyEdge{\n");
    for (program.dependency_edges) |edge| {
        try writer.print("    .{{ .from = {d}, .to = {d} }},\n", .{ edge.from, edge.to });
    }
    try writer.writeAll(
        \\};
        \\
        \\const generated_runtime_plan: GeneratedRuntimePlan = .{
        \\    .record_shapes = &generated_record_shapes,
        \\    .list_shapes = &generated_list_shapes,
        \\    .branch_activations = &generated_branch_activations,
        \\    .list_map_scopes = &generated_list_map_scopes,
        \\    .dependency_edges = &generated_dependency_edges,
        \\};
        \\
    );
    try writer.print(
        \\fn validateGeneratedRuntimePlan() !void {{
        \\    if (generated_runtime_plan.record_shapes.len != {d}) return error.GeneratedRuntimePlanMismatch;
        \\    if (generated_runtime_plan.list_shapes.len != {d}) return error.GeneratedRuntimePlanMismatch;
        \\    if (generated_runtime_plan.branch_activations.len != {d}) return error.GeneratedRuntimePlanMismatch;
        \\    if (generated_runtime_plan.list_map_scopes.len != {d}) return error.GeneratedRuntimePlanMismatch;
        \\    if (generated_runtime_plan.dependency_edges.len != {d}) return error.GeneratedRuntimePlanMismatch;
        \\    for (generated_runtime_plan.record_shapes) |shape| {{
        \\        if (shape.fields.len == 0) return error.GeneratedRuntimePlanMismatch;
        \\    }}
        \\    for (generated_runtime_plan.list_map_scopes) |scope| {{
        \\        if (scope.item_binding.len == 0) return error.GeneratedRuntimePlanMismatch;
        \\    }}
        \\}}
        \\
        \\
    , .{ record_count, list_count, branch_count, list_map_count, dependency_count });
}

fn writeStaticPhysicalProgram(writer: *std.Io.Writer, program: *const physical_ir.PhysicalProgram) !void {
    for (program.instructions) |instruction| {
        switch (instruction) {
            .record => |record| {
                try writer.print("var generated_physical_record_{d}_fields = [_]physical_ir.RecordFieldInstruction{{\n", .{record.dst});
                for (record.fields) |field| {
                    try writer.writeAll("    .{ .name = \"");
                    try writeEscapedZigString(writer, field.name);
                    try writer.print("\", .value = {d} }},\n", .{field.value});
                }
                try writer.writeAll("};\n\n");
            },
            .load_list => |list| try writeValueSlotArray(writer, "generated_physical_list", list.dst, "items", list.items),
            .text => |text| try writeValueSlotArray(writer, "generated_physical_text", text.dst, "parts", text.parts),
            .when => |when| {
                try writer.print("var generated_physical_when_{d}_arms = [_]physical_ir.WhenArmInstruction{{\n", .{when.dst});
                for (when.arms) |arm| {
                    try writer.print("    .{{ .pattern = {d}, .result = {d} }},\n", .{ arm.pattern, arm.result });
                }
                try writer.writeAll("};\n\n");
            },
            .latest => |latest| try writeValueSlotArray(writer, "generated_physical_latest", latest.dst, "sources", latest.sources),
            .hold => |hold| try writeValueSlotArray(writer, "generated_physical_hold", hold.dst, "updates", hold.updates),
            else => {},
        }
    }

    try writer.writeAll("var generated_physical_source_slots = [_]physical_ir.SourceSlot{\n");
    for (program.source_slots) |slot| {
        try writer.writeAll("    .{ .id = ");
        try writer.print("{d}, .semantic_id = \"", .{slot.id});
        try writeEscapedZigString(writer, slot.semantic_id);
        try writer.writeAll("\", .payload_type = \"");
        try writeEscapedZigString(writer, slot.payload_type);
        try writer.print("\", .source_span = .{{ .start = {d}, .end = {d} }}, .value_slot = ", .{ slot.source_span.start, slot.source_span.end });
        if (slot.value_slot) |value_slot| {
            try writer.print("{d}", .{value_slot});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(" },\n");
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("var generated_physical_value_slots = [_]physical_ir.ValueSlot{\n");
    for (program.value_slots) |slot| {
        try writer.print("    .{{ .id = {d}, .semantic_id = \"", .{slot.id});
        try writeEscapedZigString(writer, slot.semantic_id);
        try writer.print("\", .flow_node = {d} }},\n", .{slot.flow_node});
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("var generated_physical_state_slots = [_]physical_ir.StateSlot{\n");
    for (program.state_slots) |slot| {
        try writer.print("    .{{ .id = {d}, .semantic_id = \"", .{slot.id});
        try writeEscapedZigString(writer, slot.semantic_id);
        try writer.print("\", .flow_node = {d} }},\n", .{slot.flow_node});
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("var generated_physical_dependency_edges = [_]physical_ir.DependencyEdge{\n");
    for (program.dependency_edges) |edge| {
        try writer.print("    .{{ .from = {d}, .to = {d} }},\n", .{ edge.from, edge.to });
    }
    try writer.writeAll("};\n\n");

    try writer.writeAll("var generated_physical_instructions = [_]physical_ir.Instruction{\n");
    for (program.instructions) |instruction| {
        try writer.writeAll("    ");
        try writePhysicalInstructionLiteral(writer, instruction);
        try writer.writeAll(",\n");
    }
    try writer.writeAll(
        \\};
        \\
        \\var generated_physical_program: physical_ir.PhysicalProgram = .{
        \\    .arena = undefined,
        \\    .source_slots = &generated_physical_source_slots,
        \\    .value_slots = &generated_physical_value_slots,
        \\    .state_slots = &generated_physical_state_slots,
        \\    .instructions = &generated_physical_instructions,
        \\    .dependency_edges = &generated_physical_dependency_edges,
        \\    .branch_table = .{
    );
    try writer.print(".count = {d}", .{program.branch_table.count});
    try writer.writeAll(
        \\ },
        \\    .list_table = .{
    );
    try writer.print(".count = {d}", .{program.list_table.count});
    try writer.writeAll(
        \\ },
        \\    .render_blueprint = .{
    );
    try writer.print(".node_count = {d}", .{program.render_blueprint.node_count});
    try writer.writeAll(
        \\ },
        \\};
        \\
        \\
    );
}

fn writeValueSlotArray(
    writer: *std.Io.Writer,
    prefix: []const u8,
    dst: physical_ir.ValueSlotId,
    field_name: []const u8,
    values: []const physical_ir.ValueSlotId,
) !void {
    try writer.print("var {s}_{d}_{s} = [_]physical_ir.ValueSlotId{{", .{ prefix, dst, field_name });
    for (values) |value| try writer.print(" {d},", .{value});
    try writer.writeAll(" };\n\n");
}

fn writePhysicalInstructionLiteral(writer: *std.Io.Writer, instruction: physical_ir.Instruction) !void {
    switch (instruction) {
        .noop => try writer.writeAll(".noop"),
        .load_empty => |dst| try writer.print(".{{ .load_empty = {d} }}", .{dst}),
        .load_number => |load| try writer.print(".{{ .load_number = .{{ .dst = {d}, .value = {d} }} }}", .{ load.dst, load.value }),
        .load_atom => |load| {
            try writer.print(".{{ .load_atom = .{{ .dst = {d}, .text = \"", .{load.dst});
            try writeEscapedZigString(writer, load.text);
            try writer.writeAll("\" } }");
        },
        .load_list => |list| try writer.print(".{{ .load_list = .{{ .dst = {d}, .items = &generated_physical_list_{d}_items }} }}", .{ list.dst, list.dst }),
        .text => |text| try writer.print(".{{ .text = .{{ .dst = {d}, .parts = &generated_physical_text_{d}_parts }} }}", .{ text.dst, text.dst }),
        .load_state => |load| try writer.print(".{{ .load_state = .{{ .dst = {d}, .state_slot = {d} }} }}", .{ load.dst, load.state_slot }),
        .load_mapped_item => |mapped| {
            try writer.print(".{{ .load_mapped_item = .{{ .dst = {d}, .name = \"", .{mapped.dst});
            try writeEscapedZigString(writer, mapped.name);
            try writer.writeAll("\" } }");
        },
        .record => |record| try writer.print(".{{ .record = .{{ .dst = {d}, .fields = &generated_physical_record_{d}_fields }} }}", .{ record.dst, record.dst }),
        .binary => |binary| try writer.print(
            ".{{ .binary = .{{ .dst = {d}, .operator = .{s}, .lhs = {d}, .rhs = {d} }} }}",
            .{ binary.dst, @tagName(binary.operator), binary.lhs, binary.rhs },
        ),
        .when => |when| try writer.print(".{{ .when = .{{ .dst = {d}, .input = {d}, .arms = &generated_physical_when_{d}_arms }} }}", .{ when.dst, when.input, when.dst }),
        .block => |block| try writer.print(".{{ .block = .{{ .dst = {d}, .result = {d} }} }}", .{ block.dst, block.result }),
        .list_map => |map| {
            try writer.print(".{{ .list_map = .{{ .dst = {d}, .input = {d}, .body = ", .{ map.dst, map.input });
            if (map.body) |body| {
                try writer.print("{d}", .{body});
            } else {
                try writer.writeAll("null");
            }
            try writer.writeAll(" } }");
        },
        .list_latest => |latest| try writer.print(".{{ .list_latest = .{{ .dst = {d}, .input = {d} }} }}", .{ latest.dst, latest.input }),
        .then_value => |then_value| try writer.print(".{{ .then_value = .{{ .dst = {d}, .source = {d}, .value = {d} }} }}", .{ then_value.dst, then_value.source, then_value.value }),
        .latest => |latest| {
            try writer.print(".{{ .latest = .{{ .dst = {d}, .initial = ", .{latest.dst});
            if (latest.initial) |initial| {
                try writer.print("{d}", .{initial});
            } else {
                try writer.writeAll("null");
            }
            try writer.print(", .sources = &generated_physical_latest_{d}_sources }} }}", .{latest.dst});
        },
        .hold => |hold| try writer.print(
            ".{{ .hold = .{{ .dst = {d}, .state_slot = {d}, .initial = {d}, .updates = &generated_physical_hold_{d}_updates }} }}",
            .{ hold.dst, hold.state_slot, hold.initial, hold.dst },
        ),
        .eval_flow_node => |dst| try writer.print(".{{ .eval_flow_node = {d} }}", .{dst}),
    }
}

fn writePhysicalRuntimeAdapter(writer: *std.Io.Writer, options: Options) !void {
    try writer.writeAll(
        \\fn runGeneratedPhysicalRuntimeAdapter(allocator: std.mem.Allocator) ![]u8 {
        \\    var runtime = try physical_runtime.Runtime.initAlloc(allocator, &generated_physical_program);
        \\    defer runtime.deinit();
        \\    try runtime.executeInitializers(&generated_physical_program);
        \\
    );
    if (options.demo_event) |event| {
        try writer.print(
            \\    try runtime.plugSource({d}, 1);
            \\    const dispatch_result = try runtime.dispatchEvent(.{{
            \\        .source_slot_id = {d},
            \\        .binding_id_or_generation = 1,
            \\        .scope_or_instance_id = 0,
            \\        .payload = 
        , .{ event.source_slot_id, event.source_slot_id });
        try writePhysicalRuntimePayload(writer, event.payload);
        try writer.writeAll(
            \\,
            \\    });
            \\    if (dispatch_result != .queued) return error.GeneratedRuntimeAdapterDispatchFailed;
            \\    try runtime.processQueuedEvents(&generated_physical_program);
            \\
        );
    }
    try writer.writeAll(
        \\    return try runtime.stateSnapshotAlloc(allocator);
        \\}
        \\
        \\fn appSnapshotAlloc(allocator: std.mem.Allocator, app: *const AppState) ![]u8 {
        \\    var output: std.Io.Writer.Allocating = .init(allocator);
        \\    defer output.deinit();
        \\    try app.writeSnapshot(&output.writer);
        \\    return try output.toOwnedSlice();
        \\}
        \\
        \\fn assertGeneratedRuntimeAdapterMatchesApp(allocator: std.mem.Allocator, app: *const AppState) !void {
        \\    const app_snapshot = try appSnapshotAlloc(allocator, app);
        \\    defer allocator.free(app_snapshot);
        \\    const runtime_snapshot = try runGeneratedPhysicalRuntimeAdapter(allocator);
        \\    defer allocator.free(runtime_snapshot);
        \\    if (!bytesEqual(app_snapshot, runtime_snapshot)) return error.GeneratedRuntimeAdapterMismatch;
        \\}
        \\
        \\fn bytesEqual(lhs: []const u8, rhs: []const u8) bool {
        \\    if (lhs.len != rhs.len) return false;
        \\    for (lhs, rhs) |left, right| {
        \\        if (left != right) return false;
        \\    }
        \\    return true;
        \\}
        \\
        \\
    );
}

fn writePhysicalRuntimePayload(writer: *std.Io.Writer, payload: DemoPayload) !void {
    switch (payload) {
        .pulse => try writer.writeAll(".pulse"),
        .text => |text| {
            try writer.writeAll(".{ .text = \"");
            try writeEscapedZigString(writer, text);
            try writer.writeAll("\" }");
        },
    }
}

fn countRecordInstructions(program: *const physical_ir.PhysicalProgram) usize {
    var count: usize = 0;
    for (program.instructions) |instruction| {
        if (instruction == .record) count += 1;
    }
    return count;
}

fn countListInstructions(program: *const physical_ir.PhysicalProgram) usize {
    var count: usize = 0;
    for (program.instructions) |instruction| {
        if (instruction == .load_list) count += 1;
    }
    return count;
}

fn countBranchInstructions(program: *const physical_ir.PhysicalProgram) usize {
    var count: usize = 0;
    for (program.instructions) |instruction| {
        if (instruction == .when) count += 1;
    }
    return count;
}

fn countListMapInstructions(program: *const physical_ir.PhysicalProgram) usize {
    var count: usize = 0;
    for (program.instructions) |instruction| {
        if (instruction == .list_map) count += 1;
    }
    return count;
}

fn mappedItemName(program: *const physical_ir.PhysicalProgram, maybe_body: ?physical_ir.ValueSlotId) ?[]const u8 {
    const body = maybe_body orelse return null;
    return mappedItemNameFromSlot(program, body);
}

fn mappedItemNameFromSlot(program: *const physical_ir.PhysicalProgram, slot_id: physical_ir.ValueSlotId) ?[]const u8 {
    const index: usize = slot_id;
    if (index >= program.instructions.len) return null;
    return switch (program.instructions[index]) {
        .load_mapped_item => |mapped| mapped.name,
        .binary => |binary| mappedItemNameFromSlot(program, binary.lhs) orelse mappedItemNameFromSlot(program, binary.rhs),
        .text => |text| {
            for (text.parts) |part| {
                if (mappedItemNameFromSlot(program, part)) |name| return name;
            }
            return null;
        },
        .block => |block| mappedItemNameFromSlot(program, block.result),
        .when => |when| {
            if (mappedItemNameFromSlot(program, when.input)) |name| return name;
            for (when.arms) |arm| {
                if (mappedItemNameFromSlot(program, arm.pattern)) |name| return name;
                if (mappedItemNameFromSlot(program, arm.result)) |name| return name;
            }
            return null;
        },
        .record => |record| {
            for (record.fields) |field| {
                if (mappedItemNameFromSlot(program, field.value)) |name| return name;
            }
            return null;
        },
        else => null,
    };
}

fn writeListLatestSupport(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\const RuntimeValueTag = enum {
        \\    pulse,
        \\    number,
        \\    text,
        \\};
        \\
        \\const GeneratedListItem = struct {
        \\    id: u32,
        \\    generation: u32,
        \\    value: RuntimeValue,
        \\};
        \\
        \\const SourceSubscription = struct {
        \\    item_id: u32,
        \\    generation: u32,
        \\    listener_slot_id: u32,
        \\};
        \\
        \\const FanInDelivery = struct {
        \\    subscription: SourceSubscription,
        \\    payload: RuntimeValue,
        \\};
        \\
        \\const GeneratedList = struct {
        \\    items: []const GeneratedListItem,
        \\
        \\    fn subscribe(self: *const GeneratedList, listener_slot_id: u32, item_id: u32) ?SourceSubscription {
        \\        for (self.items) |item| {
        \\            if (item.id == item_id) {
        \\                return .{ .item_id = item.id, .generation = item.generation, .listener_slot_id = listener_slot_id };
        \\            }
        \\        }
        \\        return null;
        \\    }
        \\
        \\    fn accepts(self: *const GeneratedList, subscription: SourceSubscription) bool {
        \\        for (self.items) |item| {
        \\            if (item.id == subscription.item_id) {
        \\                return item.generation == subscription.generation;
        \\            }
        \\        }
        \\        return false;
        \\    }
        \\};
        \\
        \\const ListLatestFanIn = struct {
        \\    latest: ?RuntimeValue = null,
        \\    latest_tag: ?RuntimeValueTag = null,
        \\
        \\    fn deliver(self: *ListLatestFanIn, list: *const GeneratedList, delivery: FanInDelivery) !?RuntimeValue {
        \\        if (!list.accepts(delivery.subscription)) return null;
        \\        const tag = runtimeValueTag(delivery.payload);
        \\        if (self.latest_tag) |expected| {
        \\            if (expected != tag) return error.PayloadShapeMismatch;
        \\        }
        \\        self.latest_tag = tag;
        \\        self.latest = delivery.payload;
        \\        return delivery.payload;
        \\    }
        \\
        \\    fn deliverDeterministic(
        \\        self: *ListLatestFanIn,
        \\        output: []RuntimeValue,
        \\        list: *const GeneratedList,
        \\        deliveries: []const FanInDelivery,
        \\    ) ![]const RuntimeValue {
        \\        var count: usize = 0;
        \\        for (list.items) |item| {
        \\            for (deliveries) |delivery| {
        \\                if (delivery.subscription.item_id != item.id) continue;
        \\                if (try self.deliver(list, delivery)) |value| {
        \\                    output[count] = value;
        \\                    count += 1;
        \\                }
        \\            }
        \\        }
        \\        return output[0..count];
        \\    }
        \\};
        \\
        \\fn runtimeValueTag(value: RuntimeValue) RuntimeValueTag {
        \\    return switch (value) {
        \\        .pulse => .pulse,
        \\        .number => .number,
        \\        .text => .text,
        \\    };
        \\}
        \\
        \\fn expectNumber(value: RuntimeValue, expected: f64) !void {
        \\    switch (value) {
        \\        .number => |actual| if (actual != expected) return error.UnexpectedListLatestValue,
        \\        else => return error.UnexpectedListLatestValue,
        \\    }
        \\}
        \\
        \\fn expectTextPrefix(value: RuntimeValue, first_byte: u8) !void {
        \\    switch (value) {
        \\        .text => |actual| if (actual.len == 0 or actual[0] != first_byte) return error.UnexpectedListLatestValue,
        \\        else => return error.UnexpectedListLatestValue,
        \\    }
        \\}
        \\
        \\fn runListLatestGeneratedSelfTests() !void {
        \\    const empty_list: GeneratedList = .{ .items = &.{} };
        \\    var empty_fan_in: ListLatestFanIn = .{};
        \\    var empty_buffer: [1]RuntimeValue = undefined;
        \\    const empty = try empty_fan_in.deliverDeterministic(&empty_buffer, &empty_list, &.{});
        \\    if (empty.len != 0) return error.ExpectedEmptyListLatest;
        \\
        \\    const ordered_items = [_]GeneratedListItem{
        \\        .{ .id = 1, .generation = 0, .value = .{ .text = "first" } },
        \\        .{ .id = 2, .generation = 0, .value = .{ .text = "second" } },
        \\    };
        \\    const ordered_list: GeneratedList = .{ .items = &ordered_items };
        \\    var ordered_fan_in: ListLatestFanIn = .{};
        \\    var ordered_buffer: [2]RuntimeValue = undefined;
        \\    const ordered_deliveries = [_]FanInDelivery{
        \\        .{ .subscription = ordered_list.subscribe(9, 2).?, .payload = .{ .number = 2 } },
        \\        .{ .subscription = ordered_list.subscribe(9, 1).?, .payload = .{ .number = 1 } },
        \\    };
        \\    const ordered = try ordered_fan_in.deliverDeterministic(&ordered_buffer, &ordered_list, &ordered_deliveries);
        \\    if (ordered.len != 2) return error.UnexpectedListLatestValue;
        \\    try expectNumber(ordered[0], 1);
        \\    try expectNumber(ordered[1], 2);
        \\
        \\    const removed_subscription = ordered_list.subscribe(9, 1).?;
        \\    const removed_items = [_]GeneratedListItem{ordered_items[1]};
        \\    const removed_list: GeneratedList = .{ .items = &removed_items };
        \\    var removed_fan_in: ListLatestFanIn = .{};
        \\    if (try removed_fan_in.deliver(&removed_list, .{ .subscription = removed_subscription, .payload = .pulse }) != null) {
        \\        return error.ExpectedRemovedListLatestEvent;
        \\    }
        \\
        \\    const reordered_items = [_]GeneratedListItem{ ordered_items[1], ordered_items[0] };
        \\    const reordered_list: GeneratedList = .{ .items = &reordered_items };
        \\    var reordered_fan_in: ListLatestFanIn = .{};
        \\    var reordered_buffer: [2]RuntimeValue = undefined;
        \\    const reordered_deliveries = [_]FanInDelivery{
        \\        .{ .subscription = reordered_list.subscribe(9, 1).?, .payload = .{ .number = 1 } },
        \\        .{ .subscription = reordered_list.subscribe(9, 2).?, .payload = .{ .number = 2 } },
        \\    };
        \\    const reordered = try reordered_fan_in.deliverDeterministic(&reordered_buffer, &reordered_list, &reordered_deliveries);
        \\    if (reordered.len != 2) return error.UnexpectedListLatestValue;
        \\    try expectNumber(reordered[0], 2);
        \\    try expectNumber(reordered[1], 1);
        \\
        \\    var mismatch_fan_in: ListLatestFanIn = .{};
        \\    _ = try mismatch_fan_in.deliver(&ordered_list, .{
        \\        .subscription = ordered_list.subscribe(9, 1).?,
        \\        .payload = .{ .number = 1 },
        \\    });
        \\    var saw_payload_shape_mismatch = false;
        \\    const mismatch_delivery = mismatch_fan_in.deliver(&ordered_list, .{
        \\        .subscription = ordered_list.subscribe(9, 2).?,
        \\        .payload = .{ .text = "bad" },
        \\    }) catch |err| blk: {
        \\        if (err != error.PayloadShapeMismatch) return err;
        \\        saw_payload_shape_mismatch = true;
        \\        break :blk null;
        \\    };
        \\    if (!saw_payload_shape_mismatch) return error.ExpectedPayloadShapeMismatch;
        \\    if (mismatch_delivery != null) return error.ExpectedPayloadShapeMismatch;
        \\
        \\    var todo_fan_in: ListLatestFanIn = .{};
        \\    const todo_delivery = try todo_fan_in.deliver(&ordered_list, .{
        \\        .subscription = ordered_list.subscribe(7, 1).?,
        \\        .payload = .{ .text = "remove:todo-1" },
        \\    }) orelse return error.UnexpectedListLatestValue;
        \\    try expectTextPrefix(todo_delivery, 'r');
        \\}
        \\
    );
}

fn writeDemoPayload(writer: *std.Io.Writer, payload: DemoPayload) !void {
    switch (payload) {
        .pulse => try writer.writeAll(".pulse"),
        .text => |text| {
            try writer.writeAll(".{ .text = \"");
            try writeEscapedZigString(writer, text);
            try writer.writeAll("\" }");
        },
    }
}

fn writeEscapedZigString(writer: *std.Io.Writer, text: []const u8) !void {
    for (text) |byte| {
        switch (byte) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
}

fn writeZigFieldIdentifier(writer: *std.Io.Writer, name: []const u8, fallback_index: usize) !void {
    if (isSimpleZigIdentifier(name) and !isZigKeyword(name)) {
        try writer.writeAll(name);
        return;
    }
    try writer.print("field_{d}", .{fallback_index});
}

fn isSimpleZigIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!isZigIdentifierStart(name[0])) return false;
    for (name[1..]) |byte| {
        if (!isZigIdentifierContinue(byte)) return false;
    }
    return true;
}

fn isZigIdentifierStart(byte: u8) bool {
    return byte == '_' or std.ascii.isAlphabetic(byte);
}

fn isZigIdentifierContinue(byte: u8) bool {
    return isZigIdentifierStart(byte) or std.ascii.isDigit(byte);
}

fn isZigKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "addrspace",
        "align",
        "allowzero",
        "and",
        "anyframe",
        "anytype",
        "asm",
        "async",
        "await",
        "break",
        "callconv",
        "catch",
        "comptime",
        "const",
        "continue",
        "defer",
        "else",
        "enum",
        "errdefer",
        "error",
        "export",
        "extern",
        "fn",
        "for",
        "if",
        "inline",
        "noalias",
        "noinline",
        "nosuspend",
        "opaque",
        "or",
        "orelse",
        "packed",
        "pub",
        "resume",
        "return",
        "linksection",
        "struct",
        "suspend",
        "switch",
        "test",
        "threadlocal",
        "try",
        "union",
        "unreachable",
        "usingnamespace",
        "var",
        "volatile",
        "while",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, name, keyword)) return true;
    }
    return false;
}

test "generates counter source with numeric dispatch" {
    const source =
        \\increment_button: [event: [press: SOURCE]]
        \\counter: 0 |> HOLD counter {
        \\    increment_button.event.press |> THEN { counter + 1 }
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected Physical IR codegen fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const generated = try generateAlloc(std.testing.allocator, &program, .{
        .demo_event = .{ .source_slot_id = 0 },
    });
    defer std.testing.allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "switch (source_slot_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "std.mem.eql") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "increment_button.event.press") != null);
}
