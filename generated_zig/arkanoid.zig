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
    .{ .id = 0, .semantic_id = "sources.keyboard.event.key_down" },
    .{ .id = 1, .semantic_id = "sources.frame.event.tick" },
};

const semantic_source_map = [_]SourceMapEntry{
    .{ .semantic_id = "sources.keyboard.event.key_down", .source_path = "examples/source_physical/arkanoid/arkanoid.bn", .boon_start = 44, .boon_end = 50, .generated_start = 621, .generated_end = 689, .source_slot_id = 0 },
    .{ .semantic_id = "sources.frame.event.tick", .source_path = "examples/source_physical/arkanoid/arkanoid.bn", .boon_start = 79, .boon_end = 85, .generated_start = 689, .generated_end = 750, .source_slot_id = 1 },
};
const render_blueprint: RenderBlueprint = .{ .node_count = 23 };

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
const GeneratedRecord_1 = struct {
    key_down: RuntimeValue,
};

const GeneratedRecord_2 = struct {
    event: RuntimeValue,
};

const GeneratedRecord_4 = struct {
    tick: RuntimeValue,
};

const GeneratedRecord_5 = struct {
    event: RuntimeValue,
};

const GeneratedRecord_6 = struct {
    keyboard: RuntimeValue,
    frame: RuntimeValue,
};

const generated_record_1_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "key_down", .value_slot_id = 0 },
};

const generated_record_2_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "event", .value_slot_id = 1 },
};

const generated_record_4_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "tick", .value_slot_id = 3 },
};

const generated_record_5_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "event", .value_slot_id = 4 },
};

const generated_record_6_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "keyboard", .value_slot_id = 2 },
    .{ .name = "frame", .value_slot_id = 5 },
};

const generated_record_shapes = [_]GeneratedRecordShape{
    .{ .dst_slot_id = 1, .fields = &generated_record_1_fields },
    .{ .dst_slot_id = 2, .fields = &generated_record_2_fields },
    .{ .dst_slot_id = 4, .fields = &generated_record_4_fields },
    .{ .dst_slot_id = 5, .fields = &generated_record_5_fields },
    .{ .dst_slot_id = 6, .fields = &generated_record_6_fields },
};

const generated_list_shapes = [_]GeneratedListShape{
};

const generated_branch_activations = [_]GeneratedBranchActivation{
};

const generated_list_map_scopes = [_]GeneratedListMapScope{
};

const generated_dependency_edges = [_]GeneratedDependencyEdge{
    .{ .from = 0, .to = 1 },
    .{ .from = 1, .to = 2 },
    .{ .from = 3, .to = 4 },
    .{ .from = 4, .to = 5 },
    .{ .from = 2, .to = 6 },
    .{ .from = 5, .to = 6 },
    .{ .from = 8, .to = 9 },
    .{ .from = 9, .to = 10 },
    .{ .from = 10, .to = 11 },
    .{ .from = 7, .to = 12 },
    .{ .from = 11, .to = 12 },
    .{ .from = 14, .to = 15 },
    .{ .from = 15, .to = 16 },
    .{ .from = 16, .to = 17 },
    .{ .from = 18, .to = 20 },
    .{ .from = 19, .to = 20 },
    .{ .from = 17, .to = 21 },
    .{ .from = 20, .to = 21 },
    .{ .from = 13, .to = 22 },
    .{ .from = 21, .to = 22 },
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
    if (generated_runtime_plan.dependency_edges.len != 20) return error.GeneratedRuntimePlanMismatch;
    for (generated_runtime_plan.list_map_scopes) |scope| {
        if (scope.item_binding.len == 0) return error.GeneratedRuntimePlanMismatch;
    }
}

var generated_physical_record_1_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "key_down", .value = 0 },
};

var generated_physical_record_2_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "event", .value = 1 },
};

var generated_physical_record_4_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "tick", .value = 3 },
};

var generated_physical_record_5_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "event", .value = 4 },
};

var generated_physical_record_6_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "keyboard", .value = 2 },
    .{ .name = "frame", .value = 5 },
};

var generated_physical_hold_12_updates = [_]physical_ir.ValueSlotId{ 11, };

var generated_physical_hold_22_updates = [_]physical_ir.ValueSlotId{ 21, };

var generated_physical_source_slots = [_]physical_ir.SourceSlot{
    .{ .id = 0, .semantic_id = "sources.keyboard.event.key_down", .payload_type = "KeyEvent", .source_span = .{ .start = 44, .end = 50 }, .value_slot = 11 },
    .{ .id = 1, .semantic_id = "sources.frame.event.tick", .payload_type = "Pulse", .source_span = .{ .start = 79, .end = 85 }, .value_slot = 17 },
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
};

var generated_physical_state_slots = [_]physical_ir.StateSlot{
    .{ .id = 0, .semantic_id = "hold.paddle_input", .flow_node = 12 },
    .{ .id = 1, .semantic_id = "hold.frame_count", .flow_node = 22 },
};

var generated_physical_dependency_edges = [_]physical_ir.DependencyEdge{
    .{ .from = 0, .to = 1 },
    .{ .from = 1, .to = 2 },
    .{ .from = 3, .to = 4 },
    .{ .from = 4, .to = 5 },
    .{ .from = 2, .to = 6 },
    .{ .from = 5, .to = 6 },
    .{ .from = 8, .to = 9 },
    .{ .from = 9, .to = 10 },
    .{ .from = 10, .to = 11 },
    .{ .from = 7, .to = 12 },
    .{ .from = 11, .to = 12 },
    .{ .from = 14, .to = 15 },
    .{ .from = 15, .to = 16 },
    .{ .from = 16, .to = 17 },
    .{ .from = 18, .to = 20 },
    .{ .from = 19, .to = 20 },
    .{ .from = 17, .to = 21 },
    .{ .from = 20, .to = 21 },
    .{ .from = 13, .to = 22 },
    .{ .from = 21, .to = 22 },
};

var generated_physical_instructions = [_]physical_ir.Instruction{
    .{ .eval_flow_node = 0 },
    .{ .record = .{ .dst = 1, .fields = &generated_physical_record_1_fields } },
    .{ .record = .{ .dst = 2, .fields = &generated_physical_record_2_fields } },
    .{ .eval_flow_node = 3 },
    .{ .record = .{ .dst = 4, .fields = &generated_physical_record_4_fields } },
    .{ .record = .{ .dst = 5, .fields = &generated_physical_record_5_fields } },
    .{ .record = .{ .dst = 6, .fields = &generated_physical_record_6_fields } },
    .{ .load_number = .{ .dst = 7, .value = 0 } },
    .{ .eval_flow_node = 8 },
    .{ .eval_flow_node = 9 },
    .{ .eval_flow_node = 10 },
    .{ .eval_flow_node = 11 },
    .{ .hold = .{ .dst = 12, .state_slot = 0, .initial = 7, .updates = &generated_physical_hold_12_updates } },
    .{ .load_number = .{ .dst = 13, .value = 0 } },
    .{ .eval_flow_node = 14 },
    .{ .eval_flow_node = 15 },
    .{ .eval_flow_node = 16 },
    .{ .eval_flow_node = 17 },
    .{ .load_state = .{ .dst = 18, .state_slot = 1 } },
    .{ .load_number = .{ .dst = 19, .value = 1 } },
    .{ .binary = .{ .dst = 20, .operator = .add, .lhs = 18, .rhs = 19 } },
    .{ .then_value = .{ .dst = 21, .source = 17, .value = 20 } },
    .{ .hold = .{ .dst = 22, .state_slot = 1, .initial = 13, .updates = &generated_physical_hold_22_updates } },
};

var generated_physical_program: physical_ir.PhysicalProgram = .{
    .arena = undefined,
    .source_slots = &generated_physical_source_slots,
    .value_slots = &generated_physical_value_slots,
    .state_slots = &generated_physical_state_slots,
    .instructions = &generated_physical_instructions,
    .dependency_edges = &generated_physical_dependency_edges,
    .branch_table = .{.count = 0 },
    .list_table = .{.count = 0 },
    .render_blueprint = .{.node_count = 23 },
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
        .payload = .{ .text = "Left" },
    });
    if (dispatch_result != .queued) return error.GeneratedRuntimeAdapterDispatchFailed;
    try runtime.processQueuedEvents(&generated_physical_program);
    return try runtime.stateSnapshotAlloc(allocator);
}
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
    const snapshot = try runGeneratedPhysicalRuntimeAdapter(std.heap.page_allocator);
    defer std.heap.page_allocator.free(snapshot);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    try stdout_writer.interface.writeAll(snapshot);
    try stdout_writer.interface.flush();
}
