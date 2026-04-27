const std = @import("std");
const ast = @import("ast.zig");
const physical_ir = @import("physical_ir.zig");

pub const BindingId = u64;
pub const ScopeOrInstanceId = u64;
pub const ListId = u64;
pub const ItemId = u64;
pub const MapSiteId = u64;
pub const TimerId = u64;
pub const RecordId = u64;

pub const RuntimeValue = union(enum) {
    empty,
    pulse,
    boolean: bool,
    number: f64,
    text: []const u8,
    list: ListId,
    record: RecordId,
};

pub const SourceState = union(enum) {
    unplugged,
    plugged: BindingId,
};

pub const SourceSlot = struct {
    semantic_id: physical_ir.SemanticId,
    physical_index: physical_ir.SourceSlotId,
    state: SourceState = .unplugged,
    payload_type: []const u8,
    value_slot: ?physical_ir.ValueSlotId = null,
};

pub const RuntimeEvent = struct {
    source_slot_id: physical_ir.SourceSlotId,
    binding_id_or_generation: BindingId,
    scope_or_instance_id: ScopeOrInstanceId,
    payload: RuntimeValue = .pulse,
};

pub const DispatchResult = enum {
    queued,
    stale,
    unplugged,
    invalid_slot,
};

pub const TypedSlotArray = struct {
    allocator: std.mem.Allocator,
    values: []RuntimeValue,
    dirty: []bool,

    pub fn initAlloc(allocator: std.mem.Allocator, count: usize) !TypedSlotArray {
        const values = try allocator.alloc(RuntimeValue, count);
        errdefer allocator.free(values);
        const dirty = try allocator.alloc(bool, count);
        for (values) |*value| value.* = .empty;
        @memset(dirty, false);
        return .{
            .allocator = allocator,
            .values = values,
            .dirty = dirty,
        };
    }

    pub fn deinit(self: *TypedSlotArray) void {
        self.allocator.free(self.values);
        self.allocator.free(self.dirty);
    }

    pub fn set(self: *TypedSlotArray, slot_id: physical_ir.PhysicalId, value: RuntimeValue) !void {
        const index: usize = slot_id;
        if (index >= self.values.len) return error.InvalidSlot;
        self.values[index] = value;
        self.dirty[index] = true;
    }

    pub fn get(self: *const TypedSlotArray, slot_id: physical_ir.PhysicalId) ?RuntimeValue {
        const index: usize = slot_id;
        if (index >= self.values.len) return null;
        return self.values[index];
    }

    pub fn isDirty(self: *const TypedSlotArray, slot_id: physical_ir.PhysicalId) bool {
        const index: usize = slot_id;
        return index < self.dirty.len and self.dirty[index];
    }

    pub fn clearDirty(self: *TypedSlotArray) void {
        @memset(self.dirty, false);
    }
};

pub const TraceEvent = struct {
    result: DispatchResult,
    source_slot_id: physical_ir.SourceSlotId,
    expected_binding: ?BindingId,
    actual_binding: BindingId,
};

pub const ListItem = struct {
    id: ItemId,
    generation: u64,
    value: RuntimeValue,
    source_subscription: ?ListSubscription = null,
};

pub const ListSubscription = struct {
    list_id: ListId,
    map_site_id: MapSiteId,
    item_id: ItemId,
    item_generation: u64,
};

pub const PayloadShape = enum {
    empty,
    pulse,
    boolean,
    number,
    text,
    list,
    record,
};

pub const FanInDelivery = struct {
    subscription: ListSubscription,
    payload: RuntimeValue,
};

pub const ListLatestFanIn = struct {
    expected_shape: ?PayloadShape = null,
    latest: ?RuntimeValue = null,

    pub fn deliver(self: *ListLatestFanIn, list: *const RuntimeList, delivery: FanInDelivery) !?RuntimeValue {
        if (!list.accepts(delivery.subscription)) return null;
        const shape = runtimeValueShape(delivery.payload);
        if (self.expected_shape) |expected| {
            if (expected != shape) return error.PayloadShapeMismatch;
        } else {
            self.expected_shape = shape;
        }
        self.latest = delivery.payload;
        return delivery.payload;
    }

    pub fn deliverDeterministic(
        self: *ListLatestFanIn,
        allocator: std.mem.Allocator,
        list: *const RuntimeList,
        deliveries: []const FanInDelivery,
    ) ![]RuntimeValue {
        var output: std.ArrayList(RuntimeValue) = .empty;
        errdefer output.deinit(allocator);

        for (list.items.items) |entry| {
            for (deliveries) |delivery| {
                if (delivery.subscription.item_id != entry.id) continue;
                if (try self.deliver(list, delivery)) |payload| {
                    try output.append(allocator, payload);
                }
            }
        }
        return try output.toOwnedSlice(allocator);
    }
};

fn runtimeValueShape(value: RuntimeValue) PayloadShape {
    return switch (value) {
        .empty => .empty,
        .pulse => .pulse,
        .boolean => .boolean,
        .number => .number,
        .text => .text,
        .list => .list,
        .record => .record,
    };
}

pub const RuntimeRecordField = struct {
    name: []const u8,
    value: RuntimeValue,
};

pub const RuntimeRecord = struct {
    allocator: std.mem.Allocator,
    id: RecordId,
    fields: []RuntimeRecordField,

    pub fn deinit(self: *RuntimeRecord) void {
        self.allocator.free(self.fields);
    }

    pub fn field(self: *const RuntimeRecord, name: []const u8) ?RuntimeValue {
        for (self.fields) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.value;
        }
        return null;
    }
};

pub const RuntimeList = struct {
    allocator: std.mem.Allocator,
    id: ListId,
    next_item_id: ItemId = 0,
    items: std.ArrayList(ListItem) = .empty,

    pub fn init(allocator: std.mem.Allocator, id: ListId) RuntimeList {
        return .{
            .allocator = allocator,
            .id = id,
        };
    }

    pub fn deinit(self: *RuntimeList) void {
        self.items.deinit(self.allocator);
    }

    pub fn append(self: *RuntimeList, value: RuntimeValue) !ItemId {
        return try self.appendWithSubscription(value, null);
    }

    pub fn appendWithSubscription(self: *RuntimeList, value: RuntimeValue, source_subscription: ?ListSubscription) !ItemId {
        const id = self.next_item_id;
        self.next_item_id += 1;
        try self.items.append(self.allocator, .{
            .id = id,
            .generation = 0,
            .value = value,
            .source_subscription = source_subscription,
        });
        return id;
    }

    pub fn remove(self: *RuntimeList, item_id: ItemId) bool {
        const index = self.indexOf(item_id) orelse return false;
        _ = self.items.orderedRemove(index);
        return true;
    }

    pub fn moveTo(self: *RuntimeList, item_id: ItemId, new_index: usize) bool {
        const old_index = self.indexOf(item_id) orelse return false;
        if (new_index >= self.items.items.len) return false;
        const moved_item = self.items.orderedRemove(old_index);
        self.items.insert(self.allocator, new_index, moved_item) catch unreachable;
        return true;
    }

    pub fn update(self: *RuntimeList, item_id: ItemId, value: RuntimeValue) bool {
        const index = self.indexOf(item_id) orelse return false;
        self.items.items[index].value = value;
        self.items.items[index].generation += 1;
        return true;
    }

    pub fn subscribe(self: *const RuntimeList, map_site_id: MapSiteId, item_id: ItemId) ?ListSubscription {
        const found_item = self.item(item_id) orelse return null;
        return .{
            .list_id = self.id,
            .map_site_id = map_site_id,
            .item_id = found_item.id,
            .item_generation = found_item.generation,
        };
    }

    pub fn accepts(self: *const RuntimeList, subscription: ListSubscription) bool {
        if (subscription.list_id != self.id) return false;
        const found_item = self.item(subscription.item_id) orelse return false;
        return found_item.generation == subscription.item_generation;
    }

    pub fn item(self: *const RuntimeList, item_id: ItemId) ?ListItem {
        const index = self.indexOf(item_id) orelse return null;
        return self.items.items[index];
    }

    fn indexOf(self: *const RuntimeList, item_id: ItemId) ?usize {
        for (self.items.items, 0..) |entry, index| {
            if (entry.id == item_id) return index;
        }
        return null;
    }
};

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    source_slots: []SourceSlot,
    value_slots: TypedSlotArray,
    state_slots: TypedSlotArray,
    lists: std.ArrayList(RuntimeList) = .empty,
    records: std.ArrayList(RuntimeRecord) = .empty,
    owned_texts: std.ArrayList([]u8) = .empty,
    event_queue: std.ArrayList(RuntimeEvent) = .empty,
    event_head: usize = 0,
    trace_events: std.ArrayList(TraceEvent) = .empty,

    pub fn initAlloc(allocator: std.mem.Allocator, program: *const physical_ir.PhysicalProgram) !Runtime {
        const source_slots = try allocator.alloc(SourceSlot, program.source_slots.len);
        errdefer allocator.free(source_slots);
        for (program.source_slots, 0..) |slot, index| {
            source_slots[index] = .{
                .semantic_id = slot.semantic_id,
                .physical_index = slot.id,
                .state = .unplugged,
                .payload_type = slot.payload_type,
                .value_slot = slot.value_slot,
            };
        }

        var value_slots = try TypedSlotArray.initAlloc(allocator, program.value_slots.len);
        errdefer value_slots.deinit();
        var state_slots = try TypedSlotArray.initAlloc(allocator, program.state_slots.len);
        errdefer state_slots.deinit();

        return .{
            .allocator = allocator,
            .source_slots = source_slots,
            .value_slots = value_slots,
            .state_slots = state_slots,
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.allocator.free(self.source_slots);
        self.value_slots.deinit();
        self.state_slots.deinit();
        for (self.lists.items) |*runtime_list| runtime_list.deinit();
        self.lists.deinit(self.allocator);
        for (self.records.items) |*runtime_record| runtime_record.deinit();
        self.records.deinit(self.allocator);
        for (self.owned_texts.items) |text| self.allocator.free(text);
        self.owned_texts.deinit(self.allocator);
        self.event_queue.deinit(self.allocator);
        self.trace_events.deinit(self.allocator);
    }

    pub fn plugSource(self: *Runtime, source_slot_id: physical_ir.SourceSlotId, binding_id: BindingId) !void {
        const slot = self.sourceSlot(source_slot_id) orelse return error.InvalidSourceSlot;
        slot.state = .{ .plugged = binding_id };
    }

    pub fn unplugSource(self: *Runtime, source_slot_id: physical_ir.SourceSlotId, binding_id: BindingId) bool {
        const slot = self.sourceSlot(source_slot_id) orelse return false;
        switch (slot.state) {
            .unplugged => return false,
            .plugged => |active_binding| {
                if (active_binding != binding_id) return false;
                slot.state = .unplugged;
                return true;
            },
        }
    }

    pub fn dispatchEvent(self: *Runtime, event: RuntimeEvent) !DispatchResult {
        const slot = self.sourceSlot(event.source_slot_id) orelse {
            try self.trace(.{
                .result = .invalid_slot,
                .source_slot_id = event.source_slot_id,
                .expected_binding = null,
                .actual_binding = event.binding_id_or_generation,
            });
            return .invalid_slot;
        };

        switch (slot.state) {
            .unplugged => {
                try self.trace(.{
                    .result = .unplugged,
                    .source_slot_id = event.source_slot_id,
                    .expected_binding = null,
                    .actual_binding = event.binding_id_or_generation,
                });
                return .unplugged;
            },
            .plugged => |active_binding| {
                if (active_binding != event.binding_id_or_generation) {
                    try self.trace(.{
                        .result = .stale,
                        .source_slot_id = event.source_slot_id,
                        .expected_binding = active_binding,
                        .actual_binding = event.binding_id_or_generation,
                    });
                    return .stale;
                }
            },
        }

        try self.event_queue.append(self.allocator, event);
        try self.trace(.{
            .result = .queued,
            .source_slot_id = event.source_slot_id,
            .expected_binding = event.binding_id_or_generation,
            .actual_binding = event.binding_id_or_generation,
        });
        return .queued;
    }

    pub fn popEvent(self: *Runtime) ?RuntimeEvent {
        if (self.event_head >= self.event_queue.items.len) return null;
        const event = self.event_queue.items[self.event_head];
        self.event_head += 1;
        if (self.event_head == self.event_queue.items.len) self.clearEventQueue();
        return event;
    }

    pub fn executeInitializers(self: *Runtime, program: *const physical_ir.PhysicalProgram) !void {
        for (program.instructions) |instruction| {
            switch (instruction) {
                .noop, .eval_flow_node => {},
                .load_empty => |dst| try self.value_slots.set(dst, .empty),
                .load_number => |load| try self.value_slots.set(load.dst, .{ .number = load.value }),
                .load_atom => |load| try self.value_slots.set(load.dst, atomValue(load.text)),
                .load_list => |load| try self.value_slots.set(load.dst, try self.createListFromSlots(load.items)),
                .text => |text| try self.value_slots.set(text.dst, try self.executeText(text)),
                .load_state => |load| try self.value_slots.set(load.dst, self.state_slots.get(load.state_slot) orelse .empty),
                .load_mapped_item => {},
                .record => |record_instruction| try self.value_slots.set(record_instruction.dst, try self.createRecordFromFields(record_instruction.fields)),
                .binary => |binary| if (evalBinary(
                    binary.operator,
                    self.value_slots.get(binary.lhs) orelse .empty,
                    self.value_slots.get(binary.rhs) orelse .empty,
                )) |value| try self.value_slots.set(binary.dst, value),
                .when => |when| if (evalWhen(&self.value_slots, when)) |value| try self.value_slots.set(when.dst, value),
                .block => |block| try self.value_slots.set(block.dst, self.value_slots.get(block.result) orelse .empty),
                .list_map => |map| try self.value_slots.set(map.dst, try self.executeListMap(program, map)),
                .list_latest => |latest| try self.value_slots.set(latest.dst, try self.executeListLatest(latest)),
                .then_value => {},
                .latest => |latest| {
                    if (latest.initial) |initial| {
                        if (self.value_slots.get(initial)) |value| try self.value_slots.set(latest.dst, value);
                    }
                },
                .hold => |hold| {
                    const initial = self.value_slots.get(hold.initial) orelse .empty;
                    try self.state_slots.set(hold.state_slot, initial);
                    try self.value_slots.set(hold.dst, initial);
                },
            }
        }
    }

    pub fn processQueuedEvents(self: *Runtime, program: *const physical_ir.PhysicalProgram) !void {
        while (self.popEvent()) |event| {
            self.value_slots.clearDirty();
            const slot_index: usize = event.source_slot_id;
            if (slot_index >= self.source_slots.len) continue;
            const value_slot = self.source_slots[slot_index].value_slot orelse continue;
            try self.value_slots.set(value_slot, event.payload);
            try self.executeReactivePass(program);
        }
    }

    fn executeReactivePass(self: *Runtime, program: *const physical_ir.PhysicalProgram) !void {
        for (program.instructions) |instruction| {
            switch (instruction) {
                .noop, .load_number, .load_atom, .load_list, .load_empty, .load_mapped_item, .text, .eval_flow_node => {},
                .load_state => |load| try self.value_slots.set(load.dst, self.state_slots.get(load.state_slot) orelse .empty),
                .record => |record_instruction| try self.value_slots.set(record_instruction.dst, try self.createRecordFromFields(record_instruction.fields)),
                .binary => |binary| if (evalBinary(
                    binary.operator,
                    self.value_slots.get(binary.lhs) orelse .empty,
                    self.value_slots.get(binary.rhs) orelse .empty,
                )) |value| try self.value_slots.set(binary.dst, value),
                .when => |when| if (evalWhen(&self.value_slots, when)) |value| try self.value_slots.set(when.dst, value),
                .block => |block| try self.value_slots.set(block.dst, self.value_slots.get(block.result) orelse .empty),
                .list_map => |map| try self.value_slots.set(map.dst, try self.executeListMap(program, map)),
                .list_latest => |latest| try self.value_slots.set(latest.dst, try self.executeListLatest(latest)),
                .then_value => |then_value| {
                    if (!self.value_slots.isDirty(then_value.source)) continue;
                    const value = self.value_slots.get(then_value.value) orelse .empty;
                    try self.value_slots.set(then_value.dst, value);
                },
                .latest => |latest| {
                    for (latest.sources) |source| {
                        if (!self.value_slots.isDirty(source)) continue;
                        const value = self.value_slots.get(source) orelse .empty;
                        try self.value_slots.set(latest.dst, value);
                        break;
                    }
                },
                .hold => |hold| {
                    for (hold.updates) |update| {
                        if (!self.value_slots.isDirty(update)) continue;
                        const value = self.value_slots.get(update) orelse .empty;
                        try self.state_slots.set(hold.state_slot, value);
                        try self.value_slots.set(hold.dst, value);
                        break;
                    }
                },
            }
        }
    }

    fn createListFromSlots(self: *Runtime, slots: []const physical_ir.ValueSlotId) !RuntimeValue {
        const list_id: ListId = @intCast(self.lists.items.len);
        var runtime_list = RuntimeList.init(self.allocator, list_id);
        errdefer runtime_list.deinit();
        for (slots) |slot_id| {
            _ = try runtime_list.append(self.value_slots.get(slot_id) orelse .empty);
        }
        try self.lists.append(self.allocator, runtime_list);
        return .{ .list = list_id };
    }

    fn executeText(self: *Runtime, instruction: physical_ir.TextInstruction) !RuntimeValue {
        var output: std.Io.Writer.Allocating = .init(self.allocator);
        defer output.deinit();

        const writer = &output.writer;
        for (instruction.parts) |part| {
            try writeRuntimeValueAsText(writer, self.value_slots.get(part) orelse .empty);
        }
        const text = try output.toOwnedSlice();
        errdefer self.allocator.free(text);
        try self.owned_texts.append(self.allocator, text);
        return .{ .text = text };
    }

    fn createRecordFromFields(self: *Runtime, fields: []const physical_ir.RecordFieldInstruction) !RuntimeValue {
        const record_id: RecordId = @intCast(self.records.items.len);
        const copied = try self.allocator.alloc(RuntimeRecordField, fields.len);
        errdefer self.allocator.free(copied);
        for (fields, 0..) |field, index| {
            copied[index] = .{
                .name = field.name,
                .value = self.value_slots.get(field.value) orelse .empty,
            };
        }
        try self.records.append(self.allocator, .{
            .allocator = self.allocator,
            .id = record_id,
            .fields = copied,
        });
        return .{ .record = record_id };
    }

    fn createListFromValues(self: *Runtime, values: []const RuntimeValue) !RuntimeValue {
        const list_id: ListId = @intCast(self.lists.items.len);
        var runtime_list = RuntimeList.init(self.allocator, list_id);
        errdefer runtime_list.deinit();
        for (values) |value| {
            _ = try runtime_list.append(value);
        }
        try self.lists.append(self.allocator, runtime_list);
        return .{ .list = list_id };
    }

    fn createListFromMappedValues(self: *Runtime, values: []const RuntimeValue, subscriptions: []const ListSubscription) !RuntimeValue {
        std.debug.assert(values.len == subscriptions.len);
        const list_id: ListId = @intCast(self.lists.items.len);
        var runtime_list = RuntimeList.init(self.allocator, list_id);
        errdefer runtime_list.deinit();
        for (values, 0..) |value, index| {
            const item_id = try runtime_list.appendWithSubscription(value, null);
            runtime_list.items.items[runtime_list.items.items.len - 1].source_subscription = runtime_list.subscribe(subscriptions[index].map_site_id, item_id);
        }
        try self.lists.append(self.allocator, runtime_list);
        return .{ .list = list_id };
    }

    fn executeListMap(self: *Runtime, program: *const physical_ir.PhysicalProgram, instruction: physical_ir.ListMapInstruction) !RuntimeValue {
        const input_value = self.value_slots.get(instruction.input) orelse return .empty;
        if (input_value != .list) return .empty;
        const input = self.list(input_value.list) orelse return .empty;

        var mapped: std.ArrayList(RuntimeValue) = .empty;
        defer mapped.deinit(self.allocator);
        var subscriptions: std.ArrayList(ListSubscription) = .empty;
        defer subscriptions.deinit(self.allocator);
        for (input.items.items) |entry| {
            const value = if (instruction.body) |body|
                try self.evalSlotWithMappedItem(program, body, entry.value)
            else
                entry.value;
            try mapped.append(self.allocator, value);
            try subscriptions.append(self.allocator, input.subscribe(instruction.dst, entry.id).?);
        }
        return try self.createListFromMappedValues(mapped.items, subscriptions.items);
    }

    fn evalSlotWithMappedItem(
        self: *Runtime,
        program: *const physical_ir.PhysicalProgram,
        slot_id: physical_ir.ValueSlotId,
        item_value: RuntimeValue,
    ) anyerror!RuntimeValue {
        const index: usize = slot_id;
        if (index >= program.instructions.len) return .empty;
        return switch (program.instructions[index]) {
            .load_empty => .empty,
            .load_number => |load| .{ .number = load.value },
            .load_atom => |load| atomValue(load.text),
            .load_mapped_item => item_value,
            .load_state => |load| self.state_slots.get(load.state_slot) orelse .empty,
            .binary => |binary| evalBinary(
                binary.operator,
                try self.evalSlotWithMappedItem(program, binary.lhs, item_value),
                try self.evalSlotWithMappedItem(program, binary.rhs, item_value),
            ) orelse .empty,
            .text => |text| try self.evalTextWithMappedItem(program, text, item_value),
            .block => |block| try self.evalSlotWithMappedItem(program, block.result, item_value),
            .when => |when| try self.evalWhenWithMappedItem(program, when, item_value),
            .record => |record_instruction| try self.evalRecordWithMappedItem(program, record_instruction, item_value),
            else => self.value_slots.get(slot_id) orelse .empty,
        };
    }

    fn evalTextWithMappedItem(
        self: *Runtime,
        program: *const physical_ir.PhysicalProgram,
        instruction: physical_ir.TextInstruction,
        item_value: RuntimeValue,
    ) anyerror!RuntimeValue {
        var output: std.Io.Writer.Allocating = .init(self.allocator);
        defer output.deinit();

        const writer = &output.writer;
        for (instruction.parts) |part| {
            try writeRuntimeValueAsText(writer, try self.evalSlotWithMappedItem(program, part, item_value));
        }
        const text = try output.toOwnedSlice();
        errdefer self.allocator.free(text);
        try self.owned_texts.append(self.allocator, text);
        return .{ .text = text };
    }

    fn evalWhenWithMappedItem(
        self: *Runtime,
        program: *const physical_ir.PhysicalProgram,
        instruction: physical_ir.WhenInstruction,
        item_value: RuntimeValue,
    ) anyerror!RuntimeValue {
        const input = try self.evalSlotWithMappedItem(program, instruction.input, item_value);
        for (instruction.arms) |arm| {
            const pattern = try self.evalSlotWithMappedItem(program, arm.pattern, item_value);
            if (isWildcard(pattern) or runtimeValueEql(input, pattern)) {
                return try self.evalSlotWithMappedItem(program, arm.result, item_value);
            }
        }
        return .empty;
    }

    fn evalRecordWithMappedItem(
        self: *Runtime,
        program: *const physical_ir.PhysicalProgram,
        instruction: physical_ir.RecordInstruction,
        item_value: RuntimeValue,
    ) anyerror!RuntimeValue {
        const record_id: RecordId = @intCast(self.records.items.len);
        const copied = try self.allocator.alloc(RuntimeRecordField, instruction.fields.len);
        errdefer self.allocator.free(copied);
        for (instruction.fields, 0..) |field, index| {
            copied[index] = .{
                .name = field.name,
                .value = try self.evalSlotWithMappedItem(program, field.value, item_value),
            };
        }
        try self.records.append(self.allocator, .{
            .allocator = self.allocator,
            .id = record_id,
            .fields = copied,
        });
        return .{ .record = record_id };
    }

    fn executeListLatest(self: *Runtime, instruction: physical_ir.ListLatestInstruction) !RuntimeValue {
        const input_value = self.value_slots.get(instruction.input) orelse return .empty;
        if (input_value != .list) return .empty;
        const input = self.list(input_value.list) orelse return .empty;

        var fan_in: ListLatestFanIn = .{};
        var deliveries: std.ArrayList(FanInDelivery) = .empty;
        defer deliveries.deinit(self.allocator);
        for (input.items.items) |entry| {
            try deliveries.append(self.allocator, .{
                .subscription = entry.source_subscription orelse input.subscribe(instruction.dst, entry.id).?,
                .payload = entry.value,
            });
        }
        const emitted = try fan_in.deliverDeterministic(self.allocator, input, deliveries.items);
        defer self.allocator.free(emitted);
        if (emitted.len == 0) return .empty;
        return emitted[emitted.len - 1];
    }

    pub fn list(self: *Runtime, list_id: ListId) ?*RuntimeList {
        const index: usize = @intCast(list_id);
        if (index >= self.lists.items.len) return null;
        return &self.lists.items[index];
    }

    pub fn record(self: *Runtime, record_id: RecordId) ?*RuntimeRecord {
        const index: usize = @intCast(record_id);
        if (index >= self.records.items.len) return null;
        return &self.records.items[index];
    }

    pub fn queuedEventCount(self: *const Runtime) usize {
        return self.event_queue.items.len - self.event_head;
    }

    fn clearEventQueue(self: *Runtime) void {
        self.event_queue.clearRetainingCapacity();
        self.event_head = 0;
    }

    fn sourceSlot(self: *Runtime, source_slot_id: physical_ir.SourceSlotId) ?*SourceSlot {
        const index: usize = source_slot_id;
        if (index >= self.source_slots.len) return null;
        return &self.source_slots[index];
    }

    fn trace(self: *Runtime, event: TraceEvent) !void {
        try self.trace_events.append(self.allocator, event);
    }

    pub fn traceAlloc(self: *const Runtime, allocator: std.mem.Allocator) ![]u8 {
        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();

        const writer = &output.writer;
        for (self.trace_events.items) |event| {
            try writer.print("dispatch source={d} result={s} expected=", .{
                event.source_slot_id,
                dispatchResultName(event.result),
            });
            if (event.expected_binding) |binding| {
                try writer.print("{d}", .{binding});
            } else {
                try writer.writeAll("none");
            }
            try writer.print(" actual={d}\n", .{event.actual_binding});
        }
        return try output.toOwnedSlice();
    }

    pub fn stateSnapshotAlloc(self: *const Runtime, allocator: std.mem.Allocator) ![]u8 {
        var output: std.Io.Writer.Allocating = .init(allocator);
        defer output.deinit();

        const writer = &output.writer;
        for (self.state_slots.values, 0..) |value, index| {
            try writer.print("state[{d}]=", .{index});
            try writeRuntimeValue(writer, value);
            try writer.writeByte('\n');
        }
        return try output.toOwnedSlice();
    }

    pub fn restoreStateSnapshot(self: *Runtime, snapshot: []const u8) !void {
        var lines = std.mem.splitScalar(u8, snapshot, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (!std.mem.startsWith(u8, line, "state[")) return error.InvalidStateSnapshot;
            const close_index = std.mem.indexOfScalar(u8, line, ']') orelse return error.InvalidStateSnapshot;
            const slot_id = try std.fmt.parseInt(physical_ir.StateSlotId, line["state[".len..close_index], 10);
            if (close_index + 1 >= line.len or line[close_index + 1] != '=') return error.InvalidStateSnapshot;
            const value = try parseRuntimeValue(line[close_index + 2 ..]);
            try self.state_slots.set(slot_id, try self.ownRestoredValue(value));
        }
    }

    fn ownRestoredValue(self: *Runtime, value: RuntimeValue) !RuntimeValue {
        return switch (value) {
            .text => |text| blk: {
                const owned = try self.allocator.dupe(u8, text);
                errdefer self.allocator.free(owned);
                try self.owned_texts.append(self.allocator, owned);
                break :blk .{ .text = owned };
            },
            else => value,
        };
    }
};

pub const VirtualTimer = struct {
    id: TimerId,
    source_slot_id: physical_ir.SourceSlotId,
    binding_id: BindingId,
    scope_or_instance_id: ScopeOrInstanceId,
    period_ms: u64,
    next_due_ms: u64,
};

pub const VirtualClock = struct {
    allocator: std.mem.Allocator,
    now_ms: u64 = 0,
    next_timer_id: TimerId = 0,
    timers: std.ArrayList(VirtualTimer) = .empty,

    pub fn init(allocator: std.mem.Allocator) VirtualClock {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *VirtualClock) void {
        self.timers.deinit(self.allocator);
    }

    pub fn addInterval(
        self: *VirtualClock,
        source_slot_id: physical_ir.SourceSlotId,
        binding_id: BindingId,
        scope_or_instance_id: ScopeOrInstanceId,
        period_ms: u64,
    ) !TimerId {
        const id = self.next_timer_id;
        self.next_timer_id += 1;
        try self.timers.append(self.allocator, .{
            .id = id,
            .source_slot_id = source_slot_id,
            .binding_id = binding_id,
            .scope_or_instance_id = scope_or_instance_id,
            .period_ms = period_ms,
            .next_due_ms = self.now_ms + period_ms,
        });
        return id;
    }

    pub fn advance(self: *VirtualClock, runtime: *Runtime, delta_ms: u64) !usize {
        self.now_ms += delta_ms;
        var emitted: usize = 0;
        for (self.timers.items) |*timer| {
            while (timer.next_due_ms <= self.now_ms) {
                const result = try runtime.dispatchEvent(.{
                    .source_slot_id = timer.source_slot_id,
                    .binding_id_or_generation = timer.binding_id,
                    .scope_or_instance_id = timer.scope_or_instance_id,
                    .payload = .pulse,
                });
                if (result == .queued) emitted += 1;
                timer.next_due_ms += timer.period_ms;
            }
        }
        return emitted;
    }
};

fn dispatchResultName(result: DispatchResult) []const u8 {
    return switch (result) {
        .queued => "queued",
        .stale => "stale",
        .unplugged => "unplugged",
        .invalid_slot => "invalid_slot",
    };
}

fn writeRuntimeValue(writer: *std.Io.Writer, value: RuntimeValue) !void {
    switch (value) {
        .empty => try writer.writeAll("empty"),
        .pulse => try writer.writeAll("pulse"),
        .boolean => |boolean| try writer.print("bool:{s}", .{if (boolean) "true" else "false"}),
        .number => |number| try writer.print("number:{d}", .{number}),
        .text => |text| try writer.print("text:{s}", .{text}),
        .list => |list_id| try writer.print("list:{d}", .{list_id}),
        .record => |record_id| try writer.print("record:{d}", .{record_id}),
    }
}

fn writeRuntimeValueAsText(writer: *std.Io.Writer, value: RuntimeValue) !void {
    switch (value) {
        .empty => {},
        .pulse => try writer.writeAll("pulse"),
        .boolean => |boolean| try writer.writeAll(if (boolean) "True" else "False"),
        .number => |number| try writer.print("{d}", .{number}),
        .text => |text| try writer.writeAll(text),
        .list => |list_id| try writer.print("<list:{d}>", .{list_id}),
        .record => |record_id| try writer.print("<record:{d}>", .{record_id}),
    }
}

pub fn parseRuntimeValue(serialized: []const u8) !RuntimeValue {
    if (std.mem.eql(u8, serialized, "empty")) return .empty;
    if (std.mem.eql(u8, serialized, "pulse")) return .pulse;
    if (std.mem.eql(u8, serialized, "bool:true")) return .{ .boolean = true };
    if (std.mem.eql(u8, serialized, "bool:false")) return .{ .boolean = false };
    if (std.mem.startsWith(u8, serialized, "number:")) {
        return .{ .number = try std.fmt.parseFloat(f64, serialized["number:".len..]) };
    }
    if (std.mem.startsWith(u8, serialized, "text:")) return .{ .text = serialized["text:".len..] };
    if (std.mem.startsWith(u8, serialized, "list:")) {
        return .{ .list = try std.fmt.parseInt(ListId, serialized["list:".len..], 10) };
    }
    if (std.mem.startsWith(u8, serialized, "record:")) {
        return .{ .record = try std.fmt.parseInt(RecordId, serialized["record:".len..], 10) };
    }
    return error.InvalidRuntimeValue;
}

fn atomValue(text: []const u8) RuntimeValue {
    if (std.mem.eql(u8, text, "True")) return .{ .boolean = true };
    if (std.mem.eql(u8, text, "False")) return .{ .boolean = false };
    if (std.mem.eql(u8, text, "SKIP")) return .empty;
    return .{ .text = text };
}

fn evalBinary(operator: ast.BinaryOp, lhs: RuntimeValue, rhs: RuntimeValue) ?RuntimeValue {
    return switch (operator) {
        .add => numericBinary(lhs, rhs, struct {
            fn apply(a: f64, b: f64) f64 {
                return a + b;
            }
        }.apply),
        .subtract => numericBinary(lhs, rhs, struct {
            fn apply(a: f64, b: f64) f64 {
                return a - b;
            }
        }.apply),
        .multiply => numericBinary(lhs, rhs, struct {
            fn apply(a: f64, b: f64) f64 {
                return a * b;
            }
        }.apply),
        .divide => numericBinary(lhs, rhs, struct {
            fn apply(a: f64, b: f64) f64 {
                return a / b;
            }
        }.apply),
        .equal => .{ .boolean = runtimeValueEql(lhs, rhs) },
        .not_equal => .{ .boolean = !runtimeValueEql(lhs, rhs) },
        else => null,
    };
}

fn numericBinary(lhs: RuntimeValue, rhs: RuntimeValue, comptime op: fn (f64, f64) f64) ?RuntimeValue {
    if (lhs != .number or rhs != .number) return null;
    return .{ .number = op(lhs.number, rhs.number) };
}

fn runtimeValueEql(lhs: RuntimeValue, rhs: RuntimeValue) bool {
    if (@as(std.meta.Tag(RuntimeValue), lhs) != @as(std.meta.Tag(RuntimeValue), rhs)) return false;
    return switch (lhs) {
        .empty, .pulse => true,
        .boolean => |value| value == rhs.boolean,
        .number => |value| value == rhs.number,
        .text => |value| std.mem.eql(u8, value, rhs.text),
        .list => |value| value == rhs.list,
        .record => |value| value == rhs.record,
    };
}

fn evalWhen(values: *const TypedSlotArray, instruction: physical_ir.WhenInstruction) ?RuntimeValue {
    const input = values.get(instruction.input) orelse .empty;
    for (instruction.arms) |arm| {
        const pattern = values.get(arm.pattern) orelse .empty;
        if (isWildcard(pattern) or runtimeValueEql(input, pattern)) {
            return values.get(arm.result) orelse .empty;
        }
    }
    return null;
}

fn isWildcard(value: RuntimeValue) bool {
    return value == .text and std.mem.eql(u8, value.text, "__");
}

test "Physical runtime initializes typed slots from Physical IR" {
    const source =
        \\button: [event: [press: SOURCE] hovered: SOURCE]
        \\counter: 0
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();

    try std.testing.expectEqual(@as(usize, 2), runtime.source_slots.len);
    try std.testing.expectEqual(program.value_slots.len, runtime.value_slots.values.len);
    try std.testing.expectEqual(program.state_slots.len, runtime.state_slots.values.len);
    try std.testing.expectEqual(SourceState.unplugged, runtime.source_slots[0].state);
    try std.testing.expectEqualStrings("button.event.press", runtime.source_slots[0].semantic_id);
}

test "Physical runtime maps source slots to Flow value slots" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\value: button.event.press |> THEN { 1 }
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR source slot mapping failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.source_slots.len);
    try std.testing.expect(program.source_slots[0].value_slot != null);
}

test "Physical runtime queues only events matching active source binding" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();

    try std.testing.expectEqual(DispatchResult.unplugged, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 99,
        .scope_or_instance_id = 17,
    }));
    try std.testing.expectEqual(@as(usize, 0), runtime.queuedEventCount());

    try runtime.plugSource(0, 99);
    try std.testing.expectEqual(DispatchResult.stale, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 98,
        .scope_or_instance_id = 17,
    }));
    try std.testing.expectEqual(@as(usize, 0), runtime.queuedEventCount());

    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 99,
        .scope_or_instance_id = 17,
        .payload = .{ .number = 1 },
    }));
    try std.testing.expectEqual(@as(usize, 1), runtime.queuedEventCount());
    const event = runtime.popEvent().?;
    try std.testing.expectEqual(@as(physical_ir.SourceSlotId, 0), event.source_slot_id);
    try std.testing.expectEqual(@as(BindingId, 99), event.binding_id_or_generation);
    try std.testing.expectEqual(@as(usize, 0), runtime.queuedEventCount());
}

test "Physical runtime ignores events after source generation changes" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();

    try runtime.plugSource(0, 7);
    try std.testing.expect(!runtime.unplugSource(0, 8));
    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 7,
        .scope_or_instance_id = 1,
    }));
    _ = runtime.popEvent();

    try std.testing.expect(runtime.unplugSource(0, 7));
    try runtime.plugSource(0, 8);
    try std.testing.expectEqual(DispatchResult.stale, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 7,
        .scope_or_instance_id = 1,
    }));
    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 8,
        .scope_or_instance_id = 1,
    }));
}

test "Physical runtime typed slot arrays track dirty values" {
    var slots = try TypedSlotArray.initAlloc(std.testing.allocator, 2);
    defer slots.deinit();

    try std.testing.expectEqual(RuntimeValue.empty, slots.get(0).?);
    try std.testing.expect(!slots.isDirty(0));
    try slots.set(0, .{ .boolean = true });
    try std.testing.expect(slots.isDirty(0));
    try std.testing.expectEqual(RuntimeValue{ .boolean = true }, slots.get(0).?);
    slots.clearDirty();
    try std.testing.expect(!slots.isDirty(0));
    try std.testing.expectEqual(@as(?RuntimeValue, null), slots.get(99));
}

test "Physical runtime executes concrete constant instructions into typed slots" {
    const source =
        \\answer: 41
        \\enabled: True
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime fixture failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_number = false;
    var saw_bool = false;
    for (runtime.value_slots.values, 0..) |value, index| {
        if (!runtime.value_slots.dirty[index]) continue;
        switch (value) {
            .number => |number| {
                if (number == 41) saw_number = true;
            },
            .boolean => |boolean| {
                if (boolean) saw_bool = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_number);
    try std.testing.expect(saw_bool);
}

test "Physical runtime initializes latest from initial value" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\value: LATEST {
        \\    5
        \\    button.event.press |> THEN { 1 }
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime latest failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_latest = false;
    for (runtime.value_slots.values, 0..) |value, index| {
        if (!runtime.value_slots.dirty[index]) continue;
        switch (value) {
            .number => |number| {
                if (number == 5) saw_latest = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_latest);
}

test "Physical runtime initializes HOLD state slot from initial value" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\counter: 0 |> HOLD counter {
        \\    button.event.press |> THEN { counter + 1 }
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime hold failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 1), program.state_slots.len);
    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    try std.testing.expect(runtime.state_slots.isDirty(0));
    try std.testing.expectEqual(RuntimeValue{ .number = 0 }, runtime.state_slots.get(0).?);
}

test "Physical runtime processes THEN event into value slot" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\value: button.event.press |> THEN { 1 }
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime then failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);
    try runtime.plugSource(0, 1);
    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 1,
        .scope_or_instance_id = 10,
        .payload = .pulse,
    }));
    try runtime.processQueuedEvents(&program);

    var saw_then = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .then_value => |then_value| {
                try std.testing.expectEqual(RuntimeValue{ .number = 1 }, runtime.value_slots.get(then_value.dst).?);
                saw_then = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_then);
}

test "Physical runtime processes canonical counter-style HOLD update" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\counter: 0 |> HOLD counter {
        \\    button.event.press |> THEN { counter + 1 }
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime counter failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);
    try std.testing.expectEqual(RuntimeValue{ .number = 0 }, runtime.state_slots.get(0).?);

    try runtime.plugSource(0, 42);
    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 42,
        .scope_or_instance_id = 10,
        .payload = .pulse,
    }));
    try runtime.processQueuedEvents(&program);

    try std.testing.expectEqual(RuntimeValue{ .number = 1 }, runtime.state_slots.get(0).?);

    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 42,
        .scope_or_instance_id = 10,
        .payload = .pulse,
    }));
    try runtime.processQueuedEvents(&program);

    try std.testing.expectEqual(RuntimeValue{ .number = 2 }, runtime.state_slots.get(0).?);
}

test "Physical runtime executes WHEN and SKIP value forms" {
    const source =
        \\selected: True |> WHEN {
        \\    True => 1
        \\    False => SKIP
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime WHEN failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_when = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .when => |when| {
                try std.testing.expectEqual(RuntimeValue{ .number = 1 }, runtime.value_slots.get(when.dst).?);
                saw_when = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_when);
}

test "Physical runtime executes BLOCK result value" {
    const source =
        \\value: BLOCK {
        \\    one: 1
        \\    one + 2
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime BLOCK failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_block = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .block => |block| {
                try std.testing.expectEqual(RuntimeValue{ .number = 3 }, runtime.value_slots.get(block.dst).?);
                saw_block = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_block);
}

test "Physical runtime executes LIST instruction into RuntimeList" {
    const source =
        \\items: LIST { 1 2 }
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime LIST failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_list = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .load_list => |load| {
                const value = runtime.value_slots.get(load.dst).?;
                try std.testing.expect(value == .list);
                const runtime_list = runtime.list(value.list).?;
                try std.testing.expectEqual(@as(usize, 2), runtime_list.items.items.len);
                try std.testing.expectEqual(RuntimeValue{ .number = 1 }, runtime_list.items.items[0].value);
                try std.testing.expectEqual(RuntimeValue{ .number = 2 }, runtime_list.items.items[1].value);
                saw_list = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_list);
}

test "Physical runtime executes List/map identity instruction" {
    const source =
        \\items: LIST { 1 2 }
        \\mapped: items |> List/map(item, new: item)
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime List/map failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_map = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .list_map => |map| {
                const value = runtime.value_slots.get(map.dst).?;
                try std.testing.expect(value == .list);
                const runtime_list = runtime.list(value.list).?;
                try std.testing.expectEqual(@as(usize, 2), runtime_list.items.items.len);
                try std.testing.expectEqual(RuntimeValue{ .number = 1 }, runtime_list.items.items[0].value);
                try std.testing.expectEqual(RuntimeValue{ .number = 2 }, runtime_list.items.items[1].value);
                saw_map = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_map);
}

test "Physical runtime executes List/map mapped item expression" {
    const source =
        \\items: LIST { 1 2 }
        \\mapped: items |> List/map(item, new: item + 1)
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime mapped item failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_map = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .list_map => |map| {
                const value = runtime.value_slots.get(map.dst).?;
                try std.testing.expect(value == .list);
                const runtime_list = runtime.list(value.list).?;
                try std.testing.expectEqual(@as(usize, 2), runtime_list.items.items.len);
                try std.testing.expectEqual(RuntimeValue{ .number = 2 }, runtime_list.items.items[0].value);
                try std.testing.expectEqual(RuntimeValue{ .number = 3 }, runtime_list.items.items[1].value);
                try std.testing.expect(runtime_list.items.items[0].source_subscription != null);
                try std.testing.expect(runtime_list.accepts(runtime_list.items.items[0].source_subscription.?));
                saw_map = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_map);
}

test "Physical runtime executes List/latest instruction from mapped list" {
    const source =
        \\items: LIST { 1 2 }
        \\mapped: items |> List/map(item, new: item)
        \\latest: mapped |> List/latest()
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime List/latest failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_latest = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .list_latest => |latest| {
                try std.testing.expectEqual(RuntimeValue{ .number = 2 }, runtime.value_slots.get(latest.dst).?);
                saw_latest = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_latest);
}

test "Physical runtime executes record instruction" {
    const source =
        \\person: [name: TEXT { Ada } score: 7]
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime record failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_record = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .record => |record_instruction| {
                const value = runtime.value_slots.get(record_instruction.dst).?;
                try std.testing.expect(value == .record);
                const runtime_record = runtime.record(value.record).?;
                try std.testing.expectEqualStrings("Ada", runtime_record.field("name").?.text);
                try std.testing.expectEqual(RuntimeValue{ .number = 7 }, runtime_record.field("score").?);
                saw_record = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_record);
}

test "Physical runtime executes TEXT instruction with interpolation" {
    const source =
        \\value: 7
        \\label: TEXT { Value: {value} }
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime TEXT failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_text = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .text => |text| {
                try std.testing.expectEqualStrings("Value: 7", runtime.value_slots.get(text.dst).?.text);
                saw_text = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_text);
}

test "Physical runtime executes WHILE wildcard fallback" {
    const source =
        \\selected: Maybe |> WHILE {
        \\    True => 1
        \\    __ => 2
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime WHILE failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);

    var saw_while = false;
    for (program.instructions) |instruction| {
        switch (instruction) {
            .when => |when| {
                try std.testing.expectEqual(RuntimeValue{ .number = 2 }, runtime.value_slots.get(when.dst).?);
                saw_while = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_while);
}

test "Physical runtime list identity keeps duplicate equal values distinct" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();

    const first = try list.append(.{ .number = 7 });
    const second = try list.append(.{ .number = 7 });

    try std.testing.expect(first != second);
    try std.testing.expectEqual(RuntimeValue{ .number = 7 }, list.item(first).?.value);
    try std.testing.expectEqual(RuntimeValue{ .number = 7 }, list.item(second).?.value);
}

test "Physical runtime list reorder preserves item scope subscription" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();

    const first = try list.append(.{ .text = "first" });
    const second = try list.append(.{ .text = "second" });
    const subscription = list.subscribe(9, first).?;

    try std.testing.expect(list.moveTo(first, 1));
    try std.testing.expectEqual(second, list.items.items[0].id);
    try std.testing.expectEqual(first, list.items.items[1].id);
    try std.testing.expect(list.accepts(subscription));
}

test "Physical runtime list fan-in rejects removed and stale child events" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();

    const item_id = try list.append(.{ .number = 1 });
    const subscription = list.subscribe(12, item_id).?;
    try std.testing.expect(list.accepts(subscription));

    try std.testing.expect(list.update(item_id, .{ .number = 2 }));
    try std.testing.expect(!list.accepts(subscription));

    const updated_subscription = list.subscribe(12, item_id).?;
    try std.testing.expect(list.accepts(updated_subscription));
    try std.testing.expect(list.remove(item_id));
    try std.testing.expect(!list.accepts(updated_subscription));
}

test "list_latest_empty_emits_nothing" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    var fan_in: ListLatestFanIn = .{};

    const emitted = try fan_in.deliverDeterministic(std.testing.allocator, &list, &.{});
    defer std.testing.allocator.free(emitted);
    try std.testing.expectEqual(@as(usize, 0), emitted.len);
}

test "list_latest_single_child_forwards_payload" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    const item_id = try list.append(.{ .text = "child" });
    var fan_in: ListLatestFanIn = .{};

    const forwarded = try fan_in.deliver(&list, .{
        .subscription = list.subscribe(1, item_id).?,
        .payload = .{ .number = 42 },
    });
    try std.testing.expectEqual(RuntimeValue{ .number = 42 }, forwarded.?);
    try std.testing.expectEqual(RuntimeValue{ .number = 42 }, fan_in.latest.?);
}

test "list_latest_multiple_children_deterministic_order" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    const first = try list.append(.{ .text = "first" });
    const second = try list.append(.{ .text = "second" });
    var fan_in: ListLatestFanIn = .{};

    const deliveries = [_]FanInDelivery{
        .{ .subscription = list.subscribe(1, second).?, .payload = .{ .number = 2 } },
        .{ .subscription = list.subscribe(1, first).?, .payload = .{ .number = 1 } },
    };
    const emitted = try fan_in.deliverDeterministic(std.testing.allocator, &list, &deliveries);
    defer std.testing.allocator.free(emitted);
    try std.testing.expectEqual(@as(usize, 2), emitted.len);
    try std.testing.expectEqual(RuntimeValue{ .number = 1 }, emitted[0]);
    try std.testing.expectEqual(RuntimeValue{ .number = 2 }, emitted[1]);
}

test "list_latest_removed_child_stale_event_ignored" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    const item_id = try list.append(.{ .text = "child" });
    const subscription = list.subscribe(1, item_id).?;
    try std.testing.expect(list.remove(item_id));
    var fan_in: ListLatestFanIn = .{};

    const forwarded = try fan_in.deliver(&list, .{
        .subscription = subscription,
        .payload = .pulse,
    });
    try std.testing.expectEqual(@as(?RuntimeValue, null), forwarded);
}

test "list_latest_reordered_child_preserves_state" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    const first = try list.append(.{ .text = "first" });
    const second = try list.append(.{ .text = "second" });
    const subscription = list.subscribe(1, first).?;
    try std.testing.expect(list.moveTo(first, 1));
    var fan_in: ListLatestFanIn = .{};

    const deliveries = [_]FanInDelivery{
        .{ .subscription = list.subscribe(1, second).?, .payload = .{ .number = 2 } },
        .{ .subscription = subscription, .payload = .{ .number = 1 } },
    };
    const emitted = try fan_in.deliverDeterministic(std.testing.allocator, &list, &deliveries);
    defer std.testing.allocator.free(emitted);
    try std.testing.expectEqual(RuntimeValue{ .number = 2 }, emitted[0]);
    try std.testing.expectEqual(RuntimeValue{ .number = 1 }, emitted[1]);
}

test "list_latest_payload_shape_mismatch_diagnostic" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    const first = try list.append(.{ .text = "first" });
    const second = try list.append(.{ .text = "second" });
    var fan_in: ListLatestFanIn = .{};

    _ = try fan_in.deliver(&list, .{
        .subscription = list.subscribe(1, first).?,
        .payload = .{ .number = 1 },
    });
    try std.testing.expectError(error.PayloadShapeMismatch, fan_in.deliver(&list, .{
        .subscription = list.subscribe(1, second).?,
        .payload = .{ .text = "bad" },
    }));
}

test "list_latest_with_todo_remove_payload" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    const todo_id = try list.append(.{ .text = "todo-1" });
    var fan_in: ListLatestFanIn = .{};

    const forwarded = try fan_in.deliver(&list, .{
        .subscription = list.subscribe(7, todo_id).?,
        .payload = .{ .text = "remove:todo-1" },
    });
    try std.testing.expectEqualStrings("remove:todo-1", forwarded.?.text);
}

test "list_latest_cells_dynamic_fan_in_regression" {
    var list = RuntimeList.init(std.testing.allocator, 1);
    defer list.deinit();
    const cell_a = try list.append(.{ .text = "A1" });
    const cell_b = try list.append(.{ .text = "B1" });
    const stale_a = list.subscribe(99, cell_a).?;
    try std.testing.expect(list.remove(cell_a));
    var fan_in: ListLatestFanIn = .{};

    const ignored = try fan_in.deliver(&list, .{
        .subscription = stale_a,
        .payload = .{ .number = 10 },
    });
    try std.testing.expectEqual(@as(?RuntimeValue, null), ignored);

    const forwarded = try fan_in.deliver(&list, .{
        .subscription = list.subscribe(99, cell_b).?,
        .payload = .{ .number = 20 },
    });
    try std.testing.expectEqual(RuntimeValue{ .number = 20 }, forwarded.?);
}

test "Physical runtime virtual clock emits deterministic interval events" {
    const source =
        \\tick: SOURCE
        \\count: 0 |> HOLD count {
        \\    tick |> THEN { count + 1 }
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime virtual-time failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);
    try runtime.plugSource(0, 3);

    var clock = VirtualClock.init(std.testing.allocator);
    defer clock.deinit();
    _ = try clock.addInterval(0, 3, 1, 100);

    try std.testing.expectEqual(@as(usize, 0), try clock.advance(&runtime, 99));
    try runtime.processQueuedEvents(&program);
    try std.testing.expectEqual(RuntimeValue{ .number = 0 }, runtime.state_slots.get(0).?);

    try std.testing.expectEqual(@as(usize, 2), try clock.advance(&runtime, 101));
    try runtime.processQueuedEvents(&program);
    try std.testing.expectEqual(RuntimeValue{ .number = 2 }, runtime.state_slots.get(0).?);
}

test "Physical runtime trace and state snapshot are deterministic" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\counter: 0 |> HOLD counter {
        \\    button.event.press |> THEN { counter + 1 }
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime snapshot failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);
    try runtime.plugSource(0, 5);
    try std.testing.expectEqual(DispatchResult.stale, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 4,
        .scope_or_instance_id = 1,
    }));
    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 5,
        .scope_or_instance_id = 1,
    }));
    try runtime.processQueuedEvents(&program);

    const trace = try runtime.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expectEqualStrings(
        \\dispatch source=0 result=stale expected=5 actual=4
        \\dispatch source=0 result=queued expected=5 actual=5
        \\
    , trace);

    const snapshot = try runtime.stateSnapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expectEqualStrings(
        \\state[0]=number:1
        \\
    , snapshot);
}

test "Physical runtime restores deterministic state snapshot" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\counter: 0 |> HOLD counter {
        \\    button.event.press |> THEN { counter + 1 }
        \\}
        \\
    ;
    const outcome = try physical_ir.lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR runtime restore failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    var runtime = try Runtime.initAlloc(std.testing.allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);
    try runtime.restoreStateSnapshot(
        \\state[0]=number:41
        \\
    );

    try std.testing.expectEqual(RuntimeValue{ .number = 41 }, runtime.state_slots.get(0).?);
    try runtime.plugSource(0, 8);
    try std.testing.expectEqual(DispatchResult.queued, try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 8,
        .scope_or_instance_id = 1,
    }));
    try runtime.processQueuedEvents(&program);
    try std.testing.expectEqual(RuntimeValue{ .number = 42 }, runtime.state_slots.get(0).?);
}
