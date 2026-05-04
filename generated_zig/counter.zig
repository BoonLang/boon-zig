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
    .{ .id = 0, .semantic_id = "increment_button.event.press" },
};

const semantic_source_map = [_]SourceMapEntry{
    .{ .semantic_id = "increment_button.event.press", .source_path = "examples/source_physical/counter/counter.bn", .boon_start = 34, .boon_end = 40, .generated_start = 621, .generated_end = 686, .source_slot_id = 0 },
};
const render_blueprint: RenderBlueprint = .{ .node_count = 12 };

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
    press: RuntimeValue,
};

const GeneratedRecord_2 = struct {
    event: RuntimeValue,
};

const generated_record_1_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "press", .value_slot_id = 0 },
};

const generated_record_2_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "event", .value_slot_id = 1 },
};

const generated_record_shapes = [_]GeneratedRecordShape{
    .{ .dst_slot_id = 1, .fields = &generated_record_1_fields },
    .{ .dst_slot_id = 2, .fields = &generated_record_2_fields },
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
    .{ .from = 4, .to = 5 },
    .{ .from = 5, .to = 6 },
    .{ .from = 7, .to = 9 },
    .{ .from = 8, .to = 9 },
    .{ .from = 6, .to = 10 },
    .{ .from = 9, .to = 10 },
    .{ .from = 3, .to = 11 },
    .{ .from = 10, .to = 11 },
};

const generated_runtime_plan: GeneratedRuntimePlan = .{
    .record_shapes = &generated_record_shapes,
    .list_shapes = &generated_list_shapes,
    .branch_activations = &generated_branch_activations,
    .list_map_scopes = &generated_list_map_scopes,
    .dependency_edges = &generated_dependency_edges,
};
fn validateGeneratedRuntimePlan() !void {
    if (generated_runtime_plan.record_shapes.len != 2) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.list_shapes.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.branch_activations.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.list_map_scopes.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.dependency_edges.len != 10) return error.GeneratedRuntimePlanMismatch;
    for (generated_runtime_plan.list_map_scopes) |scope| {
        if (scope.item_binding.len == 0) return error.GeneratedRuntimePlanMismatch;
    }
}

var generated_physical_record_1_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "press", .value = 0 },
};

var generated_physical_record_2_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "event", .value = 1 },
};

var generated_physical_hold_11_updates = [_]physical_ir.ValueSlotId{ 10, };

var generated_physical_source_slots = [_]physical_ir.SourceSlot{
    .{ .id = 0, .semantic_id = "increment_button.event.press", .payload_type = "Pulse", .source_span = .{ .start = 34, .end = 40 }, .value_slot = 6 },
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
};

var generated_physical_state_slots = [_]physical_ir.StateSlot{
    .{ .id = 0, .semantic_id = "hold.counter", .flow_node = 11 },
};

var generated_physical_dependency_edges = [_]physical_ir.DependencyEdge{
    .{ .from = 0, .to = 1 },
    .{ .from = 1, .to = 2 },
    .{ .from = 4, .to = 5 },
    .{ .from = 5, .to = 6 },
    .{ .from = 7, .to = 9 },
    .{ .from = 8, .to = 9 },
    .{ .from = 6, .to = 10 },
    .{ .from = 9, .to = 10 },
    .{ .from = 3, .to = 11 },
    .{ .from = 10, .to = 11 },
};

var generated_physical_instructions = [_]physical_ir.Instruction{
    .{ .eval_flow_node = 0 },
    .{ .record = .{ .dst = 1, .fields = &generated_physical_record_1_fields } },
    .{ .record = .{ .dst = 2, .fields = &generated_physical_record_2_fields } },
    .{ .load_number = .{ .dst = 3, .value = 0 } },
    .{ .eval_flow_node = 4 },
    .{ .eval_flow_node = 5 },
    .{ .eval_flow_node = 6 },
    .{ .load_state = .{ .dst = 7, .state_slot = 0 } },
    .{ .load_number = .{ .dst = 8, .value = 1 } },
    .{ .binary = .{ .dst = 9, .operator = .add, .lhs = 7, .rhs = 8 } },
    .{ .then_value = .{ .dst = 10, .source = 6, .value = 9 } },
    .{ .hold = .{ .dst = 11, .state_slot = 0, .initial = 3, .updates = &generated_physical_hold_11_updates } },
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
    .render_blueprint = .{.node_count = 12 },
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
        .payload = .pulse,
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
