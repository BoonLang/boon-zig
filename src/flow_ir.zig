const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const hir = @import("hir.zig");

const LowerError = std.mem.Allocator.Error || error{LoweringFailed};

pub const NodeId = u32;
pub const BindingId = u32;
pub const FunctionId = u32;

pub const Outcome = union(enum) {
    ok: Document,
    err: diag.Diagnostic,
};

pub const Number = struct {
    text: []const u8,
    value: f64,
};

pub const Field = struct {
    name: []const u8,
    value: NodeId,
};

pub const NamedArg = struct {
    name: []const u8,
    value: NodeId,
};

pub const Access = struct {
    target: NodeId,
    field: []const u8,
    kind: ast.AccessKind,
};

pub const ListKind = enum {
    dynamic,
    static,
    bits_dynamic,
    bits_static,
    bytes_dynamic,
    bytes_static,
    memory_dynamic,
    memory_static,
};

pub const List = struct {
    kind: ListKind,
    items: []NodeId,
};

pub const Latest = struct {
    initial: ?NodeId,
    sources: []NodeId,
};

pub const ThenValue = struct {
    source: NodeId,
    value: NodeId,
};

pub const Hold = struct {
    state_name: []const u8,
    initial: NodeId,
    updates: []NodeId,
};

pub const Binary = struct {
    operator: ast.BinaryOp,
    lhs: NodeId,
    rhs: NodeId,
};

pub const BlockBinding = struct {
    name: []const u8,
    value: NodeId,
};

pub const Block = struct {
    bindings: []BlockBinding,
    result: NodeId,
};

pub const WhenArm = struct {
    pattern: NodeId,
    result: NodeId,
};

pub const When = struct {
    input: NodeId,
    arms: []WhenArm,
};

pub const BuiltinCall = struct {
    path: []const u8,
    positional: []NodeId,
    named: []NamedArg,
};

pub const UserCall = struct {
    function: FunctionId,
    positional: []NodeId,
    named: []NamedArg,
    pass_context: ?NodeId,
};

pub const LinkedValue = struct {
    value: NodeId,
    target: NodeId,
};

pub const Node = struct {
    span: ast.Span,
    kind: Kind,

    pub const Kind = union(enum) {
        number: Number,
        atom: []const u8,
        symbol: []const u8,
        local_ref: []const u8,
        special: hir.SpecialKind,
        link_port: []const u8,
        binding_ref: BindingId,
        text: []NodeId,
        list: List,
        record: []Field,
        access: Access,
        binary: Binary,
        block: Block,
        when: When,
        latest: Latest,
        then_value: ThenValue,
        hold: Hold,
        linked_value: LinkedValue,
        builtin_call: BuiltinCall,
        user_call: UserCall,
    };
};

pub const Binding = struct {
    name: []const u8,
    node: NodeId,
    span: ast.Span,
};

pub const UserFunction = struct {
    name: []const u8,
    params: [][]const u8,
    body: NodeId,
    span: ast.Span,
};

pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    bindings: []Binding,
    functions: []UserFunction,
    nodes: []Node,
    root_binding: ?BindingId,
    source_len: usize,
    link_port_count: usize,
    stateful_count: usize,

    pub fn deinit(self: *Document) void {
        self.arena.deinit();
    }
};

const cache_magic = "BNCF";
const cache_version: u32 = 1;

pub const Options = struct {};

pub fn lowerAlloc(allocator: std.mem.Allocator, source: []const u8) !Outcome {
    return lowerAllocWithOptions(allocator, source, .{});
}

pub fn lowerAllocWithOptions(allocator: std.mem.Allocator, source: []const u8, options: Options) !Outcome {
    _ = options;
    const lowered_hir = try hir.lowerAlloc(allocator, source);
    const hir_document = switch (lowered_hir) {
        .ok => |document| document,
        .err => |failure| return .{ .err = failure },
    };
    var input = hir_document;
    defer input.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var lowerer = Lowerer.init(source, arena.allocator());
    lowerer.lowerDocument(input) catch |err| switch (err) {
        error.LoweringFailed => return .{ .err = lowerer.failure_diag.? },
        else => return err,
    };
    return .{ .ok = .{
        .arena = arena,
        .bindings = try lowerer.bindings.toOwnedSlice(lowerer.arena),
        .functions = try lowerer.functions.toOwnedSlice(lowerer.arena),
        .nodes = try lowerer.nodes.toOwnedSlice(lowerer.arena),
        .root_binding = lowerer.binding_lookup.get("terminal") orelse lowerer.binding_lookup.get("document") orelse lowerer.binding_lookup.get("scene"),
        .source_len = source.len,
        .link_port_count = lowerer.link_port_count,
        .stateful_count = lowerer.stateful_count,
    } };
}

pub fn renderAlloc(allocator: std.mem.Allocator, document: *const Document) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    const writer = &output.writer;
    const root_name = if (document.root_binding) |binding_id| document.bindings[binding_id].name else "<none>";
    try writer.print(
        "stats bindings={d} nodes={d} link_ports={d} stateful={d} root={s}\n",
        .{
            document.bindings.len,
            document.nodes.len,
            document.link_port_count,
            document.stateful_count,
            root_name,
        },
    );

    for (document.bindings, 0..) |binding, index| {
        try writer.print("binding[{d}] {s} = n{d}\n", .{ index, binding.name, binding.node });
    }
    for (document.nodes, 0..) |node, index| {
        try writer.print("n{d} = ", .{index});
        try renderNode(writer, document, node);
        try writer.writeByte('\n');
    }

    return try output.toOwnedSlice();
}

pub fn serializeDocument(writer: anytype, document: *const Document) !void {
    try writer.writeAll(cache_magic);
    try writer.writeInt(u32, cache_version, .little);
    try writer.writeInt(u32, @intCast(document.bindings.len), .little);
    try writer.writeInt(u32, @intCast(document.functions.len), .little);
    try writer.writeInt(u32, @intCast(document.nodes.len), .little);
    try writeOptionalU32(writer, if (document.root_binding) |binding_id| @as(u32, binding_id) else null);
    try writer.writeInt(u64, @intCast(document.source_len), .little);
    try writer.writeInt(u64, @intCast(document.link_port_count), .little);
    try writer.writeInt(u64, @intCast(document.stateful_count), .little);

    for (document.bindings) |binding| {
        try writeString(writer, binding.name);
        try writer.writeInt(u32, binding.node, .little);
        try writeSpan(writer, binding.span);
    }

    for (document.functions) |function| {
        try writeString(writer, function.name);
        try writer.writeInt(u32, @intCast(function.params.len), .little);
        for (function.params) |param| try writeString(writer, param);
        try writer.writeInt(u32, function.body, .little);
        try writeSpan(writer, function.span);
    }

    for (document.nodes) |node| {
        try writeSpan(writer, node.span);
        switch (node.kind) {
            .number => |number| {
                try writer.writeByte(0);
                try writeString(writer, number.text);
                try writer.writeInt(u64, @bitCast(number.value), .little);
            },
            .atom => |text| {
                try writer.writeByte(1);
                try writeString(writer, text);
            },
            .symbol => |text| {
                try writer.writeByte(2);
                try writeString(writer, text);
            },
            .local_ref => |text| {
                try writer.writeByte(3);
                try writeString(writer, text);
            },
            .special => |special| {
                try writer.writeByte(4);
                try writer.writeByte(@intFromEnum(special));
            },
            .link_port => |text| {
                try writer.writeByte(5);
                try writeString(writer, text);
            },
            .binding_ref => |binding_id| {
                try writer.writeByte(6);
                try writer.writeInt(u32, binding_id, .little);
            },
            .text => |parts| {
                try writer.writeByte(7);
                try writeNodeIdSlice(writer, parts);
            },
            .list => |list| {
                try writer.writeByte(8);
                try writer.writeByte(@intFromEnum(list.kind));
                try writeNodeIdSlice(writer, list.items);
            },
            .record => |fields| {
                try writer.writeByte(9);
                try writer.writeInt(u32, @intCast(fields.len), .little);
                for (fields) |field| {
                    try writeString(writer, field.name);
                    try writer.writeInt(u32, field.value, .little);
                }
            },
            .access => |access| {
                try writer.writeByte(10);
                try writer.writeInt(u32, access.target, .little);
                try writeString(writer, access.field);
                try writer.writeByte(@intFromEnum(access.kind));
            },
            .binary => |binary| {
                try writer.writeByte(11);
                try writer.writeByte(@intFromEnum(binary.operator));
                try writer.writeInt(u32, binary.lhs, .little);
                try writer.writeInt(u32, binary.rhs, .little);
            },
            .block => |block| {
                try writer.writeByte(12);
                try writer.writeInt(u32, @intCast(block.bindings.len), .little);
                for (block.bindings) |binding| {
                    try writeString(writer, binding.name);
                    try writer.writeInt(u32, binding.value, .little);
                }
                try writer.writeInt(u32, block.result, .little);
            },
            .when => |when| {
                try writer.writeByte(13);
                try writer.writeInt(u32, when.input, .little);
                try writer.writeInt(u32, @intCast(when.arms.len), .little);
                for (when.arms) |arm| {
                    try writer.writeInt(u32, arm.pattern, .little);
                    try writer.writeInt(u32, arm.result, .little);
                }
            },
            .latest => |latest| {
                try writer.writeByte(14);
                try writeOptionalU32(writer, latest.initial);
                try writeNodeIdSlice(writer, latest.sources);
            },
            .then_value => |then_value| {
                try writer.writeByte(15);
                try writer.writeInt(u32, then_value.source, .little);
                try writer.writeInt(u32, then_value.value, .little);
            },
            .hold => |hold| {
                try writer.writeByte(16);
                try writeString(writer, hold.state_name);
                try writer.writeInt(u32, hold.initial, .little);
                try writeNodeIdSlice(writer, hold.updates);
            },
            .linked_value => |linked| {
                try writer.writeByte(17);
                try writer.writeInt(u32, linked.value, .little);
                try writer.writeInt(u32, linked.target, .little);
            },
            .builtin_call => |call| {
                try writer.writeByte(18);
                try writeString(writer, call.path);
                try writeNodeIdSlice(writer, call.positional);
                try writer.writeInt(u32, @intCast(call.named.len), .little);
                for (call.named) |arg| {
                    try writeString(writer, arg.name);
                    try writer.writeInt(u32, arg.value, .little);
                }
            },
            .user_call => |call| {
                try writer.writeByte(19);
                try writer.writeInt(u32, call.function, .little);
                try writeNodeIdSlice(writer, call.positional);
                try writer.writeInt(u32, @intCast(call.named.len), .little);
                for (call.named) |arg| {
                    try writeString(writer, arg.name);
                    try writer.writeInt(u32, arg.value, .little);
                }
                try writeOptionalU32(writer, call.pass_context);
            },
        }
    }
}

pub fn deserializeDocumentAlloc(allocator: std.mem.Allocator, reader: anytype) !Document {
    var magic: [4]u8 = undefined;
    try reader.readSliceAll(&magic);
    if (!std.mem.eql(u8, &magic, cache_magic)) return error.InvalidCacheFormat;
    const version = try reader.takeInt(u32, .little);
    if (version != cache_version) return error.InvalidCacheFormat;

    const binding_count: usize = @intCast(try reader.takeInt(u32, .little));
    const function_count: usize = @intCast(try reader.takeInt(u32, .little));
    const node_count: usize = @intCast(try reader.takeInt(u32, .little));
    const root_binding_u32 = try readOptionalU32(reader);
    const source_len: usize = @intCast(try reader.takeInt(u64, .little));
    const link_port_count: usize = @intCast(try reader.takeInt(u64, .little));
    const stateful_count: usize = @intCast(try reader.takeInt(u64, .little));

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const bindings = try a.alloc(Binding, binding_count);
    for (bindings) |*binding| {
        binding.* = .{
            .name = try readString(a, reader),
            .node = try reader.takeInt(u32, .little),
            .span = try readSpan(reader),
        };
    }

    const functions = try a.alloc(UserFunction, function_count);
    for (functions) |*function| {
        const name = try readString(a, reader);
        const param_count: usize = @intCast(try reader.takeInt(u32, .little));
        const params = try a.alloc([]const u8, param_count);
        for (params) |*param| param.* = try readString(a, reader);
        function.* = .{
            .name = name,
            .params = params,
            .body = try reader.takeInt(u32, .little),
            .span = try readSpan(reader),
        };
    }

    const nodes = try a.alloc(Node, node_count);
    for (nodes) |*node| {
        const span = try readSpan(reader);
        const tag = try reader.takeByte();
        node.* = .{
            .span = span,
            .kind = switch (tag) {
                0 => .{ .number = .{ .text = try readString(a, reader), .value = @bitCast(try reader.takeInt(u64, .little)) } },
                1 => .{ .atom = try readString(a, reader) },
                2 => .{ .symbol = try readString(a, reader) },
                3 => .{ .local_ref = try readString(a, reader) },
                4 => .{ .special = @enumFromInt(try reader.takeByte()) },
                5 => .{ .link_port = try readString(a, reader) },
                6 => .{ .binding_ref = try reader.takeInt(u32, .little) },
                7 => .{ .text = try readNodeIdSlice(a, reader) },
                8 => .{ .list = .{ .kind = @enumFromInt(try reader.takeByte()), .items = try readNodeIdSlice(a, reader) } },
                9 => .{ .record = try readFieldSlice(a, reader) },
                10 => .{ .access = .{
                    .target = try reader.takeInt(u32, .little),
                    .field = try readString(a, reader),
                    .kind = @enumFromInt(try reader.takeByte()),
                } },
                11 => .{ .binary = .{
                    .operator = @enumFromInt(try reader.takeByte()),
                    .lhs = try reader.takeInt(u32, .little),
                    .rhs = try reader.takeInt(u32, .little),
                } },
                12 => .{ .block = .{
                    .bindings = try readBlockBindingSlice(a, reader),
                    .result = try reader.takeInt(u32, .little),
                } },
                13 => .{ .when = .{
                    .input = try reader.takeInt(u32, .little),
                    .arms = try readWhenArmSlice(a, reader),
                } },
                14 => .{ .latest = .{
                    .initial = try readOptionalU32(reader),
                    .sources = try readNodeIdSlice(a, reader),
                } },
                15 => .{ .then_value = .{
                    .source = try reader.takeInt(u32, .little),
                    .value = try reader.takeInt(u32, .little),
                } },
                16 => .{ .hold = .{
                    .state_name = try readString(a, reader),
                    .initial = try reader.takeInt(u32, .little),
                    .updates = try readNodeIdSlice(a, reader),
                } },
                17 => .{ .linked_value = .{
                    .value = try reader.takeInt(u32, .little),
                    .target = try reader.takeInt(u32, .little),
                } },
                18 => .{ .builtin_call = .{
                    .path = try readString(a, reader),
                    .positional = try readNodeIdSlice(a, reader),
                    .named = try readNamedArgSlice(a, reader),
                } },
                19 => .{ .user_call = .{
                    .function = try reader.takeInt(u32, .little),
                    .positional = try readNodeIdSlice(a, reader),
                    .named = try readNamedArgSlice(a, reader),
                    .pass_context = try readOptionalU32(reader),
                } },
                else => return error.InvalidCacheFormat,
            },
        };
    }

    return .{
        .arena = arena,
        .bindings = bindings,
        .functions = functions,
        .nodes = nodes,
        .root_binding = if (root_binding_u32) |binding_id| binding_id else null,
        .source_len = source_len,
        .link_port_count = link_port_count,
        .stateful_count = stateful_count,
    };
}

fn writeSpan(writer: anytype, span: ast.Span) !void {
    try writer.writeInt(u64, @intCast(span.start), .little);
    try writer.writeInt(u64, @intCast(span.end), .little);
}

fn readSpan(reader: anytype) !ast.Span {
    return .{
        .start = @intCast(try reader.takeInt(u64, .little)),
        .end = @intCast(try reader.takeInt(u64, .little)),
    };
}

fn writeString(writer: anytype, text: []const u8) !void {
    try writer.writeInt(u32, @intCast(text.len), .little);
    try writer.writeAll(text);
}

fn readString(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    const len: usize = @intCast(try reader.takeInt(u32, .little));
    const text = try allocator.alloc(u8, len);
    try reader.readSliceAll(text);
    return text;
}

fn writeOptionalU32(writer: anytype, value: ?u32) !void {
    try writer.writeByte(if (value != null) 1 else 0);
    if (value) |resolved| try writer.writeInt(u32, resolved, .little);
}

fn readOptionalU32(reader: anytype) !?u32 {
    return if (try reader.takeByte() == 0) null else try reader.takeInt(u32, .little);
}

fn writeNodeIdSlice(writer: anytype, items: []NodeId) !void {
    try writer.writeInt(u32, @intCast(items.len), .little);
    for (items) |item| try writer.writeInt(u32, item, .little);
}

fn readNodeIdSlice(allocator: std.mem.Allocator, reader: anytype) ![]NodeId {
    const count: usize = @intCast(try reader.takeInt(u32, .little));
    const items = try allocator.alloc(NodeId, count);
    for (items) |*item| item.* = try reader.takeInt(u32, .little);
    return items;
}

fn readFieldSlice(allocator: std.mem.Allocator, reader: anytype) ![]Field {
    const count: usize = @intCast(try reader.takeInt(u32, .little));
    const fields = try allocator.alloc(Field, count);
    for (fields) |*field| {
        field.* = .{
            .name = try readString(allocator, reader),
            .value = try reader.takeInt(u32, .little),
        };
    }
    return fields;
}

fn readNamedArgSlice(allocator: std.mem.Allocator, reader: anytype) ![]NamedArg {
    const count: usize = @intCast(try reader.takeInt(u32, .little));
    const args = try allocator.alloc(NamedArg, count);
    for (args) |*arg| {
        arg.* = .{
            .name = try readString(allocator, reader),
            .value = try reader.takeInt(u32, .little),
        };
    }
    return args;
}

fn readBlockBindingSlice(allocator: std.mem.Allocator, reader: anytype) ![]BlockBinding {
    const count: usize = @intCast(try reader.takeInt(u32, .little));
    const bindings = try allocator.alloc(BlockBinding, count);
    for (bindings) |*binding| {
        binding.* = .{
            .name = try readString(allocator, reader),
            .value = try reader.takeInt(u32, .little),
        };
    }
    return bindings;
}

fn readWhenArmSlice(allocator: std.mem.Allocator, reader: anytype) ![]WhenArm {
    const count: usize = @intCast(try reader.takeInt(u32, .little));
    const arms = try allocator.alloc(WhenArm, count);
    for (arms) |*arm| {
        arm.* = .{
            .pattern = try reader.takeInt(u32, .little),
            .result = try reader.takeInt(u32, .little),
        };
    }
    return arms;
}

fn renderNode(writer: *std.Io.Writer, document: *const Document, node: Node) !void {
    switch (node.kind) {
        .number => |number| try writer.print("number({s})", .{number.text}),
        .atom => |text| try writer.print("atom({s})", .{text}),
        .symbol => |text| try writer.print("symbol({s})", .{text}),
        .local_ref => |text| try writer.print("local({s})", .{text}),
        .special => |special| try writer.print("special({s})", .{@tagName(special)}),
        .link_port => |label| try writer.print("link({s})", .{label}),
        .binding_ref => |binding_id| try writer.print("ref({s})", .{document.bindings[binding_id].name}),
        .text => |parts| {
            try writer.writeAll("text(");
            for (parts, 0..) |part, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("n{d}", .{part});
            }
            try writer.writeByte(')');
        },
        .list => |list| {
            try writer.print("list<{s}>(", .{@tagName(list.kind)});
            for (list.items, 0..) |item, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("n{d}", .{item});
            }
            try writer.writeByte(')');
        },
        .record => |fields| {
            try writer.writeAll("record(");
            for (fields, 0..) |field, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("{s}=n{d}", .{ field.name, field.value });
            }
            try writer.writeByte(')');
        },
        .access => |access| try writer.print("access(n{d}, {s}, {s})", .{ access.target, access.field, @tagName(access.kind) }),
        .binary => |binary| try writer.print("binary({s}, n{d}, n{d})", .{ @tagName(binary.operator), binary.lhs, binary.rhs }),
        .block => |block| {
            try writer.writeAll("block(");
            for (block.bindings, 0..) |binding, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("{s}=n{d}", .{ binding.name, binding.value });
            }
            if (block.bindings.len != 0) try writer.writeAll(", ");
            try writer.print("result=n{d})", .{block.result});
        },
        .when => |when| {
            try writer.print("when(n{d}", .{when.input});
            for (when.arms) |arm| {
                try writer.print(", n{d}->n{d}", .{ arm.pattern, arm.result });
            }
            try writer.writeByte(')');
        },
        .latest => |latest| {
            if (latest.initial) |initial| {
                try writer.print("latest(init=n{d}", .{initial});
            } else {
                try writer.writeAll("latest(init=<none>");
            }
            for (latest.sources) |source| {
                try writer.print(", source=n{d}", .{source});
            }
            try writer.writeByte(')');
        },
        .then_value => |then_value| try writer.print("then(n{d} -> n{d})", .{ then_value.source, then_value.value }),
        .hold => |hold| {
            try writer.print("hold({s}, init=n{d}", .{ hold.state_name, hold.initial });
            for (hold.updates) |update| {
                try writer.print(", update=n{d}", .{update});
            }
            try writer.writeByte(')');
        },
        .linked_value => |linked| try writer.print("linked(n{d} -> n{d})", .{ linked.value, linked.target }),
        .builtin_call => |call| {
            try writer.print("call({s}", .{call.path});
            for (call.positional) |input| {
                try writer.print(", n{d}", .{input});
            }
            for (call.named) |named| {
                try writer.print(", {s}=n{d}", .{ named.name, named.value });
            }
            try writer.writeByte(')');
        },
        .user_call => |call| {
            try writer.print("user_call(f{d}", .{call.function});
            for (call.positional) |input| {
                try writer.print(", n{d}", .{input});
            }
            for (call.named) |named| {
                try writer.print(", {s}=n{d}", .{ named.name, named.value });
            }
            if (call.pass_context) |pass_context| {
                try writer.print(", PASS=n{d}", .{pass_context});
            }
            try writer.writeByte(')');
        },
    }
}

const Scope = struct {
    parent: ?*const Scope,
    names: []const []const u8,
    binding_nodes: ?*const std.StringHashMapUnmanaged(NodeId) = null,

    fn contains(self: *const Scope, name: []const u8) bool {
        var current: ?*const Scope = self;
        while (current) |scope| {
            for (scope.names) |entry| {
                if (std.mem.eql(u8, entry, name)) return true;
            }
            current = scope.parent;
        }
        return false;
    }

    fn lookupNode(self: *const Scope, name: []const u8) ?NodeId {
        var current: ?*const Scope = self;
        while (current) |scope| {
            if (scope.binding_nodes) |bindings| {
                if (bindings.get(name)) |node_id| return node_id;
            }
            current = scope.parent;
        }
        return null;
    }
};

const Lowerer = struct {
    source: []const u8,
    arena: std.mem.Allocator,
    failure_diag: ?diag.Diagnostic = null,
    bindings: std.ArrayList(Binding) = .empty,
    functions: std.ArrayList(UserFunction) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    binding_lookup: std.StringHashMapUnmanaged(BindingId) = .empty,
    function_lookup: std.StringHashMapUnmanaged(FunctionId) = .empty,
    link_port_count: usize = 0,
    stateful_count: usize = 0,

    fn init(source: []const u8, arena: std.mem.Allocator) Lowerer {
        return .{
            .source = source,
            .arena = arena,
        };
    }

    fn lowerDocument(self: *Lowerer, input: hir.Document) LowerError!void {
        try self.collectFunctions(input.items);
        try self.collectBindings(input.items);

        for (input.items) |item| {
            switch (item) {
                .binding => {},
                .expr => |expr| {
                    if (!(expr == .form and expr.form.kind == .function_decl)) {
                        return self.fail(ast.Span.init(0, input.source_len), "flow slice only supports root-level bindings and FUNCTION declarations");
                    }
                    try self.lowerFunction(expr.form);
                },
            }
        }

        var binding_nodes = try self.arena.alloc(NodeId, self.bindings.items.len);
        var binding_index: usize = 0;
        for (input.items) |item| {
            switch (item) {
                .binding => |binding| {
                    binding_nodes[binding_index] = try self.lowerExprInScope(binding.value, null);
                    binding_index += 1;
                },
                .expr => continue,
            }
        }

        for (binding_nodes, 0..) |node, index| {
            self.bindings.items[index].node = node;
        }
    }

    fn collectFunctions(self: *Lowerer, items: []hir.Item) LowerError!void {
        for (items) |item| {
            const expr = switch (item) {
                .binding => continue,
                .expr => |expr| expr,
            };
            if (!(expr == .form and expr.form.kind == .function_decl)) continue;
            const form = expr.form;
            if (form.bare_args.len != 1) return self.fail(form.span, "FUNCTION expects exactly one bare name");
            const function_id: FunctionId = @intCast(self.functions.items.len);
            const name = try self.arena.dupe(u8, form.bare_args[0].text);
            try self.functions.append(self.arena, .{
                .name = name,
                .params = &.{},
                .body = 0,
                .span = form.span,
            });
            try self.function_lookup.put(self.arena, form.bare_args[0].text, function_id);
        }
    }

    fn collectBindings(self: *Lowerer, items: []hir.Item) LowerError!void {
        for (items) |item| {
            const binding = switch (item) {
                .binding => |binding| binding,
                .expr => continue,
            };
            const index: BindingId = @intCast(self.bindings.items.len);
            try self.bindings.append(self.arena, .{
                .name = try self.arena.dupe(u8, binding.name.text),
                .node = 0,
                .span = binding.span,
            });
            try self.binding_lookup.put(self.arena, binding.name.text, index);
        }
    }

    fn lowerExpr(self: *Lowerer, expr: hir.Expr) LowerError!NodeId {
        return try self.lowerExprInScope(expr, null);
    }

    fn lowerExprInScope(self: *Lowerer, expr: hir.Expr, scope: ?*const Scope) LowerError!NodeId {
        return switch (expr) {
            .number => |number| blk: {
                const parsed = std.fmt.parseFloat(f64, number.text) catch {
                    return self.fail(number.span, "invalid numeric literal");
                };
                break :blk try self.addNode(exprSpan(expr), .{
                    .number = .{
                        .text = try self.arena.dupe(u8, number.text),
                        .value = parsed,
                    },
                });
            },
            .atom => |literal| try self.addNode(exprSpan(expr), .{ .atom = try self.arena.dupe(u8, literal.text) }),
            .wildcard => |literal| try self.addNode(exprSpan(expr), .{ .atom = try self.arena.dupe(u8, literal.text) }),
            .symbol => |symbol| blk: {
                if (symbol.kind == .snake) {
                    if (scope) |local_scope| {
                        if (local_scope.lookupNode(symbol.text)) |node_id| {
                            break :blk node_id;
                        }
                        if (local_scope.contains(symbol.text)) {
                            break :blk try self.addNode(exprSpan(expr), .{ .local_ref = try self.arena.dupe(u8, symbol.text) });
                        }
                    }
                    if (self.binding_lookup.get(symbol.text)) |binding_id| {
                        break :blk try self.addNode(exprSpan(expr), .{ .binding_ref = binding_id });
                    }
                }
                break :blk try self.addNode(exprSpan(expr), .{ .symbol = try self.arena.dupe(u8, symbol.text) });
            },
            .special => |special| switch (special.kind) {
                .link_ref => try self.addLinkPort(special.span),
                else => try self.addNode(exprSpan(expr), .{ .special = special.kind }),
            },
            .path => |path| try self.addNode(exprSpan(expr), .{ .symbol = try self.renderPath(path.segments) }),
            .record => |record| try self.lowerRecord(exprSpan(expr), record.fields, scope),
            .access => |access| try self.addNode(exprSpan(expr), .{
                .access = .{
                    .target = try self.lowerExprInScope(access.target, scope),
                    .field = try self.arena.dupe(u8, access.field.text),
                    .kind = access.kind,
                },
            }),
            .binary => |binary| try self.addNode(exprSpan(expr), .{
                .binary = .{
                    .operator = binary.operator,
                    .lhs = try self.lowerExprInScope(binary.lhs, scope),
                    .rhs = try self.lowerExprInScope(binary.rhs, scope),
                },
            }),
            .form => |form| try self.lowerForm(form, scope),
            .call => |call| try self.lowerCall(exprSpan(expr), call, scope),
            .sequence => |sequence| try self.lowerSequenceExpr(sequence, scope),
            .unary => |unary| switch (unary.operator) {
                .negate => try self.addNode(exprSpan(expr), .{
                    .binary = .{
                        .operator = .subtract,
                        .lhs = try self.addNode(exprSpan(expr), .{
                            .number = .{
                                .text = try self.arena.dupe(u8, "0"),
                                .value = 0,
                            },
                        }),
                        .rhs = try self.lowerExprInScope(unary.operand, scope),
                    },
                }),
                .spread => try self.lowerExprInScope(unary.operand, scope),
            },
        };
    }

    fn lowerRecord(self: *Lowerer, span: ast.Span, fields: []*hir.Binding, scope: ?*const Scope) LowerError!NodeId {
        var lowered_fields: std.ArrayList(Field) = .empty;
        defer lowered_fields.deinit(self.arena);
        var local_bindings: std.StringHashMapUnmanaged(NodeId) = .empty;

        var record_scope = Scope{
            .parent = scope,
            .names = &.{},
            .binding_nodes = &local_bindings,
        };

        for (fields) |field| {
            const value = try self.lowerExprInScope(field.value, &record_scope);
            try lowered_fields.append(self.arena, .{
                .name = try self.arena.dupe(u8, field.name.text),
                .value = value,
            });
            try local_bindings.put(self.arena, field.name.text, value);
        }

        return try self.addNode(span, .{ .record = try lowered_fields.toOwnedSlice(self.arena) });
    }

    fn lowerForm(self: *Lowerer, form: *hir.Form, scope: ?*const Scope) LowerError!NodeId {
        return switch (form.kind) {
            .text => try self.lowerTextForm(form, scope),
            .list_dynamic => try self.lowerListForm(form, .dynamic, scope),
            .list_static => try self.lowerListForm(form, .static, scope),
            .bits_dynamic => try self.lowerListForm(form, .bits_dynamic, scope),
            .bits_static => try self.lowerListForm(form, .bits_static, scope),
            .bytes_dynamic => try self.lowerListForm(form, .bytes_dynamic, scope),
            .bytes_static => try self.lowerListForm(form, .bytes_static, scope),
            .memory_dynamic => try self.lowerListForm(form, .memory_dynamic, scope),
            .memory_static => try self.lowerListForm(form, .memory_static, scope),
            .block => try self.lowerBlockForm(form, scope),
            .when => try self.lowerWhenForm(form, scope),
            .while_ => try self.lowerWhileForm(form, scope),
            .latest => try self.lowerLatestForm(form, scope),
            .then => try self.lowerThenForm(form, scope),
            .hold => try self.lowerHoldForm(form, scope),
            .link => try self.lowerLinkForm(form, scope),
            else => self.fail(form.span, "flow slice does not yet support this Boon form"),
        };
    }

    fn lowerHoldForm(self: *Lowerer, form: *hir.Form, parent_scope: ?*const Scope) LowerError!NodeId {
        if (form.bare_args.len != 1) return self.fail(form.span, "HOLD expects exactly one bare state name");
        if (form.arguments.len != 2) return self.fail(form.span, "HOLD expects an initial input and a brace body");
        if (form.arguments[1] != .sequence or form.arguments[1].sequence.delimiter != .braces) {
            return self.fail(form.span, "HOLD expects a brace body");
        }

        const state_name = try self.arena.dupe(u8, form.bare_args[0].text);
        const local_names = try self.arena.alloc([]const u8, 1);
        local_names[0] = state_name;
        const scope = Scope{
            .parent = parent_scope,
            .names = local_names,
        };

        const initial = try self.lowerExprInScope(form.arguments[0], parent_scope);

        var updates: std.ArrayList(NodeId) = .empty;
        defer updates.deinit(self.arena);
        for (form.arguments[1].sequence.items) |item| {
            const expr = switch (item) {
                .expr => |expr| expr,
                .binding => return self.fail(form.span, "HOLD body does not support bindings in this flow slice"),
            };
            const update = try self.lowerExprInScope(expr, &scope);
            try updates.append(self.arena, update);
        }

        self.stateful_count += 1;
        return try self.addNode(form.span, .{ .hold = .{
            .state_name = state_name,
            .initial = initial,
            .updates = try updates.toOwnedSlice(self.arena),
        } });
    }

    fn lowerTextForm(self: *Lowerer, form: *hir.Form, scope: ?*const Scope) LowerError!NodeId {
        if (form.arguments.len != 1 or form.arguments[0] != .sequence or form.arguments[0].sequence.delimiter != .braces) {
            return self.fail(form.span, "TEXT expects a single brace body");
        }

        var parts: std.ArrayList(NodeId) = .empty;
        defer parts.deinit(self.arena);

        for (form.arguments[0].sequence.items) |item| {
            switch (item) {
                .expr => |expr| try parts.append(self.arena, try self.lowerExprInScope(expr, scope)),
                .binding => return self.fail(form.span, "TEXT body does not support bindings in flow slice"),
            }
        }

        return try self.addNode(form.span, .{ .text = try parts.toOwnedSlice(self.arena) });
    }

    fn lowerListForm(self: *Lowerer, form: *hir.Form, kind: ListKind, scope: ?*const Scope) LowerError!NodeId {
        const body = blk: {
            if (form.arguments.len == 1 and form.arguments[0] == .sequence and form.arguments[0].sequence.delimiter == .braces) {
                break :blk form.arguments[0].sequence;
            }
            if (form.arguments.len == 2 and
                (form.arguments[0] == .sequence and form.arguments[0].sequence.delimiter == .brackets or form.arguments[0] == .record) and
                form.arguments[1] == .sequence and
                form.arguments[1].sequence.delimiter == .braces)
            {
                break :blk form.arguments[1].sequence;
            }
            return self.fail(form.span, "LIST expects a brace body, with an optional fixed-size bracket prefix");
        };

        var items: std.ArrayList(NodeId) = .empty;
        defer items.deinit(self.arena);

        for (body.items) |item| {
            switch (item) {
                .expr => |expr| try items.append(self.arena, try self.lowerExprInScope(expr, scope)),
                .binding => return self.fail(form.span, "LIST body does not support bindings in flow slice"),
            }
        }

        return try self.addNode(form.span, .{ .list = .{
            .kind = kind,
            .items = try items.toOwnedSlice(self.arena),
        } });
    }

    fn lowerBlockForm(self: *Lowerer, form: *hir.Form, parent_scope: ?*const Scope) LowerError!NodeId {
        if (form.arguments.len != 1 or form.arguments[0] != .sequence or form.arguments[0].sequence.delimiter != .braces) {
            return self.fail(form.span, "BLOCK expects a single brace body");
        }
        const body = form.arguments[0].sequence;
        if (body.items.len == 0) return self.fail(form.span, "BLOCK requires at least one item");

        var local_names: std.ArrayList([]const u8) = .empty;
        defer local_names.deinit(self.arena);
        var bindings: std.ArrayList(BlockBinding) = .empty;
        defer bindings.deinit(self.arena);
        var local_bindings: std.StringHashMapUnmanaged(NodeId) = .empty;

        var scope = Scope{
            .parent = parent_scope,
            .names = &.{},
            .binding_nodes = &local_bindings,
        };

        var result: ?NodeId = null;
        for (body.items, 0..) |item, index| {
            const is_last = index + 1 == body.items.len;
            switch (item) {
                .binding => |binding| {
                    if (is_last) return self.fail(binding.span, "BLOCK requires a final expression result");
                    const value = try self.lowerExprInScope(binding.value, &scope);
                    const name = try self.arena.dupe(u8, binding.name.text);
                    try bindings.append(self.arena, .{ .name = name, .value = value });
                    try local_names.append(self.arena, name);
                    try local_bindings.put(self.arena, binding.name.text, value);
                    scope.names = local_names.items;
                },
                .expr => |expr| {
                    if (!is_last) return self.fail(exprSpan(expr), "BLOCK only supports bindings before the final expression");
                    result = try self.lowerExprInScope(expr, &scope);
                },
            }
        }

        return try self.addNode(form.span, .{ .block = .{
            .bindings = try bindings.toOwnedSlice(self.arena),
            .result = result.?,
        } });
    }

    fn lowerWhenForm(self: *Lowerer, form: *hir.Form, scope: ?*const Scope) LowerError!NodeId {
        if (form.arguments.len != 2) return self.fail(form.span, "WHEN expects an input and a brace arm body");
        if (form.arguments[1] != .sequence or form.arguments[1].sequence.delimiter != .braces) {
            return self.fail(form.span, "WHEN expects a brace arm body");
        }

        var arms: std.ArrayList(WhenArm) = .empty;
        defer arms.deinit(self.arena);

        for (form.arguments[1].sequence.items) |item| {
            const expr = switch (item) {
                .expr => |expr| expr,
                .binding => return self.fail(form.span, "WHEN arm body does not support bindings"),
            };
            try self.appendWhenArmExprs(&arms, expr, scope, "WHEN expects pattern => result arms");
        }
        if (arms.items.len == 0) return self.fail(form.span, "WHEN requires at least one arm");

        return try self.addNode(form.span, .{ .when = .{
            .input = try self.lowerExprInScope(form.arguments[0], scope),
            .arms = try arms.toOwnedSlice(self.arena),
        } });
    }

    fn lowerWhileForm(self: *Lowerer, form: *hir.Form, scope: ?*const Scope) LowerError!NodeId {
        if (form.arguments.len != 2) return self.fail(form.span, "WHILE expects an input and a brace arm body");
        if (form.arguments[1] != .sequence or form.arguments[1].sequence.delimiter != .braces) {
            return self.fail(form.span, "WHILE expects a brace arm body");
        }

        var arms: std.ArrayList(WhenArm) = .empty;
        defer arms.deinit(self.arena);

        for (form.arguments[1].sequence.items) |item| {
            const expr = switch (item) {
                .expr => |expr| expr,
                .binding => return self.fail(form.span, "WHILE arm body does not support bindings"),
            };
            try self.appendWhenArmExprs(&arms, expr, scope, "WHILE expects pattern => result arms");
        }
        if (arms.items.len == 0) return self.fail(form.span, "WHILE requires at least one arm");

        return try self.addNode(form.span, .{ .when = .{
            .input = try self.lowerExprInScope(form.arguments[0], scope),
            .arms = try arms.toOwnedSlice(self.arena),
        } });
    }

    fn appendWhenArmExprs(
        self: *Lowerer,
        arms: *std.ArrayList(WhenArm),
        expr: hir.Expr,
        scope: ?*const Scope,
        error_message: []const u8,
    ) LowerError!void {
        if (isCommaExpr(expr)) return;
        if (!(expr == .binary and expr.binary.operator == .arm_arrow)) {
            return self.fail(exprSpan(expr), error_message);
        }
        var arm_scope_storage = try self.captureScopeForPattern(expr.binary.lhs, scope);
        const arm_scope = if (arm_scope_storage) |*capture_scope| @as(?*const Scope, capture_scope) else scope;
        try arms.append(self.arena, .{
            .pattern = try self.lowerExprInScope(expr.binary.lhs, scope),
            .result = try self.lowerExprInScope(expr.binary.rhs, arm_scope),
        });
    }

    fn lowerLatestForm(self: *Lowerer, form: *hir.Form, scope: ?*const Scope) LowerError!NodeId {
        if (form.arguments.len != 1 or form.arguments[0] != .sequence or form.arguments[0].sequence.delimiter != .braces) {
            return self.fail(form.span, "LATEST expects a single brace body");
        }
        const body = form.arguments[0].sequence;
        if (body.items.len == 0) return self.fail(form.span, "LATEST requires at least one input");

        const first = switch (body.items[0]) {
            .expr => |expr| expr,
            .binding => return self.fail(form.span, "LATEST items must be expressions"),
        };
        const first_node = try self.lowerExprInScope(first, scope);

        var sources: std.ArrayList(NodeId) = .empty;
        defer sources.deinit(self.arena);
        var initial: ?NodeId = null;

        if (isEventNode(self.nodes.items[first_node].kind)) {
            try sources.append(self.arena, first_node);
        } else {
            initial = first_node;
        }

        for (body.items[1..]) |item| {
            switch (item) {
                .expr => |expr| try sources.append(self.arena, try self.lowerExprInScope(expr, scope)),
                .binding => return self.fail(form.span, "LATEST event inputs must be expressions"),
            }
        }

        self.stateful_count += 1;
        return try self.addNode(form.span, .{ .latest = .{
            .initial = initial,
            .sources = try sources.toOwnedSlice(self.arena),
        } });
    }

    fn lowerThenForm(self: *Lowerer, form: *hir.Form, scope: ?*const Scope) LowerError!NodeId {
        if (form.arguments.len != 2) return self.fail(form.span, "THEN expects a piped source and a brace body");
        if (form.arguments[1] != .sequence or form.arguments[1].sequence.delimiter != .braces) {
            return self.fail(form.span, "THEN expects a brace body");
        }
        const body = form.arguments[1].sequence;
        if (body.items.len != 1 or body.items[0] != .expr) {
            return self.fail(form.span, "THEN flow slice expects a single expression body");
        }

        return try self.addNode(form.span, .{ .then_value = .{
            .source = try self.lowerExprInScope(form.arguments[0], scope),
            .value = try self.lowerExprInScope(body.items[0].expr, scope),
        } });
    }

    fn lowerLinkForm(self: *Lowerer, form: *hir.Form, scope: ?*const Scope) LowerError!NodeId {
        if (form.arguments.len != 2) return self.fail(form.span, "SOURCE expects a piped value and a brace target body");
        if (form.arguments[1] != .sequence or form.arguments[1].sequence.delimiter != .braces) {
            return self.fail(form.span, "SOURCE expects a brace target body");
        }
        const body = form.arguments[1].sequence;
        if (body.items.len != 1 or body.items[0] != .expr) {
            return self.fail(form.span, "SOURCE expects a single target expression");
        }
        return try self.addNode(form.span, .{ .linked_value = .{
            .value = try self.lowerExprInScope(form.arguments[0], scope),
            .target = try self.lowerExprInScope(body.items[0].expr, scope),
        } });
    }

    fn lowerCall(self: *Lowerer, span: ast.Span, call: *hir.Call, scope: ?*const Scope) LowerError!NodeId {
        if (call.callee == .symbol) {
            if (self.function_lookup.get(call.callee.symbol.text)) |function_id| {
                return try self.lowerUserCall(span, function_id, call, scope);
            }
        }

        const path = switch (call.callee) {
            .path => |path| try self.renderPath(path.segments),
            .symbol => |symbol| try self.arena.dupe(u8, symbol.text),
            else => return self.fail(span, "flow slice only supports path/symbol callees"),
        };

        var positional: std.ArrayList(NodeId) = .empty;
        defer positional.deinit(self.arena);

        var named: std.ArrayList(NamedArg) = .empty;
        defer named.deinit(self.arena);

        var callback_scope: ?Scope = null;
        if ((std.mem.eql(u8, path, "List/map") or std.mem.eql(u8, path, "List/retain") or std.mem.eql(u8, path, "List/remove")) and call.arguments.len >= 2) {
            switch (call.arguments[1]) {
                .positional => |expr| if (expr == .symbol and expr.symbol.kind == .snake) {
                    const local_name = try self.arena.dupe(u8, expr.symbol.text);
                    const local_names = try self.arena.alloc([]const u8, 1);
                    local_names[0] = local_name;
                    callback_scope = .{
                        .parent = scope,
                        .names = local_names,
                    };
                },
                else => {},
            }
        }

        for (call.arguments) |argument| {
            switch (argument) {
                .positional => |expr| try positional.append(self.arena, try self.lowerExprInScope(expr, scope)),
                .named => |binding| {
                    const named_scope = if (callback_scope) |*callback|
                        if ((std.mem.eql(u8, path, "List/map") and std.mem.eql(u8, binding.name.text, "new")) or
                            (std.mem.eql(u8, path, "List/retain") and std.mem.eql(u8, binding.name.text, "if")) or
                            (std.mem.eql(u8, path, "List/remove") and std.mem.eql(u8, binding.name.text, "on")))
                            @as(?*const Scope, callback)
                        else
                            scope
                    else
                        scope;
                    try named.append(self.arena, .{
                        .name = try self.arena.dupe(u8, binding.name.text),
                        .value = try self.lowerExprInScope(binding.value, named_scope),
                    });
                },
                .spread => return self.fail(span, "flow slice does not support spread arguments"),
            }
        }

        if (std.mem.eql(u8, path, "Math/sum") or
            std.mem.eql(u8, path, "Stream/pulses") or
            std.mem.eql(u8, path, "Stream/skip") or
            std.mem.eql(u8, path, "List/append") or
            std.mem.eql(u8, path, "List/clear") or
            std.mem.eql(u8, path, "List/remove"))
        {
            self.stateful_count += 1;
        }
        return try self.addNode(span, .{ .builtin_call = .{
            .path = path,
            .positional = try positional.toOwnedSlice(self.arena),
            .named = try named.toOwnedSlice(self.arena),
        } });
    }

    fn captureScopeForPattern(self: *Lowerer, pattern: hir.Expr, parent: ?*const Scope) LowerError!?Scope {
        const symbol = switch (pattern) {
            .symbol => |symbol| symbol,
            else => return null,
        };
        if (symbol.kind != .snake or !isCaptureName(symbol.text)) return null;

        const local_name = try self.arena.dupe(u8, symbol.text);
        const local_names = try self.arena.alloc([]const u8, 1);
        local_names[0] = local_name;
        return .{
            .parent = parent,
            .names = local_names,
        };
    }

    fn lowerUserCall(self: *Lowerer, span: ast.Span, function_id: FunctionId, call: *hir.Call, scope: ?*const Scope) LowerError!NodeId {
        var positional: std.ArrayList(NodeId) = .empty;
        defer positional.deinit(self.arena);

        var named: std.ArrayList(NamedArg) = .empty;
        defer named.deinit(self.arena);

        var pass_context: ?NodeId = null;

        for (call.arguments) |argument| {
            switch (argument) {
                .positional => |expr| try positional.append(self.arena, try self.lowerExprInScope(expr, scope)),
                .named => |binding| {
                    if (std.mem.eql(u8, binding.name.text, "PASS")) {
                        pass_context = try self.lowerExprInScope(binding.value, scope);
                    } else {
                        try named.append(self.arena, .{
                            .name = try self.arena.dupe(u8, binding.name.text),
                            .value = try self.lowerExprInScope(binding.value, scope),
                        });
                    }
                },
                .spread => return self.fail(span, "flow slice does not support spread arguments"),
            }
        }

        return try self.addNode(span, .{ .user_call = .{
            .function = function_id,
            .positional = try positional.toOwnedSlice(self.arena),
            .named = try named.toOwnedSlice(self.arena),
            .pass_context = pass_context,
        } });
    }

    fn lowerFunction(self: *Lowerer, form: *hir.Form) LowerError!void {
        const function_id = self.function_lookup.get(form.bare_args[0].text) orelse return self.fail(form.span, "missing FUNCTION header");
        if (form.arguments.len != 2) return self.fail(form.span, "FUNCTION expects parameter and body clauses");
        if (form.arguments[0] != .sequence or form.arguments[0].sequence.delimiter != .parentheses) {
            return self.fail(form.span, "FUNCTION expects a parenthesized parameter list");
        }
        if (form.arguments[1] != .sequence or form.arguments[1].sequence.delimiter != .braces) {
            return self.fail(form.span, "FUNCTION expects a brace body");
        }

        var params: std.ArrayList([]const u8) = .empty;
        defer params.deinit(self.arena);
        for (form.arguments[0].sequence.items) |item| {
            const expr = switch (item) {
                .expr => |expr| expr,
                .binding => return self.fail(form.span, "FUNCTION parameters must be bare names"),
            };
            if (isCommaExpr(expr)) continue;
            const symbol = switch (expr) {
                .symbol => |symbol| symbol,
                else => return self.fail(exprSpan(expr), "FUNCTION parameters must be symbols"),
            };
            try params.append(self.arena, try self.arena.dupe(u8, symbol.text));
        }

        const scope = Scope{
            .parent = null,
            .names = params.items,
        };
        self.functions.items[function_id].params = try params.toOwnedSlice(self.arena);
        self.functions.items[function_id].body = try self.lowerBraceBody(form.arguments[1].sequence, &scope);
    }

    fn lowerBraceBody(self: *Lowerer, sequence: *hir.Sequence, scope: ?*const Scope) LowerError!NodeId {
        if (sequence.items.len == 0) return self.fail(sequence.span, "body requires at least one item");

        var local_names: std.ArrayList([]const u8) = .empty;
        defer local_names.deinit(self.arena);
        var bindings: std.ArrayList(BlockBinding) = .empty;
        defer bindings.deinit(self.arena);
        var local_bindings: std.StringHashMapUnmanaged(NodeId) = .empty;

        var local_scope = Scope{
            .parent = scope,
            .names = &.{},
            .binding_nodes = &local_bindings,
        };

        var result: ?NodeId = null;
        for (sequence.items, 0..) |item, index| {
            const is_last = index + 1 == sequence.items.len;
            switch (item) {
                .binding => |binding| {
                    if (is_last) return self.fail(binding.span, "body requires a final expression result");
                    const value = try self.lowerExprInScope(binding.value, &local_scope);
                    const name = try self.arena.dupe(u8, binding.name.text);
                    try bindings.append(self.arena, .{ .name = name, .value = value });
                    try local_names.append(self.arena, name);
                    try local_bindings.put(self.arena, binding.name.text, value);
                    local_scope.names = local_names.items;
                },
                .expr => |expr| {
                    if (!is_last) return self.fail(exprSpan(expr), "body only supports bindings before the final expression");
                    result = try self.lowerExprInScope(expr, &local_scope);
                },
            }
        }

        if (bindings.items.len == 0) return result.?;
        return try self.addNode(sequence.span, .{ .block = .{
            .bindings = try bindings.toOwnedSlice(self.arena),
            .result = result.?,
        } });
    }

    fn lowerSequenceExpr(self: *Lowerer, sequence: *hir.Sequence, scope: ?*const Scope) LowerError!NodeId {
        if (sequence.delimiter == .braces) {
            var items: std.ArrayList(NodeId) = .empty;
            defer items.deinit(self.arena);
            for (sequence.items) |item| {
                switch (item) {
                    .expr => |expr| try items.append(self.arena, try self.lowerExprInScope(expr, scope)),
                    .binding => return self.fail(sequence.span, "brace sequences with bindings are not supported here"),
                }
            }
            return try self.addNode(sequence.span, .{ .list = .{
                .kind = .dynamic,
                .items = try items.toOwnedSlice(self.arena),
            } });
        }
        if (sequence.delimiter == .brackets) {
            var lowered_fields: std.ArrayList(Field) = .empty;
            defer lowered_fields.deinit(self.arena);
            var local_bindings: std.StringHashMapUnmanaged(NodeId) = .empty;

            var record_scope = Scope{
                .parent = scope,
                .names = &.{},
                .binding_nodes = &local_bindings,
            };

            for (sequence.items) |item| {
                switch (item) {
                    .binding => |binding| {
                        const value = try self.lowerExprInScope(binding.value, &record_scope);
                        const name = try self.arena.dupe(u8, binding.name.text);
                        try lowered_fields.append(self.arena, .{
                            .name = name,
                            .value = value,
                        });
                        try local_bindings.put(self.arena, binding.name.text, value);
                    },
                    .expr => |expr| {
                        if (isCommaExpr(expr)) continue;
                        const spread_value = if (expr == .unary and expr.unary.operator == .spread)
                            try self.lowerExprInScope(expr.unary.operand, &record_scope)
                        else
                            try self.lowerExprInScope(expr, &record_scope);
                        try lowered_fields.append(self.arena, .{
                            .name = "",
                            .value = spread_value,
                        });
                    },
                }
            }

            return try self.addNode(sequence.span, .{ .record = try lowered_fields.toOwnedSlice(self.arena) });
        }
        if (sequence.delimiter == .parentheses) {
            var expr_count: usize = 0;
            var last_expr: ?hir.Expr = null;
            for (sequence.items) |item| {
                switch (item) {
                    .expr => |expr| {
                        if (isCommaExpr(expr)) continue;
                        expr_count += 1;
                        last_expr = expr;
                    },
                    .binding => return self.fail(sequence.span, "parenthesized sequences do not support bindings in flow slice"),
                }
            }
            if (expr_count == 1) return try self.lowerExprInScope(last_expr.?, scope);
        }
        return self.fail(sequence.span, "standalone sequence is not supported in flow slice");
    }

    fn addNode(self: *Lowerer, span: ast.Span, kind: Node.Kind) LowerError!NodeId {
        const node_id: NodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(self.arena, .{
            .span = span,
            .kind = kind,
        });
        return node_id;
    }

    fn addLinkPort(self: *Lowerer, span: ast.Span) LowerError!NodeId {
        self.link_port_count += 1;
        return try self.addNode(span, .{ .link_port = "SOURCE" });
    }

    fn renderPath(self: *Lowerer, segments: []hir.Symbol) LowerError![]const u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.arena);

        for (segments, 0..) |segment, index| {
            if (index != 0) try output.append(self.arena, '/');
            try output.appendSlice(self.arena, segment.text);
        }
        return try output.toOwnedSlice(self.arena);
    }

    fn fail(self: *Lowerer, span: ast.Span, message: []const u8) error{LoweringFailed} {
        self.failure_diag = .{ .message = message, .span = span };
        return error.LoweringFailed;
    }
};

fn exprSpan(expr: hir.Expr) ast.Span {
    return switch (expr) {
        .symbol => |value| value.span,
        .special => |value| value.span,
        .number => |value| value.span,
        .wildcard => |value| value.span,
        .atom => |value| value.span,
        .path => |value| value.span,
        .call => |value| value.span,
        .access => |value| value.span,
        .unary => |value| value.span,
        .binary => |value| value.span,
        .sequence => |value| value.span,
        .record => |value| value.span,
        .form => |value| value.span,
    };
}

fn findNamed(named: []const NamedArg, name: []const u8) ?NodeId {
    for (named) |arg| {
        if (std.mem.eql(u8, arg.name, name)) return arg.value;
    }
    return null;
}

fn isCommaExpr(expr: hir.Expr) bool {
    return switch (expr) {
        .atom => |literal| std.mem.eql(u8, literal.text, ","),
        else => false,
    };
}

fn isEventNode(kind: Node.Kind) bool {
    return switch (kind) {
        .then_value, .latest, .hold => true,
        .builtin_call => |call| std.mem.eql(u8, call.path, "Stream/skip") or std.mem.eql(u8, call.path, "Stream/pulses"),
        else => false,
    };
}

fn isCaptureName(text: []const u8) bool {
    if (text.len == 0) return false;
    if (std.mem.eql(u8, text, "__")) return false;
    return switch (text[0]) {
        'a'...'z', '_' => true,
        else => false,
    };
}

test "lowers counter to flow ir" {
    const source = @embedFile("../examples/upstream/counter/counter.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 3), flowed.bindings.len);
    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expectEqual(@as(usize, 1), flowed.link_port_count);
    try std.testing.expect(flowed.stateful_count >= 2);
}

test "lowers interval to flow ir" {
    const source = @embedFile("../examples/upstream/interval/interval.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected interval flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 1), flowed.bindings.len);
    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expect(flowed.stateful_count >= 1);
}

test "lowers block and when flow forms" {
    const source =
        \\document: Document/new(root: BLOCK {
        \\    value: 2
        \\    value |> WHEN {
        \\        1 => TEXT { no }
        \\        2 => TEXT { yes }
        \\        __ => TEXT { fallback }
        \\    }
        \\})
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected block/when flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 1), flowed.bindings.len);
    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expect(flowed.nodes.len >= 5);
}

test "lowers block-local event sources to concrete link nodes" {
    const source =
        \\FUNCTION make_evented() {
        \\    BLOCK {
        \\        display_element: [event: [double_click: SOURCE]]
        \\        display_element.event.double_click
        \\            |> THEN { 1 }
        \\            |> SOURCE { edit_started }
        \\    }
        \\}
        \\
        \\edit_started: SOURCE
        \\document: make_evented()
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected block-local event flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    const rendered = try renderAlloc(std.testing.allocator, &flowed);
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "local(display_element)") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "then(") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "linked(") != null);
}

test "lowers counter_hold to flow ir" {
    const source = @embedFile("../examples/upstream/counter_hold/counter_hold.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected counter_hold flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 3), flowed.bindings.len);
    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expectEqual(@as(usize, 1), flowed.link_port_count);
    try std.testing.expect(flowed.stateful_count >= 1);

    var found_hold = false;
    for (flowed.nodes) |node| {
        if (node.kind == .hold) {
            found_hold = true;
            try std.testing.expectEqualStrings("counter", node.kind.hold.state_name);
            try std.testing.expectEqual(@as(usize, 1), node.kind.hold.updates.len);
        }
    }
    try std.testing.expect(found_hold);
}

test "lowers interval_hold to flow ir" {
    const source = @embedFile("../examples/upstream/interval_hold/interval_hold.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected interval_hold flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 3), flowed.bindings.len);
    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expect(flowed.stateful_count >= 2);

    var found_skip = false;
    for (flowed.nodes) |node| {
        if (node.kind == .builtin_call and std.mem.eql(u8, node.kind.builtin_call.path, "Stream/skip")) {
            found_skip = true;
            try std.testing.expectEqual(@as(usize, 1), node.kind.builtin_call.positional.len);
            try std.testing.expect(findNamed(node.kind.builtin_call.named, "count") != null);
        }
    }
    try std.testing.expect(found_skip);
}

test "lowers complex_counter with user functions and pass context" {
    const source = @embedFile("../examples/upstream/complex_counter/complex_counter.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected complex_counter flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 2), flowed.functions.len);
    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);

    var found_user_call = false;
    var found_linked = false;
    for (flowed.nodes) |node| switch (node.kind) {
        .user_call => found_user_call = true,
        .linked_value => found_linked = true,
        else => {},
    };
    try std.testing.expect(found_user_call);
    try std.testing.expect(found_linked);
}

test "lowers while example with live branch arms" {
    const source = @embedFile("../examples/upstream/while/while.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected while flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);

    var found_when = false;
    for (flowed.nodes) |node| {
        if (node.kind == .when) found_when = true;
    }
    try std.testing.expect(found_when);
}

test "lowers temperature_converter with parenthesized math and captures" {
    const source = @embedFile("../examples/upstream/temperature_converter/temperature_converter.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected temperature_converter flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expect(flowed.stateful_count >= 3);
}

test "lowers todo_mvc with negative style literals" {
    const source = @embedFile("../examples/upstream/todo_mvc/todo_mvc.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected todo_mvc flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expect(flowed.stateful_count >= 1);
}

test "lowers shopping_list with list state and key input" {
    const source = @embedFile("../examples/upstream/shopping_list/shopping_list.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected shopping_list flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expect(flowed.stateful_count >= 2);
}

test "lowers static list and bits forms to flow ir" {
    const source =
        \\list_out: LIST[__] { 1 2 }
        \\bits_out: BITS[__] { 1 2 }
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected static collection flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 2), flowed.bindings.len);

    var list_static_count: usize = 0;
    var bits_static_count: usize = 0;
    for (flowed.nodes) |node| {
        if (node.kind == .list) switch (node.kind.list.kind) {
            .static => list_static_count += 1,
            .bits_static => bits_static_count += 1,
            else => {},
        };
    }
    try std.testing.expectEqual(@as(usize, 1), list_static_count);
    try std.testing.expectEqual(@as(usize, 1), bits_static_count);
}

test "lowers scene root when document binding is absent" {
    const source =
        \\scene: Scene/new(root: TEXT { Hello })
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected scene-root flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("scene", flowed.bindings[flowed.root_binding.?].name);
}

test "lowers list_retain_reactive with raw text punctuation and retain filters" {
    const source = @embedFile("../examples/upstream/list_retain_reactive/list_retain_reactive.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected list_retain_reactive flow failure: {s}\n", .{failure.message});
            return error.UnexpectedFlowFailure;
        },
    };
    var flowed = document;
    defer flowed.deinit();

    try std.testing.expectEqual(@as(usize, 2), flowed.bindings.len);
    try std.testing.expect(flowed.root_binding != null);
    try std.testing.expectEqualStrings("document", flowed.bindings[flowed.root_binding.?].name);
    try std.testing.expectEqual(@as(usize, 1), flowed.link_port_count);
    try std.testing.expect(flowed.nodes.len >= 80);
}
