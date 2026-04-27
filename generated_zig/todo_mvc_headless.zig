const std = @import("std");
const boon = @import("boon");
const physical_ir = boon.physical_ir;
const physical_runtime = boon.physical_runtime;

const RuntimeValue = union(enum) {
    pulse,
    number: f64,
    text: []const u8,
};

const SourceSlot = struct {
    id: u32,
    semantic_id: []const u8,
};

const SourceMapEntry = struct {
    semantic_id: []const u8,
    source_path: []const u8,
    boon_start: usize,
    boon_end: usize,
    generated_start: usize,
    generated_end: usize,
    source_slot_id: u32,
};

const RenderBlueprint = struct {
    node_count: usize,
};

const source_slots = [_]SourceSlot{
    .{ .id = 0, .semantic_id = "sources.new_todo.event.change" },
    .{ .id = 1, .semantic_id = "sources.new_todo.event.key_down" },
    .{ .id = 2, .semantic_id = "sources.remove_completed_button.event.press" },
    .{ .id = 3, .semantic_id = "sources.remove_completed_button.hovered" },
};

const semantic_source_map = [_]SourceMapEntry{
    .{ .semantic_id = "sources.new_todo.event.change", .source_path = "examples/source_physical/todo_mvc/todo_mvc.bn", .boon_start = 64, .boon_end = 70, .generated_start = 621, .generated_end = 687, .source_slot_id = 0 },
    .{ .semantic_id = "sources.new_todo.event.key_down", .source_path = "examples/source_physical/todo_mvc/todo_mvc.bn", .boon_start = 93, .boon_end = 99, .generated_start = 687, .generated_end = 755, .source_slot_id = 1 },
    .{ .semantic_id = "sources.remove_completed_button.event.press", .source_path = "examples/source_physical/todo_mvc/todo_mvc.bn", .boon_start = 171, .boon_end = 177, .generated_start = 755, .generated_end = 835, .source_slot_id = 2 },
    .{ .semantic_id = "sources.remove_completed_button.hovered", .source_path = "examples/source_physical/todo_mvc/todo_mvc.bn", .boon_start = 196, .boon_end = 202, .generated_start = 835, .generated_end = 911, .source_slot_id = 3 },
};
const render_blueprint: RenderBlueprint = .{ .node_count = 25 };

const GeneratedRecordFieldSpec = struct {
    name: []const u8,
    value_slot_id: u32,
};

const GeneratedRecordShape = struct {
    dst_slot_id: u32,
    fields: []const GeneratedRecordFieldSpec,
};

const GeneratedListShape = struct {
    dst_slot_id: u32,
    item_slots: []const u32,
};

const GeneratedBranchArm = struct {
    pattern_slot_id: u32,
    result_slot_id: u32,
};

const GeneratedBranchActivation = struct {
    dst_slot_id: u32,
    input_slot_id: u32,
    arms: []const GeneratedBranchArm,
};

const GeneratedListMapScope = struct {
    dst_slot_id: u32,
    input_slot_id: u32,
    body_slot_id: ?u32,
    item_binding: []const u8,
};

const GeneratedDependencyEdge = struct {
    from: u32,
    to: u32,
};

const GeneratedRuntimePlan = struct {
    record_shapes: []const GeneratedRecordShape,
    list_shapes: []const GeneratedListShape,
    branch_activations: []const GeneratedBranchActivation,
    list_map_scopes: []const GeneratedListMapScope,
    dependency_edges: []const GeneratedDependencyEdge,
};
const GeneratedRecord_2 = struct {
    change: RuntimeValue,
    key_down: RuntimeValue,
};

const GeneratedRecord_3 = struct {
    event: RuntimeValue,
};

const GeneratedRecord_5 = struct {
    press: RuntimeValue,
};

const GeneratedRecord_7 = struct {
    event: RuntimeValue,
    hovered: RuntimeValue,
};

const GeneratedRecord_8 = struct {
    new_todo: RuntimeValue,
    remove_completed_button: RuntimeValue,
};

const generated_record_2_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "change", .value_slot_id = 0 },
    .{ .name = "key_down", .value_slot_id = 1 },
};

const generated_record_3_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "event", .value_slot_id = 2 },
};

const generated_record_5_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "press", .value_slot_id = 4 },
};

const generated_record_7_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "event", .value_slot_id = 5 },
    .{ .name = "hovered", .value_slot_id = 6 },
};

const generated_record_8_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "new_todo", .value_slot_id = 3 },
    .{ .name = "remove_completed_button", .value_slot_id = 7 },
};

const generated_record_shapes = [_]GeneratedRecordShape{
    .{ .dst_slot_id = 2, .fields = &generated_record_2_fields },
    .{ .dst_slot_id = 3, .fields = &generated_record_3_fields },
    .{ .dst_slot_id = 5, .fields = &generated_record_5_fields },
    .{ .dst_slot_id = 7, .fields = &generated_record_7_fields },
    .{ .dst_slot_id = 8, .fields = &generated_record_8_fields },
};

const generated_list_shapes = [_]GeneratedListShape{};

const generated_branch_activations = [_]GeneratedBranchActivation{};

const generated_list_map_scopes = [_]GeneratedListMapScope{};

const generated_dependency_edges = [_]GeneratedDependencyEdge{
    .{ .from = 0, .to = 2 },
    .{ .from = 1, .to = 2 },
    .{ .from = 2, .to = 3 },
    .{ .from = 4, .to = 5 },
    .{ .from = 5, .to = 7 },
    .{ .from = 6, .to = 7 },
    .{ .from = 3, .to = 8 },
    .{ .from = 7, .to = 8 },
    .{ .from = 10, .to = 11 },
    .{ .from = 11, .to = 12 },
    .{ .from = 12, .to = 13 },
    .{ .from = 9, .to = 14 },
    .{ .from = 13, .to = 14 },
    .{ .from = 16, .to = 17 },
    .{ .from = 17, .to = 18 },
    .{ .from = 18, .to = 19 },
    .{ .from = 20, .to = 22 },
    .{ .from = 21, .to = 22 },
    .{ .from = 19, .to = 23 },
    .{ .from = 22, .to = 23 },
    .{ .from = 15, .to = 24 },
    .{ .from = 23, .to = 24 },
};

const generated_runtime_plan: GeneratedRuntimePlan = .{
    .record_shapes = &generated_record_shapes,
    .list_shapes = &generated_list_shapes,
    .branch_activations = &generated_branch_activations,
    .list_map_scopes = &generated_list_map_scopes,
    .dependency_edges = &generated_dependency_edges,
};
fn validateGeneratedRuntimePlan() !void {
    if (generated_runtime_plan.record_shapes.len != 5) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.list_shapes.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.branch_activations.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.list_map_scopes.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.dependency_edges.len != 22) return error.GeneratedRuntimePlanMismatch;
    for (generated_runtime_plan.record_shapes) |shape| {
        if (shape.fields.len == 0) return error.GeneratedRuntimePlanMismatch;
    }
    for (generated_runtime_plan.list_map_scopes) |scope| {
        if (scope.item_binding.len == 0) return error.GeneratedRuntimePlanMismatch;
    }
}

var generated_physical_record_2_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "change", .value = 0 },
    .{ .name = "key_down", .value = 1 },
};

var generated_physical_record_3_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "event", .value = 2 },
};

var generated_physical_record_5_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "press", .value = 4 },
};

var generated_physical_record_7_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "event", .value = 5 },
    .{ .name = "hovered", .value = 6 },
};

var generated_physical_record_8_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "new_todo", .value = 3 },
    .{ .name = "remove_completed_button", .value = 7 },
};

var generated_physical_hold_14_updates = [_]physical_ir.ValueSlotId{
    13,
};

var generated_physical_hold_24_updates = [_]physical_ir.ValueSlotId{
    23,
};

var generated_physical_source_slots = [_]physical_ir.SourceSlot{
    .{ .id = 0, .semantic_id = "sources.new_todo.event.change", .payload_type = "TextChange", .source_span = .{ .start = 64, .end = 70 }, .value_slot = 13 },
    .{ .id = 1, .semantic_id = "sources.new_todo.event.key_down", .payload_type = "KeyEvent", .source_span = .{ .start = 93, .end = 99 }, .value_slot = 19 },
    .{ .id = 2, .semantic_id = "sources.remove_completed_button.event.press", .payload_type = "Pulse", .source_span = .{ .start = 171, .end = 177 }, .value_slot = null },
    .{ .id = 3, .semantic_id = "sources.remove_completed_button.hovered", .payload_type = "Bool", .source_span = .{ .start = 196, .end = 202 }, .value_slot = null },
};

var generated_physical_value_slots = [_]physical_ir.ValueSlot{
    .{ .id = 0, .semantic_id = "flow.n0", .flow_node = 0 },
    .{ .id = 1, .semantic_id = "flow.n1", .flow_node = 1 },
    .{ .id = 2, .semantic_id = "flow.n2", .flow_node = 2 },
    .{ .id = 3, .semantic_id = "flow.n3", .flow_node = 3 },
    .{ .id = 4, .semantic_id = "flow.n4", .flow_node = 4 },
    .{ .id = 5, .semantic_id = "flow.n5", .flow_node = 5 },
    .{ .id = 6, .semantic_id = "flow.n6", .flow_node = 6 },
    .{ .id = 7, .semantic_id = "flow.n7", .flow_node = 7 },
    .{ .id = 8, .semantic_id = "flow.n8", .flow_node = 8 },
    .{ .id = 9, .semantic_id = "flow.n9", .flow_node = 9 },
    .{ .id = 10, .semantic_id = "flow.n10", .flow_node = 10 },
    .{ .id = 11, .semantic_id = "flow.n11", .flow_node = 11 },
    .{ .id = 12, .semantic_id = "flow.n12", .flow_node = 12 },
    .{ .id = 13, .semantic_id = "flow.n13", .flow_node = 13 },
    .{ .id = 14, .semantic_id = "flow.n14", .flow_node = 14 },
    .{ .id = 15, .semantic_id = "flow.n15", .flow_node = 15 },
    .{ .id = 16, .semantic_id = "flow.n16", .flow_node = 16 },
    .{ .id = 17, .semantic_id = "flow.n17", .flow_node = 17 },
    .{ .id = 18, .semantic_id = "flow.n18", .flow_node = 18 },
    .{ .id = 19, .semantic_id = "flow.n19", .flow_node = 19 },
    .{ .id = 20, .semantic_id = "flow.n20", .flow_node = 20 },
    .{ .id = 21, .semantic_id = "flow.n21", .flow_node = 21 },
    .{ .id = 22, .semantic_id = "flow.n22", .flow_node = 22 },
    .{ .id = 23, .semantic_id = "flow.n23", .flow_node = 23 },
    .{ .id = 24, .semantic_id = "flow.n24", .flow_node = 24 },
};

var generated_physical_state_slots = [_]physical_ir.StateSlot{
    .{ .id = 0, .semantic_id = "hold.draft_title", .flow_node = 14 },
    .{ .id = 1, .semantic_id = "hold.submitted_count", .flow_node = 24 },
};

var generated_physical_dependency_edges = [_]physical_ir.DependencyEdge{
    .{ .from = 0, .to = 2 },
    .{ .from = 1, .to = 2 },
    .{ .from = 2, .to = 3 },
    .{ .from = 4, .to = 5 },
    .{ .from = 5, .to = 7 },
    .{ .from = 6, .to = 7 },
    .{ .from = 3, .to = 8 },
    .{ .from = 7, .to = 8 },
    .{ .from = 10, .to = 11 },
    .{ .from = 11, .to = 12 },
    .{ .from = 12, .to = 13 },
    .{ .from = 9, .to = 14 },
    .{ .from = 13, .to = 14 },
    .{ .from = 16, .to = 17 },
    .{ .from = 17, .to = 18 },
    .{ .from = 18, .to = 19 },
    .{ .from = 20, .to = 22 },
    .{ .from = 21, .to = 22 },
    .{ .from = 19, .to = 23 },
    .{ .from = 22, .to = 23 },
    .{ .from = 15, .to = 24 },
    .{ .from = 23, .to = 24 },
};

var generated_physical_instructions = [_]physical_ir.Instruction{
    .{ .eval_flow_node = 0 },
    .{ .eval_flow_node = 1 },
    .{ .record = .{ .dst = 2, .fields = &generated_physical_record_2_fields } },
    .{ .record = .{ .dst = 3, .fields = &generated_physical_record_3_fields } },
    .{ .eval_flow_node = 4 },
    .{ .record = .{ .dst = 5, .fields = &generated_physical_record_5_fields } },
    .{ .eval_flow_node = 6 },
    .{ .record = .{ .dst = 7, .fields = &generated_physical_record_7_fields } },
    .{ .record = .{ .dst = 8, .fields = &generated_physical_record_8_fields } },
    .{ .load_number = .{ .dst = 9, .value = 0 } },
    .{ .eval_flow_node = 10 },
    .{ .eval_flow_node = 11 },
    .{ .eval_flow_node = 12 },
    .{ .eval_flow_node = 13 },
    .{ .hold = .{ .dst = 14, .state_slot = 0, .initial = 9, .updates = &generated_physical_hold_14_updates } },
    .{ .load_number = .{ .dst = 15, .value = 0 } },
    .{ .eval_flow_node = 16 },
    .{ .eval_flow_node = 17 },
    .{ .eval_flow_node = 18 },
    .{ .eval_flow_node = 19 },
    .{ .load_state = .{ .dst = 20, .state_slot = 1 } },
    .{ .load_number = .{ .dst = 21, .value = 1 } },
    .{ .binary = .{ .dst = 22, .operator = .add, .lhs = 20, .rhs = 21 } },
    .{ .then_value = .{ .dst = 23, .source = 19, .value = 22 } },
    .{ .hold = .{ .dst = 24, .state_slot = 1, .initial = 15, .updates = &generated_physical_hold_24_updates } },
};

var generated_physical_program: physical_ir.PhysicalProgram = .{
    .arena = undefined,
    .source_slots = &generated_physical_source_slots,
    .value_slots = &generated_physical_value_slots,
    .state_slots = &generated_physical_state_slots,
    .instructions = &generated_physical_instructions,
    .dependency_edges = &generated_physical_dependency_edges,
    .branch_table = .{ .count = 0 },
    .list_table = .{ .count = 0 },
    .render_blueprint = .{ .node_count = 25 },
};

fn runGeneratedPhysicalRuntimeAdapter(allocator: std.mem.Allocator) ![]u8 {
    var runtime = try physical_runtime.Runtime.initAlloc(allocator, &generated_physical_program);
    defer runtime.deinit();
    try runtime.executeInitializers(&generated_physical_program);
    try runtime.plugSource(0, 1);
    const dispatch_result = try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 1,
        .scope_or_instance_id = 0,
        .payload = .{ .text = "Write tests" },
    });
    if (dispatch_result != .queued) return error.GeneratedRuntimeAdapterDispatchFailed;
    try runtime.processQueuedEvents(&generated_physical_program);
    return try runtime.stateSnapshotAlloc(allocator);
}

fn appSnapshotAlloc(allocator: std.mem.Allocator, app: *const AppState) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try app.writeSnapshot(&output.writer);
    return try output.toOwnedSlice();
}

fn assertGeneratedRuntimeAdapterMatchesApp(allocator: std.mem.Allocator, app: *const AppState) !void {
    const app_snapshot = try appSnapshotAlloc(allocator, app);
    defer allocator.free(app_snapshot);
    const runtime_snapshot = try runGeneratedPhysicalRuntimeAdapter(allocator);
    defer allocator.free(runtime_snapshot);
    if (!bytesEqual(app_snapshot, runtime_snapshot)) return error.GeneratedRuntimeAdapterMismatch;
}

fn bytesEqual(lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (left != right) return false;
    }
    return true;
}

const AppState = struct {
    state_0: RuntimeValue = .{ .number = 0 },
    state_1: RuntimeValue = .{ .number = 0 },

    fn dispatchEvent(self: *AppState, source_slot_id: u32, payload: RuntimeValue) void {
        switch (source_slot_id) {
            0 => self.state_0 = payload,
            1 => switch (self.state_1) {
                .number => |value| self.state_1 = .{ .number = value + 1 },
                else => self.state_1 = .{ .number = 1 },
            },
            else => {},
        }
    }

    fn writeSnapshot(self: *const AppState, writer: *std.Io.Writer) !void {
        try writer.writeAll("state[0]=");
        try writeRuntimeValue(writer, self.state_0);
        try writer.writeByte('\n');
        try writer.writeAll("state[1]=");
        try writeRuntimeValue(writer, self.state_1);
        try writer.writeByte('\n');
    }
};

fn writeRuntimeValue(writer: *std.Io.Writer, value: RuntimeValue) !void {
    switch (value) {
        .pulse => try writer.writeAll("pulse"),
        .number => |number| try writer.print("number:{d}", .{number}),
        .text => |text| try writer.print("text:{s}", .{text}),
    }
}
pub fn main(init: std.process.Init) !void {
    _ = source_slots;
    _ = semantic_source_map;
    _ = render_blueprint;
    _ = generated_runtime_plan;
    try validateGeneratedRuntimePlan();
    var app: AppState = .{};
    app.dispatchEvent(0, .{ .text = "Write tests" });
    try assertGeneratedRuntimeAdapterMatchesApp(std.heap.page_allocator, &app);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    try app.writeSnapshot(&stdout_writer.interface);
    try stdout_writer.interface.flush();
}
