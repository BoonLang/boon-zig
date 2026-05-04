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
    .{ .id = 0, .semantic_id = "button.event.press" },
};

const semantic_source_map = [_]SourceMapEntry{
    .{ .semantic_id = "button.event.press", .source_path = "fixtures/physical_runtime/structured_runtime_plan.bn", .boon_start = 24, .boon_end = 30, .generated_start = 621, .generated_end = 676, .source_slot_id = 0 },
};
const render_blueprint: RenderBlueprint = .{ .node_count = 26 };

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

const GeneratedRecord_6 = struct {
    name: RuntimeValue,
    score: RuntimeValue,
};

const GeneratedList_9 = struct {
    items: []const RuntimeValue,
};

const GeneratedRecord_13 = struct {
    value: RuntimeValue,
};

const GeneratedListMapScope_14 = struct {
    item_id: u64,
    item_generation: u32,
    item: RuntimeValue,
};

const GeneratedRecord_21 = struct {
    name: RuntimeValue,
    score: RuntimeValue,
};

const GeneratedBranchState_25 = struct {
    active_arm_index: ?usize = null,
    input_slot_id: u32 = 24,
};

const generated_record_1_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "press", .value_slot_id = 0 },
};

const generated_record_2_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "event", .value_slot_id = 1 },
};

const generated_record_6_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "name", .value_slot_id = 4 },
    .{ .name = "score", .value_slot_id = 5 },
};

const generated_list_9_items = [_]u32{ 7, 8, };

const generated_record_13_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "value", .value_slot_id = 12 },
};

const generated_record_21_fields = [_]GeneratedRecordFieldSpec{
    .{ .name = "name", .value_slot_id = 19 },
    .{ .name = "score", .value_slot_id = 20 },
};

const generated_branch_25_arms = [_]GeneratedBranchArm{
    .{ .pattern_slot_id = 15, .result_slot_id = 16 },
    .{ .pattern_slot_id = 17, .result_slot_id = 21 },
};

const generated_record_shapes = [_]GeneratedRecordShape{
    .{ .dst_slot_id = 1, .fields = &generated_record_1_fields },
    .{ .dst_slot_id = 2, .fields = &generated_record_2_fields },
    .{ .dst_slot_id = 6, .fields = &generated_record_6_fields },
    .{ .dst_slot_id = 13, .fields = &generated_record_13_fields },
    .{ .dst_slot_id = 21, .fields = &generated_record_21_fields },
};

const generated_list_shapes = [_]GeneratedListShape{
    .{ .dst_slot_id = 9, .item_slots = &generated_list_9_items },
};

const generated_branch_activations = [_]GeneratedBranchActivation{
    .{ .dst_slot_id = 25, .input_slot_id = 24, .arms = &generated_branch_25_arms },
};

const generated_list_map_scopes = [_]GeneratedListMapScope{
    .{ .dst_slot_id = 14, .input_slot_id = 10, .body_slot_id = 13, .item_binding = "item" },
};

const generated_dependency_edges = [_]GeneratedDependencyEdge{
    .{ .from = 0, .to = 1 },
    .{ .from = 1, .to = 2 },
    .{ .from = 3, .to = 4 },
    .{ .from = 4, .to = 6 },
    .{ .from = 5, .to = 6 },
    .{ .from = 7, .to = 9 },
    .{ .from = 8, .to = 9 },
    .{ .from = 12, .to = 13 },
    .{ .from = 10, .to = 14 },
    .{ .from = 11, .to = 14 },
    .{ .from = 13, .to = 14 },
    .{ .from = 18, .to = 19 },
    .{ .from = 19, .to = 21 },
    .{ .from = 20, .to = 21 },
    .{ .from = 22, .to = 23 },
    .{ .from = 23, .to = 24 },
    .{ .from = 24, .to = 25 },
    .{ .from = 15, .to = 25 },
    .{ .from = 16, .to = 25 },
    .{ .from = 17, .to = 25 },
    .{ .from = 21, .to = 25 },
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
    if (generated_runtime_plan.list_shapes.len != 1) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.branch_activations.len != 1) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.list_map_scopes.len != 1) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.dependency_edges.len != 21) return error.GeneratedRuntimePlanMismatch;
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

var generated_physical_text_4_parts = [_]physical_ir.ValueSlotId{ 3, };

var generated_physical_record_6_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "name", .value = 4 },
    .{ .name = "score", .value = 5 },
};

var generated_physical_list_9_items = [_]physical_ir.ValueSlotId{ 7, 8, };

var generated_physical_record_13_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "value", .value = 12 },
};

var generated_physical_text_19_parts = [_]physical_ir.ValueSlotId{ 18, };

var generated_physical_record_21_fields = [_]physical_ir.RecordFieldInstruction{
    .{ .name = "name", .value = 19 },
    .{ .name = "score", .value = 20 },
};

var generated_physical_when_25_arms = [_]physical_ir.WhenArmInstruction{
    .{ .pattern = 15, .result = 16 },
    .{ .pattern = 17, .result = 21 },
};

var generated_physical_source_slots = [_]physical_ir.SourceSlot{
    .{ .id = 0, .semantic_id = "button.event.press", .payload_type = "Pulse", .source_span = .{ .start = 24, .end = 30 }, .value_slot = 24 },
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
    .{ .id = 25, .semantic_id = "flow.n25", .flow_node = 25 },
};

var generated_physical_state_slots = [_]physical_ir.StateSlot{
};

var generated_physical_dependency_edges = [_]physical_ir.DependencyEdge{
    .{ .from = 0, .to = 1 },
    .{ .from = 1, .to = 2 },
    .{ .from = 3, .to = 4 },
    .{ .from = 4, .to = 6 },
    .{ .from = 5, .to = 6 },
    .{ .from = 7, .to = 9 },
    .{ .from = 8, .to = 9 },
    .{ .from = 12, .to = 13 },
    .{ .from = 10, .to = 14 },
    .{ .from = 11, .to = 14 },
    .{ .from = 13, .to = 14 },
    .{ .from = 18, .to = 19 },
    .{ .from = 19, .to = 21 },
    .{ .from = 20, .to = 21 },
    .{ .from = 22, .to = 23 },
    .{ .from = 23, .to = 24 },
    .{ .from = 24, .to = 25 },
    .{ .from = 15, .to = 25 },
    .{ .from = 16, .to = 25 },
    .{ .from = 17, .to = 25 },
    .{ .from = 21, .to = 25 },
};

var generated_physical_instructions = [_]physical_ir.Instruction{
    .{ .eval_flow_node = 0 },
    .{ .record = .{ .dst = 1, .fields = &generated_physical_record_1_fields } },
    .{ .record = .{ .dst = 2, .fields = &generated_physical_record_2_fields } },
    .{ .load_atom = .{ .dst = 3, .text = "Ada" } },
    .{ .text = .{ .dst = 4, .parts = &generated_physical_text_4_parts } },
    .{ .load_number = .{ .dst = 5, .value = 7 } },
    .{ .record = .{ .dst = 6, .fields = &generated_physical_record_6_fields } },
    .{ .load_number = .{ .dst = 7, .value = 1 } },
    .{ .load_number = .{ .dst = 8, .value = 2 } },
    .{ .load_list = .{ .dst = 9, .items = &generated_physical_list_9_items } },
    .{ .eval_flow_node = 10 },
    .{ .eval_flow_node = 11 },
    .{ .load_mapped_item = .{ .dst = 12, .name = "item" } },
    .{ .record = .{ .dst = 13, .fields = &generated_physical_record_13_fields } },
    .{ .list_map = .{ .dst = 14, .input = 10, .body = 13 } },
    .{ .eval_flow_node = 15 },
    .{ .eval_flow_node = 16 },
    .{ .eval_flow_node = 17 },
    .{ .load_atom = .{ .dst = 18, .text = "None" } },
    .{ .text = .{ .dst = 19, .parts = &generated_physical_text_19_parts } },
    .{ .load_number = .{ .dst = 20, .value = 0 } },
    .{ .record = .{ .dst = 21, .fields = &generated_physical_record_21_fields } },
    .{ .eval_flow_node = 22 },
    .{ .eval_flow_node = 23 },
    .{ .eval_flow_node = 24 },
    .{ .when = .{ .dst = 25, .input = 24, .arms = &generated_physical_when_25_arms } },
};

var generated_physical_program: physical_ir.PhysicalProgram = .{
    .arena = undefined,
    .source_slots = &generated_physical_source_slots,
    .value_slots = &generated_physical_value_slots,
    .state_slots = &generated_physical_state_slots,
    .instructions = &generated_physical_instructions,
    .dependency_edges = &generated_physical_dependency_edges,
    .branch_table = .{.count = 0 },
    .list_table = .{.count = 1 },
    .render_blueprint = .{.node_count = 26 },
};

fn runGeneratedPhysicalRuntimeAdapter(allocator: std.mem.Allocator) ![]u8 {
    var runtime = try physical_runtime.Runtime.initAlloc(allocator, &generated_physical_program);
    defer runtime.deinit();
    try runtime.executeInitializers(&generated_physical_program);
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
