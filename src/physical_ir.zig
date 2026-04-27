const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const flow_ir = @import("flow_ir.zig");
const host_schema = @import("host_schema.zig");
const parser = @import("parser.zig");
const source_shape = @import("source_shape.zig");

pub const PhysicalId = u32;
pub const SemanticId = []const u8;
pub const SourceSlotId = PhysicalId;
pub const StateSlotId = PhysicalId;
pub const ValueSlotId = PhysicalId;

pub const PhysicalSlot = union(enum) {
    source: SourceSlot,
    state: StateSlot,
    value: ValueSlot,
};

pub const SourceSlot = struct {
    id: SourceSlotId,
    semantic_id: SemanticId,
    payload_type: []const u8,
    source_span: ast.Span,
    value_slot: ?ValueSlotId = null,
};

pub const StateSlot = struct {
    id: StateSlotId,
    semantic_id: SemanticId,
    flow_node: flow_ir.NodeId,
};

pub const ValueSlot = struct {
    id: ValueSlotId,
    semantic_id: SemanticId,
    flow_node: flow_ir.NodeId,
};

pub const LoadNumber = struct {
    dst: ValueSlotId,
    value: f64,
};

pub const LoadAtom = struct {
    dst: ValueSlotId,
    text: []const u8,
};

pub const ThenInstruction = struct {
    dst: ValueSlotId,
    source: ValueSlotId,
    value: ValueSlotId,
};

pub const LatestInstruction = struct {
    dst: ValueSlotId,
    initial: ?ValueSlotId,
    sources: []ValueSlotId,
};

pub const HoldInstruction = struct {
    dst: ValueSlotId,
    state_slot: StateSlotId,
    initial: ValueSlotId,
    updates: []ValueSlotId,
};

pub const LoadState = struct {
    dst: ValueSlotId,
    state_slot: StateSlotId,
};

pub const LoadMappedItem = struct {
    dst: ValueSlotId,
    name: []const u8,
};

pub const BinaryInstruction = struct {
    dst: ValueSlotId,
    operator: ast.BinaryOp,
    lhs: ValueSlotId,
    rhs: ValueSlotId,
};

pub const WhenArmInstruction = struct {
    pattern: ValueSlotId,
    result: ValueSlotId,
};

pub const WhenInstruction = struct {
    dst: ValueSlotId,
    input: ValueSlotId,
    arms: []WhenArmInstruction,
};

pub const BlockInstruction = struct {
    dst: ValueSlotId,
    result: ValueSlotId,
};

pub const RecordFieldInstruction = struct {
    name: []const u8,
    value: ValueSlotId,
};

pub const RecordInstruction = struct {
    dst: ValueSlotId,
    fields: []RecordFieldInstruction,
};

pub const LoadList = struct {
    dst: ValueSlotId,
    items: []ValueSlotId,
};

pub const TextInstruction = struct {
    dst: ValueSlotId,
    parts: []ValueSlotId,
};

pub const ListMapInstruction = struct {
    dst: ValueSlotId,
    input: ValueSlotId,
    body: ?ValueSlotId,
};

pub const ListLatestInstruction = struct {
    dst: ValueSlotId,
    input: ValueSlotId,
};

pub const Instruction = union(enum) {
    noop,
    load_empty: ValueSlotId,
    load_number: LoadNumber,
    load_atom: LoadAtom,
    load_list: LoadList,
    text: TextInstruction,
    load_state: LoadState,
    load_mapped_item: LoadMappedItem,
    record: RecordInstruction,
    binary: BinaryInstruction,
    when: WhenInstruction,
    block: BlockInstruction,
    list_map: ListMapInstruction,
    list_latest: ListLatestInstruction,
    then_value: ThenInstruction,
    latest: LatestInstruction,
    hold: HoldInstruction,
    eval_flow_node: ValueSlotId,
};

pub const DependencyEdge = struct {
    from: PhysicalId,
    to: PhysicalId,
};

pub const BranchTable = struct {
    count: usize = 0,
};

pub const ListTable = struct {
    count: usize = 0,
};

pub const RenderBlueprint = struct {
    node_count: usize = 0,
};

pub const PhysicalProgram = struct {
    arena: std.heap.ArenaAllocator,
    source_slots: []SourceSlot,
    value_slots: []ValueSlot,
    state_slots: []StateSlot,
    instructions: []Instruction,
    dependency_edges: []DependencyEdge,
    branch_table: BranchTable,
    list_table: ListTable,
    render_blueprint: RenderBlueprint,

    pub fn deinit(self: *PhysicalProgram) void {
        self.arena.deinit();
    }
};

pub const Outcome = union(enum) {
    ok: PhysicalProgram,
    err: diag.Diagnostic,
};

const PhysicalFlow = struct {
    nodes: []const flow_ir.Node,
    bindings: []const flow_ir.Binding,
};

pub fn lowerAlloc(allocator: std.mem.Allocator, source: []const u8) !Outcome {
    return lowerAllocWithOptions(allocator, source, .{});
}

pub fn lowerAllocWithOptions(allocator: std.mem.Allocator, source: []const u8, options: parser.Options) !Outcome {
    _ = options;
    const parsed = try parser.parseAlloc(allocator, source);
    var ast_document = switch (parsed) {
        .ok => |document| document,
        .err => |failure| return .{ .err = failure },
    };
    defer ast_document.deinit();

    const frozen = try source_shape.freezeAlloc(allocator, source, &ast_document);
    var shape = switch (frozen) {
        .ok => |shape| shape,
        .err => |failure| return .{ .err = failure },
    };
    defer shape.deinit();

    const lowered_flow = try flow_ir.lowerAlloc(allocator, source);
    var flow = switch (lowered_flow) {
        .ok => |document| document,
        .err => |failure| return .{ .err = failure },
    };
    defer flow.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const physical_flow = try physicalFlowForRuntimeAlloc(a, &flow);
    if (validateNoRuntimeSpecials(physical_flow)) |failure| return .{ .err = failure };

    if (validateSourceFields(allocator, shape.fields)) |failure| return .{ .err = failure };

    const source_slots = try a.alloc(SourceSlot, shape.fields.len);
    for (shape.fields, 0..) |field, index| {
        source_slots[index] = .{
            .id = @intCast(index),
            .semantic_id = try a.dupe(u8, field.path),
            .payload_type = host_schema.inferSourcePayload(field.path).label(),
            .source_span = field.span,
            .value_slot = sourceValueSlotForPath(physical_flow, field.path),
        };
    }

    const value_slots = try a.alloc(ValueSlot, physical_flow.nodes.len);
    for (physical_flow.nodes, 0..) |_, index| {
        value_slots[index] = .{
            .id = @intCast(index),
            .semantic_id = try std.fmt.allocPrint(a, "flow.n{d}", .{index}),
            .flow_node = @intCast(index),
        };
    }

    const state_slots = try lowerStateSlots(a, physical_flow);

    var dependency_edges: std.ArrayList(DependencyEdge) = .empty;
    defer dependency_edges.deinit(a);
    for (physical_flow.nodes, 0..) |node, index| {
        try appendNodeDependencies(a, &dependency_edges, @intCast(index), node);
    }

    const instructions = try a.alloc(Instruction, physical_flow.nodes.len);
    for (instructions, physical_flow.nodes, 0..) |*instruction, node, index| {
        instruction.* = try selectInstruction(a, node, @intCast(index), state_slots);
    }

    return .{ .ok = .{
        .arena = arena,
        .source_slots = source_slots,
        .value_slots = value_slots,
        .state_slots = state_slots,
        .instructions = instructions,
        .dependency_edges = try dependency_edges.toOwnedSlice(a),
        .branch_table = .{},
        .list_table = .{ .count = countListNodes(physical_flow) },
        .render_blueprint = .{ .node_count = physical_flow.nodes.len },
    } };
}

fn selectInstruction(allocator: std.mem.Allocator, node: flow_ir.Node, dst: ValueSlotId, state_slots: []const StateSlot) !Instruction {
    return switch (node.kind) {
        .number => |number| .{ .load_number = .{ .dst = dst, .value = number.value } },
        .atom => |text| .{ .load_atom = .{ .dst = dst, .text = try allocator.dupe(u8, text) } },
        .list => |list| .{ .load_list = .{
            .dst = dst,
            .items = try copyNodeIds(allocator, list.items),
        } },
        .text => |parts| .{ .text = .{
            .dst = dst,
            .parts = try copyNodeIds(allocator, parts),
        } },
        .local_ref => |name| if (stateSlotForLocalRef(state_slots, name)) |local_state_slot| .{
            .load_state = .{ .dst = dst, .state_slot = local_state_slot },
        } else .{ .load_mapped_item = .{
            .dst = dst,
            .name = try allocator.dupe(u8, name),
        } },
        .record => |fields| .{ .record = .{
            .dst = dst,
            .fields = try copyRecordFields(allocator, fields),
        } },
        .binary => |binary| .{ .binary = .{
            .dst = dst,
            .operator = binary.operator,
            .lhs = binary.lhs,
            .rhs = binary.rhs,
        } },
        .special => |special| switch (special) {
            .skip_ref => .{ .load_empty = dst },
            else => .{ .eval_flow_node = dst },
        },
        .when => |when| .{ .when = .{
            .dst = dst,
            .input = when.input,
            .arms = try copyWhenArms(allocator, when.arms),
        } },
        .block => |block| .{ .block = .{ .dst = dst, .result = block.result } },
        .builtin_call => |call| try selectBuiltinInstruction(call, dst),
        .then_value => |then_value| .{ .then_value = .{
            .dst = dst,
            .source = then_value.source,
            .value = then_value.value,
        } },
        .latest => |latest| .{ .latest = .{
            .dst = dst,
            .initial = latest.initial,
            .sources = try copyNodeIds(allocator, latest.sources),
        } },
        .hold => |hold| .{ .hold = .{
            .dst = dst,
            .state_slot = stateSlotForFlowNode(state_slots, dst) orelse 0,
            .initial = hold.initial,
            .updates = try copyNodeIds(allocator, hold.updates),
        } },
        else => .{ .eval_flow_node = dst },
    };
}

const NormalizeBinding = struct {
    name: []const u8,
    value: flow_ir.NodeId,
};

const NormalizeScope = struct {
    parent: ?*const NormalizeScope = null,
    bindings: []const NormalizeBinding = &.{},
    pass_context: ?flow_ir.NodeId = null,

    fn lookup(self: *const NormalizeScope, name: []const u8) ?flow_ir.NodeId {
        var current: ?*const NormalizeScope = self;
        while (current) |scope| {
            for (scope.bindings) |binding| {
                if (std.mem.eql(u8, binding.name, name)) return binding.value;
            }
            current = scope.parent;
        }
        return null;
    }

    fn passed(self: *const NormalizeScope) ?flow_ir.NodeId {
        var current: ?*const NormalizeScope = self;
        while (current) |scope| {
            if (scope.pass_context) |pass_context| return pass_context;
            current = scope.parent;
        }
        return null;
    }
};

const PassNormalizer = struct {
    allocator: std.mem.Allocator,
    flow: *const flow_ir.Document,
    nodes: std.ArrayList(flow_ir.Node) = .empty,

    fn deinit(self: *PassNormalizer) void {
        self.nodes.deinit(self.allocator);
    }

    fn normalizeBindings(self: *PassNormalizer) anyerror![]flow_ir.Binding {
        const bindings = try self.allocator.alloc(flow_ir.Binding, self.flow.bindings.len);
        for (self.flow.bindings, 0..) |binding, index| {
            bindings[index] = .{
                .name = binding.name,
                .node = try self.normalizeNode(binding.node, null),
                .span = binding.span,
            };
        }
        return bindings;
    }

    fn normalizeNode(self: *PassNormalizer, node_id: flow_ir.NodeId, scope: ?*const NormalizeScope) anyerror!flow_ir.NodeId {
        const index: usize = node_id;
        if (index >= self.flow.nodes.len) return error.InvalidFlowNode;
        const node = self.flow.nodes[index];
        return switch (node.kind) {
            .number, .atom, .symbol, .link_port, .binding_ref => try self.append(node.span, node.kind),
            .local_ref => |name| if (scope) |active_scope|
                active_scope.lookup(name) orelse try self.append(node.span, node.kind)
            else
                try self.append(node.span, node.kind),
            .special => |special| switch (special) {
                .pass_ref, .passed_ref => if (scope) |active_scope|
                    active_scope.passed() orelse try self.append(node.span, node.kind)
                else
                    try self.append(node.span, node.kind),
                else => try self.append(node.span, node.kind),
            },
            .text => |parts| try self.append(node.span, .{ .text = try self.normalizeNodeIds(parts, scope) }),
            .list => |list| try self.append(node.span, .{ .list = .{
                .kind = list.kind,
                .items = try self.normalizeNodeIds(list.items, scope),
            } }),
            .record => |fields| try self.append(node.span, .{ .record = try self.normalizeFields(fields, scope) }),
            .access => |access| try self.append(node.span, .{ .access = .{
                .target = try self.normalizeNode(access.target, scope),
                .field = access.field,
                .kind = access.kind,
            } }),
            .binary => |binary| try self.append(node.span, .{ .binary = .{
                .operator = binary.operator,
                .lhs = try self.normalizeNode(binary.lhs, scope),
                .rhs = try self.normalizeNode(binary.rhs, scope),
            } }),
            .block => |block| try self.normalizeBlock(node.span, block, scope),
            .when => |when| try self.append(node.span, .{ .when = .{
                .input = try self.normalizeNode(when.input, scope),
                .arms = try self.normalizeWhenArms(when.arms, scope),
            } }),
            .latest => |latest| try self.append(node.span, .{ .latest = .{
                .initial = if (latest.initial) |initial| try self.normalizeNode(initial, scope) else null,
                .sources = try self.normalizeNodeIds(latest.sources, scope),
            } }),
            .then_value => |then_value| try self.append(node.span, .{ .then_value = .{
                .source = try self.normalizeNode(then_value.source, scope),
                .value = try self.normalizeNode(then_value.value, scope),
            } }),
            .hold => |hold| try self.append(node.span, .{ .hold = .{
                .state_name = hold.state_name,
                .initial = try self.normalizeNode(hold.initial, scope),
                .updates = try self.normalizeNodeIds(hold.updates, scope),
            } }),
            .linked_value => |linked| try self.append(node.span, .{ .linked_value = .{
                .value = try self.normalizeNode(linked.value, scope),
                .target = try self.normalizeNode(linked.target, scope),
            } }),
            .builtin_call => |call| try self.append(node.span, .{ .builtin_call = .{
                .path = call.path,
                .positional = try self.normalizeNodeIds(call.positional, scope),
                .named = try self.normalizeNamedArgs(call.named, scope),
            } }),
            .user_call => |call| try self.normalizeUserCall(node.span, call, scope),
        };
    }

    fn normalizeUserCall(self: *PassNormalizer, span: ast.Span, call: flow_ir.UserCall, scope: ?*const NormalizeScope) anyerror!flow_ir.NodeId {
        const function_index: usize = call.function;
        if (function_index >= self.flow.functions.len) return try self.append(span, .{ .user_call = call });
        const function = self.flow.functions[function_index];

        var bindings: std.ArrayList(NormalizeBinding) = .empty;
        defer bindings.deinit(self.allocator);
        var filled = try self.allocator.alloc(bool, function.params.len);
        @memset(filled, false);

        for (call.positional, 0..) |arg, index| {
            if (index >= function.params.len) break;
            try bindings.append(self.allocator, .{
                .name = function.params[index],
                .value = try self.normalizeNode(arg, scope),
            });
            filled[index] = true;
        }

        for (call.named) |arg| {
            for (function.params, 0..) |param, index| {
                if (!std.mem.eql(u8, param, arg.name)) continue;
                try bindings.append(self.allocator, .{
                    .name = param,
                    .value = try self.normalizeNode(arg.value, scope),
                });
                filled[index] = true;
                break;
            }
        }

        for (filled) |is_filled| {
            if (!is_filled) return try self.append(span, .{ .user_call = .{
                .function = call.function,
                .positional = try self.normalizeNodeIds(call.positional, scope),
                .named = try self.normalizeNamedArgs(call.named, scope),
                .pass_context = if (call.pass_context) |pass_context| try self.normalizeNode(pass_context, scope) else null,
            } });
        }

        const pass_context = if (call.pass_context) |pass_context|
            try self.normalizeNode(pass_context, scope)
        else if (scope) |active_scope|
            active_scope.passed()
        else
            null;
        const function_scope = NormalizeScope{
            .parent = null,
            .bindings = bindings.items,
            .pass_context = pass_context,
        };
        return try self.normalizeNode(function.body, &function_scope);
    }

    fn normalizeBlock(self: *PassNormalizer, span: ast.Span, block: flow_ir.Block, parent_scope: ?*const NormalizeScope) anyerror!flow_ir.NodeId {
        var normalized_bindings: std.ArrayList(flow_ir.BlockBinding) = .empty;
        defer normalized_bindings.deinit(self.allocator);
        var scope_bindings: std.ArrayList(NormalizeBinding) = .empty;
        defer scope_bindings.deinit(self.allocator);
        var scope = NormalizeScope{
            .parent = parent_scope,
            .bindings = &.{},
            .pass_context = if (parent_scope) |active_scope| active_scope.passed() else null,
        };

        for (block.bindings) |binding| {
            const value = try self.normalizeNode(binding.value, &scope);
            try normalized_bindings.append(self.allocator, .{
                .name = binding.name,
                .value = value,
            });
            try scope_bindings.append(self.allocator, .{
                .name = binding.name,
                .value = value,
            });
            scope.bindings = scope_bindings.items;
        }

        return try self.append(span, .{ .block = .{
            .bindings = try normalized_bindings.toOwnedSlice(self.allocator),
            .result = try self.normalizeNode(block.result, &scope),
        } });
    }

    fn normalizeNodeIds(self: *PassNormalizer, ids: []const flow_ir.NodeId, scope: ?*const NormalizeScope) anyerror![]flow_ir.NodeId {
        const normalized = try self.allocator.alloc(flow_ir.NodeId, ids.len);
        for (ids, 0..) |id, index| normalized[index] = try self.normalizeNode(id, scope);
        return normalized;
    }

    fn normalizeFields(self: *PassNormalizer, fields: []const flow_ir.Field, scope: ?*const NormalizeScope) anyerror![]flow_ir.Field {
        const normalized = try self.allocator.alloc(flow_ir.Field, fields.len);
        for (fields, 0..) |field, index| {
            normalized[index] = .{
                .name = field.name,
                .value = try self.normalizeNode(field.value, scope),
            };
        }
        return normalized;
    }

    fn normalizeNamedArgs(self: *PassNormalizer, args: []const flow_ir.NamedArg, scope: ?*const NormalizeScope) anyerror![]flow_ir.NamedArg {
        const normalized = try self.allocator.alloc(flow_ir.NamedArg, args.len);
        for (args, 0..) |arg, index| {
            normalized[index] = .{
                .name = arg.name,
                .value = try self.normalizeNode(arg.value, scope),
            };
        }
        return normalized;
    }

    fn normalizeWhenArms(self: *PassNormalizer, arms: []const flow_ir.WhenArm, scope: ?*const NormalizeScope) anyerror![]flow_ir.WhenArm {
        const normalized = try self.allocator.alloc(flow_ir.WhenArm, arms.len);
        for (arms, 0..) |arm, index| {
            normalized[index] = .{
                .pattern = try self.normalizeNode(arm.pattern, scope),
                .result = try self.normalizeNode(arm.result, scope),
            };
        }
        return normalized;
    }

    fn append(self: *PassNormalizer, span: ast.Span, kind: flow_ir.Node.Kind) !flow_ir.NodeId {
        const id: flow_ir.NodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{
            .span = span,
            .kind = kind,
        });
        return id;
    }
};

fn physicalFlowForRuntimeAlloc(allocator: std.mem.Allocator, flow: *const flow_ir.Document) !PhysicalFlow {
    if (!flowHasUserCalls(flow)) {
        return .{
            .nodes = flow.nodes,
            .bindings = flow.bindings,
        };
    }

    var normalizer = PassNormalizer{
        .allocator = allocator,
        .flow = flow,
    };
    errdefer normalizer.deinit();
    const bindings = try normalizer.normalizeBindings();
    return .{
        .nodes = try normalizer.nodes.toOwnedSlice(allocator),
        .bindings = bindings,
    };
}

fn flowHasUserCalls(flow: *const flow_ir.Document) bool {
    for (flow.nodes) |node| {
        if (node.kind == .user_call) return true;
    }
    return false;
}

fn copyRecordFields(allocator: std.mem.Allocator, fields: []const flow_ir.Field) ![]RecordFieldInstruction {
    const copied = try allocator.alloc(RecordFieldInstruction, fields.len);
    for (fields, 0..) |field, index| {
        copied[index] = .{
            .name = try allocator.dupe(u8, field.name),
            .value = field.value,
        };
    }
    return copied;
}

fn selectBuiltinInstruction(call: flow_ir.BuiltinCall, dst: ValueSlotId) !Instruction {
    if (std.mem.eql(u8, call.path, "List/map")) {
        return .{ .list_map = .{
            .dst = dst,
            .input = call.positional[0],
            .body = namedArgValue(call.named, "new"),
        } };
    }
    if (std.mem.eql(u8, call.path, "List/latest")) {
        return .{ .list_latest = .{
            .dst = dst,
            .input = call.positional[0],
        } };
    }
    return .{ .eval_flow_node = dst };
}

fn namedArgValue(args: []const flow_ir.NamedArg, name: []const u8) ?ValueSlotId {
    for (args) |arg| {
        if (std.mem.eql(u8, arg.name, name)) return arg.value;
    }
    return null;
}

fn copyWhenArms(allocator: std.mem.Allocator, arms: []const flow_ir.WhenArm) ![]WhenArmInstruction {
    const copied = try allocator.alloc(WhenArmInstruction, arms.len);
    for (arms, 0..) |arm, index| {
        copied[index] = .{
            .pattern = arm.pattern,
            .result = arm.result,
        };
    }
    return copied;
}

fn stateSlotForLocalRef(state_slots: []const StateSlot, name: []const u8) ?StateSlotId {
    for (state_slots) |slot| {
        if (!std.mem.startsWith(u8, slot.semantic_id, "hold.")) continue;
        if (std.mem.eql(u8, slot.semantic_id["hold.".len..], name)) return slot.id;
    }
    return null;
}

fn copyNodeIds(allocator: std.mem.Allocator, ids: []const flow_ir.NodeId) ![]ValueSlotId {
    const copied = try allocator.alloc(ValueSlotId, ids.len);
    for (ids, 0..) |id, index| copied[index] = id;
    return copied;
}

fn stateSlotForFlowNode(state_slots: []const StateSlot, flow_node: flow_ir.NodeId) ?StateSlotId {
    for (state_slots) |slot| {
        if (slot.flow_node == flow_node) return slot.id;
    }
    return null;
}

fn sourceValueSlotForPath(flow: PhysicalFlow, path: []const u8) ?ValueSlotId {
    for (flow.nodes, 0..) |_, index| {
        if (flowNodePathMatches(flow, @intCast(index), path)) return @intCast(index);
    }
    return null;
}

fn flowNodePathMatches(flow: PhysicalFlow, node_id: flow_ir.NodeId, expected: []const u8) bool {
    var scratch: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&scratch);
    writeFlowNodePath(&writer, flow, node_id) catch return false;
    return std.mem.eql(u8, writer.buffered(), expected);
}

fn writeFlowNodePath(writer: *std.Io.Writer, flow: PhysicalFlow, node_id: flow_ir.NodeId) !void {
    const node_index: usize = node_id;
    if (node_index >= flow.nodes.len) return error.InvalidFlowNode;
    switch (flow.nodes[node_index].kind) {
        .binding_ref => |binding_id| {
            const binding_index: usize = binding_id;
            if (binding_index >= flow.bindings.len) return error.InvalidBinding;
            try writer.writeAll(flow.bindings[binding_index].name);
        },
        .local_ref => |name| try writer.writeAll(name),
        .access => |access| {
            try writeFlowNodePath(writer, flow, access.target);
            try writer.writeByte('.');
            try writer.writeAll(access.field);
        },
        else => return error.NotAPath,
    }
}

fn validateSourceFields(allocator: std.mem.Allocator, fields: []const source_shape.SourceField) ?diag.Diagnostic {
    var seen = std.StringHashMap(ast.Span).init(allocator);
    defer seen.deinit();
    for (fields) |field| {
        if (sourcePathHasEventNamespaceLeaf(field.path)) {
            return .{ .message = "incompatible source binding", .span = field.span };
        }
        if (seen.get(field.path)) |_| {
            return .{ .message = "multiple active binders", .span = field.span };
        }
        seen.put(field.path, field.span) catch unreachable;
    }
    return null;
}

fn validateNoRuntimeSpecials(flow: PhysicalFlow) ?diag.Diagnostic {
    for (flow.nodes) |node| {
        switch (node.kind) {
            .special => |special| switch (special) {
                .pass_ref, .passed_ref => return .{
                    .message = "PASS/PASSED must be lowered before Physical Runtime execution",
                    .span = node.span,
                },
                .drain_reserved => return .{
                    .message = "DRAIN is reserved and cannot lower to Physical Runtime",
                    .span = node.span,
                },
                .skip_ref, .link_ref => {},
            },
            else => {},
        }
    }
    return null;
}

fn sourcePathHasEventNamespaceLeaf(path: []const u8) bool {
    if (std.mem.eql(u8, path, "event")) return true;
    return std.mem.endsWith(u8, path, ".event");
}

fn lowerStateSlots(allocator: std.mem.Allocator, flow: PhysicalFlow) ![]StateSlot {
    var state_slots: std.ArrayList(StateSlot) = .empty;
    defer state_slots.deinit(allocator);
    for (flow.nodes, 0..) |node, index| {
        switch (node.kind) {
            .hold => |hold| try state_slots.append(allocator, .{
                .id = @intCast(state_slots.items.len),
                .semantic_id = try std.fmt.allocPrint(allocator, "hold.{s}", .{hold.state_name}),
                .flow_node = @intCast(index),
            }),
            else => {},
        }
    }
    return try state_slots.toOwnedSlice(allocator);
}

fn appendNodeDependencies(
    allocator: std.mem.Allocator,
    edges: *std.ArrayList(DependencyEdge),
    to: PhysicalId,
    node: flow_ir.Node,
) !void {
    switch (node.kind) {
        .number, .atom, .symbol, .local_ref, .special, .link_port, .binding_ref => {},
        .text => |parts| for (parts) |part| try appendEdge(edges, part, to, allocator),
        .list => |list| for (list.items) |item| try appendEdge(edges, item, to, allocator),
        .record => |fields| for (fields) |field| try appendEdge(edges, field.value, to, allocator),
        .access => |access| try appendEdge(edges, access.target, to, allocator),
        .binary => |binary| {
            try appendEdge(edges, binary.lhs, to, allocator);
            try appendEdge(edges, binary.rhs, to, allocator);
        },
        .block => |block| {
            for (block.bindings) |binding| try appendEdge(edges, binding.value, to, allocator);
            try appendEdge(edges, block.result, to, allocator);
        },
        .when => |when| {
            try appendEdge(edges, when.input, to, allocator);
            for (when.arms) |arm| {
                try appendEdge(edges, arm.pattern, to, allocator);
                try appendEdge(edges, arm.result, to, allocator);
            }
        },
        .latest => |latest| {
            if (latest.initial) |initial| try appendEdge(edges, initial, to, allocator);
            for (latest.sources) |source| try appendEdge(edges, source, to, allocator);
        },
        .then_value => |then_value| {
            try appendEdge(edges, then_value.source, to, allocator);
            try appendEdge(edges, then_value.value, to, allocator);
        },
        .hold => |hold| {
            try appendEdge(edges, hold.initial, to, allocator);
            for (hold.updates) |update| try appendEdge(edges, update, to, allocator);
        },
        .linked_value => |linked| {
            try appendEdge(edges, linked.value, to, allocator);
            try appendEdge(edges, linked.target, to, allocator);
        },
        .builtin_call => |call| {
            for (call.positional) |arg| try appendEdge(edges, arg, to, allocator);
            for (call.named) |arg| try appendEdge(edges, arg.value, to, allocator);
        },
        .user_call => |call| {
            for (call.positional) |arg| try appendEdge(edges, arg, to, allocator);
            for (call.named) |arg| try appendEdge(edges, arg.value, to, allocator);
            if (call.pass_context) |pass_context| try appendEdge(edges, pass_context, to, allocator);
        },
    }
}

fn appendEdge(edges: *std.ArrayList(DependencyEdge), from: flow_ir.NodeId, to: PhysicalId, allocator: std.mem.Allocator) !void {
    try edges.append(allocator, .{ .from = from, .to = to });
}

fn countListNodes(flow: PhysicalFlow) usize {
    var count: usize = 0;
    for (flow.nodes) |node| {
        if (node.kind == .list) count += 1;
    }
    return count;
}

pub fn renderAlloc(allocator: std.mem.Allocator, program: *const PhysicalProgram) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    const writer = &output.writer;
    try writer.print("physical source_slots={d} value_slots={d} state_slots={d} instructions={d} edges={d}\n", .{
        program.source_slots.len,
        program.value_slots.len,
        program.state_slots.len,
        program.instructions.len,
        program.dependency_edges.len,
    });
    for (program.source_slots) |slot| {
        try writer.print("source[{d}] {s} : {s}\n", .{ slot.id, slot.semantic_id, slot.payload_type });
    }
    for (program.state_slots) |slot| {
        try writer.print("state[{d}] {s} <- flow.n{d}\n", .{ slot.id, slot.semantic_id, slot.flow_node });
    }
    return try output.toOwnedSlice();
}

test "lowers canonical SOURCE leaves to physical source slots" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\hover: SOURCE
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
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
    try std.testing.expectEqual(@as(SourceSlotId, 0), program.source_slots[0].id);
    try std.testing.expectEqualStrings("button.event.press", program.source_slots[0].semantic_id);
    try std.testing.expectEqualStrings("Pulse", program.source_slots[0].payload_type);
    try std.testing.expectEqual(@as(SourceSlotId, 1), program.source_slots[1].id);
    try std.testing.expectEqualStrings("hover", program.source_slots[1].semantic_id);
    try std.testing.expectEqualStrings("Pulse", program.source_slots[1].payload_type);
}

test "renders canonical counter-style physical golden" {
    const source =
        \\increment_button: [event: [press: SOURCE] hovered: SOURCE]
        \\counter: 0
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    var program = switch (outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected physical IR golden failure: {s}\n", .{failure.message});
            return error.UnexpectedPhysicalIrFailure;
        },
    };
    defer program.deinit();

    const rendered = try renderAlloc(std.testing.allocator, &program);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(
        \\physical source_slots=2 value_slots=5 state_slots=0 instructions=5 edges=3
        \\source[0] increment_button.event.press : Pulse
        \\source[1] increment_button.hovered : Bool
        \\
    , rendered);
}

test "freezes static source spreads" {
    const source =
        \\button: [event: [press: SOURCE]]
        \\copy: [...button]
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
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

test "rejects dynamic source spreads" {
    const source =
        \\copy: [...dynamic_sources()]
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedDynamicSourceShapeFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("dynamic source shape", failure.message),
    }
}

test "canonical Physical IR rejects legacy LINK" {
    const source = "button: [event: [press: LINK]]\n";
    const outcome = try lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |program| {
            var physical_program = program;
            physical_program.deinit();
            return error.ExpectedCanonicalLinkFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("`LINK` was renamed to `SOURCE`; use `SOURCE` in canonical source mode", failure.message),
    }
}
