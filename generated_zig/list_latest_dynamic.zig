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

const source_slots = [_]SourceSlot{};

const semantic_source_map = [_]SourceMapEntry{};
const render_blueprint: RenderBlueprint = .{ .node_count = 6 };

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
const GeneratedList_2 = struct {
    items: []const RuntimeValue,
};

const generated_list_2_items = [_]u32{
    0,
    1,
};

const generated_record_shapes = [_]GeneratedRecordShape{};

const generated_list_shapes = [_]GeneratedListShape{
    .{ .dst_slot_id = 2, .item_slots = &generated_list_2_items },
};

const generated_branch_activations = [_]GeneratedBranchActivation{};

const generated_list_map_scopes = [_]GeneratedListMapScope{};

const generated_dependency_edges = [_]GeneratedDependencyEdge{
    .{ .from = 0, .to = 2 },
    .{ .from = 1, .to = 2 },
    .{ .from = 2, .to = 3 },
    .{ .from = 3, .to = 5 },
    .{ .from = 4, .to = 5 },
};

const generated_runtime_plan: GeneratedRuntimePlan = .{
    .record_shapes = &generated_record_shapes,
    .list_shapes = &generated_list_shapes,
    .branch_activations = &generated_branch_activations,
    .list_map_scopes = &generated_list_map_scopes,
    .dependency_edges = &generated_dependency_edges,
};
fn validateGeneratedRuntimePlan() !void {
    if (generated_runtime_plan.record_shapes.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.list_shapes.len != 1) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.branch_activations.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.list_map_scopes.len != 0) return error.GeneratedRuntimePlanMismatch;
    if (generated_runtime_plan.dependency_edges.len != 5) return error.GeneratedRuntimePlanMismatch;
    for (generated_runtime_plan.record_shapes) |shape| {
        if (shape.fields.len == 0) return error.GeneratedRuntimePlanMismatch;
    }
    for (generated_runtime_plan.list_map_scopes) |scope| {
        if (scope.item_binding.len == 0) return error.GeneratedRuntimePlanMismatch;
    }
}

var generated_physical_list_2_items = [_]physical_ir.ValueSlotId{
    0,
    1,
};

var generated_physical_hold_5_updates = [_]physical_ir.ValueSlotId{
    4,
};

var generated_physical_source_slots = [_]physical_ir.SourceSlot{};

var generated_physical_value_slots = [_]physical_ir.ValueSlot{
    .{ .id = 0, .semantic_id = "flow.n0", .flow_node = 0 },
    .{ .id = 1, .semantic_id = "flow.n1", .flow_node = 1 },
    .{ .id = 2, .semantic_id = "flow.n2", .flow_node = 2 },
    .{ .id = 3, .semantic_id = "flow.n3", .flow_node = 3 },
    .{ .id = 4, .semantic_id = "flow.n4", .flow_node = 4 },
    .{ .id = 5, .semantic_id = "flow.n5", .flow_node = 5 },
};

var generated_physical_state_slots = [_]physical_ir.StateSlot{
    .{ .id = 0, .semantic_id = "hold.latest", .flow_node = 5 },
};

var generated_physical_dependency_edges = [_]physical_ir.DependencyEdge{
    .{ .from = 0, .to = 2 },
    .{ .from = 1, .to = 2 },
    .{ .from = 2, .to = 3 },
    .{ .from = 3, .to = 5 },
    .{ .from = 4, .to = 5 },
};

var generated_physical_instructions = [_]physical_ir.Instruction{
    .{ .load_number = .{ .dst = 0, .value = 1 } },
    .{ .load_number = .{ .dst = 1, .value = 2 } },
    .{ .load_list = .{ .dst = 2, .items = &generated_physical_list_2_items } },
    .{ .list_latest = .{ .dst = 3, .input = 2 } },
    .{ .load_empty = 4 },
    .{ .hold = .{ .dst = 5, .state_slot = 0, .initial = 3, .updates = &generated_physical_hold_5_updates } },
};

var generated_physical_program: physical_ir.PhysicalProgram = .{
    .arena = undefined,
    .source_slots = &generated_physical_source_slots,
    .value_slots = &generated_physical_value_slots,
    .state_slots = &generated_physical_state_slots,
    .instructions = &generated_physical_instructions,
    .dependency_edges = &generated_physical_dependency_edges,
    .branch_table = .{ .count = 0 },
    .list_table = .{ .count = 1 },
    .render_blueprint = .{ .node_count = 6 },
};

fn runGeneratedPhysicalRuntimeAdapter(allocator: std.mem.Allocator) ![]u8 {
    var runtime = try physical_runtime.Runtime.initAlloc(allocator, &generated_physical_program);
    defer runtime.deinit();
    try runtime.executeInitializers(&generated_physical_program);
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
    state_0: RuntimeValue = .{ .number = 2 },

    fn dispatchEvent(self: *AppState, source_slot_id: u32, payload: RuntimeValue) void {
        _ = self;
        _ = source_slot_id;
        _ = payload;
    }

    fn writeSnapshot(self: *const AppState, writer: *std.Io.Writer) !void {
        try writer.writeAll("state[0]=");
        try writeRuntimeValue(writer, self.state_0);
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
const RuntimeValueTag = enum {
    pulse,
    number,
    text,
};

const GeneratedListItem = struct {
    id: u32,
    generation: u32,
    value: RuntimeValue,
};

const SourceSubscription = struct {
    item_id: u32,
    generation: u32,
    listener_slot_id: u32,
};

const FanInDelivery = struct {
    subscription: SourceSubscription,
    payload: RuntimeValue,
};

const GeneratedList = struct {
    items: []const GeneratedListItem,

    fn subscribe(self: *const GeneratedList, listener_slot_id: u32, item_id: u32) ?SourceSubscription {
        for (self.items) |item| {
            if (item.id == item_id) {
                return .{ .item_id = item.id, .generation = item.generation, .listener_slot_id = listener_slot_id };
            }
        }
        return null;
    }

    fn accepts(self: *const GeneratedList, subscription: SourceSubscription) bool {
        for (self.items) |item| {
            if (item.id == subscription.item_id) {
                return item.generation == subscription.generation;
            }
        }
        return false;
    }
};

const ListLatestFanIn = struct {
    latest: ?RuntimeValue = null,
    latest_tag: ?RuntimeValueTag = null,

    fn deliver(self: *ListLatestFanIn, list: *const GeneratedList, delivery: FanInDelivery) !?RuntimeValue {
        if (!list.accepts(delivery.subscription)) return null;
        const tag = runtimeValueTag(delivery.payload);
        if (self.latest_tag) |expected| {
            if (expected != tag) return error.PayloadShapeMismatch;
        }
        self.latest_tag = tag;
        self.latest = delivery.payload;
        return delivery.payload;
    }

    fn deliverDeterministic(
        self: *ListLatestFanIn,
        output: []RuntimeValue,
        list: *const GeneratedList,
        deliveries: []const FanInDelivery,
    ) ![]const RuntimeValue {
        var count: usize = 0;
        for (list.items) |item| {
            for (deliveries) |delivery| {
                if (delivery.subscription.item_id != item.id) continue;
                if (try self.deliver(list, delivery)) |value| {
                    output[count] = value;
                    count += 1;
                }
            }
        }
        return output[0..count];
    }
};

fn runtimeValueTag(value: RuntimeValue) RuntimeValueTag {
    return switch (value) {
        .pulse => .pulse,
        .number => .number,
        .text => .text,
    };
}

fn expectNumber(value: RuntimeValue, expected: f64) !void {
    switch (value) {
        .number => |actual| if (actual != expected) return error.UnexpectedListLatestValue,
        else => return error.UnexpectedListLatestValue,
    }
}

fn expectTextPrefix(value: RuntimeValue, first_byte: u8) !void {
    switch (value) {
        .text => |actual| if (actual.len == 0 or actual[0] != first_byte) return error.UnexpectedListLatestValue,
        else => return error.UnexpectedListLatestValue,
    }
}

fn runListLatestGeneratedSelfTests() !void {
    const empty_list: GeneratedList = .{ .items = &.{} };
    var empty_fan_in: ListLatestFanIn = .{};
    var empty_buffer: [1]RuntimeValue = undefined;
    const empty = try empty_fan_in.deliverDeterministic(&empty_buffer, &empty_list, &.{});
    if (empty.len != 0) return error.ExpectedEmptyListLatest;

    const ordered_items = [_]GeneratedListItem{
        .{ .id = 1, .generation = 0, .value = .{ .text = "first" } },
        .{ .id = 2, .generation = 0, .value = .{ .text = "second" } },
    };
    const ordered_list: GeneratedList = .{ .items = &ordered_items };
    var ordered_fan_in: ListLatestFanIn = .{};
    var ordered_buffer: [2]RuntimeValue = undefined;
    const ordered_deliveries = [_]FanInDelivery{
        .{ .subscription = ordered_list.subscribe(9, 2).?, .payload = .{ .number = 2 } },
        .{ .subscription = ordered_list.subscribe(9, 1).?, .payload = .{ .number = 1 } },
    };
    const ordered = try ordered_fan_in.deliverDeterministic(&ordered_buffer, &ordered_list, &ordered_deliveries);
    if (ordered.len != 2) return error.UnexpectedListLatestValue;
    try expectNumber(ordered[0], 1);
    try expectNumber(ordered[1], 2);

    const removed_subscription = ordered_list.subscribe(9, 1).?;
    const removed_items = [_]GeneratedListItem{ordered_items[1]};
    const removed_list: GeneratedList = .{ .items = &removed_items };
    var removed_fan_in: ListLatestFanIn = .{};
    if (try removed_fan_in.deliver(&removed_list, .{ .subscription = removed_subscription, .payload = .pulse }) != null) {
        return error.ExpectedRemovedListLatestEvent;
    }

    const reordered_items = [_]GeneratedListItem{ ordered_items[1], ordered_items[0] };
    const reordered_list: GeneratedList = .{ .items = &reordered_items };
    var reordered_fan_in: ListLatestFanIn = .{};
    var reordered_buffer: [2]RuntimeValue = undefined;
    const reordered_deliveries = [_]FanInDelivery{
        .{ .subscription = reordered_list.subscribe(9, 1).?, .payload = .{ .number = 1 } },
        .{ .subscription = reordered_list.subscribe(9, 2).?, .payload = .{ .number = 2 } },
    };
    const reordered = try reordered_fan_in.deliverDeterministic(&reordered_buffer, &reordered_list, &reordered_deliveries);
    if (reordered.len != 2) return error.UnexpectedListLatestValue;
    try expectNumber(reordered[0], 2);
    try expectNumber(reordered[1], 1);

    var mismatch_fan_in: ListLatestFanIn = .{};
    _ = try mismatch_fan_in.deliver(&ordered_list, .{
        .subscription = ordered_list.subscribe(9, 1).?,
        .payload = .{ .number = 1 },
    });
    var saw_payload_shape_mismatch = false;
    const mismatch_delivery = mismatch_fan_in.deliver(&ordered_list, .{
        .subscription = ordered_list.subscribe(9, 2).?,
        .payload = .{ .text = "bad" },
    }) catch |err| blk: {
        if (err != error.PayloadShapeMismatch) return err;
        saw_payload_shape_mismatch = true;
        break :blk null;
    };
    if (!saw_payload_shape_mismatch) return error.ExpectedPayloadShapeMismatch;
    if (mismatch_delivery != null) return error.ExpectedPayloadShapeMismatch;

    var todo_fan_in: ListLatestFanIn = .{};
    const todo_delivery = try todo_fan_in.deliver(&ordered_list, .{
        .subscription = ordered_list.subscribe(7, 1).?,
        .payload = .{ .text = "remove:todo-1" },
    }) orelse return error.UnexpectedListLatestValue;
    try expectTextPrefix(todo_delivery, 'r');
}
pub fn main(init: std.process.Init) !void {
    _ = source_slots;
    _ = semantic_source_map;
    _ = render_blueprint;
    _ = generated_runtime_plan;
    try validateGeneratedRuntimePlan();
    var app: AppState = .{};
    try runListLatestGeneratedSelfTests();
    try assertGeneratedRuntimeAdapterMatchesApp(std.heap.page_allocator, &app);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    try app.writeSnapshot(&stdout_writer.interface);
    try stdout_writer.interface.flush();
}
