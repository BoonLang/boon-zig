const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const parser = @import("parser.zig");

const LowerError = std.mem.Allocator.Error || error{LoweringFailed};

pub const Outcome = union(enum) {
    ok: Document,
    err: diag.Diagnostic,
};

pub const SymbolKind = enum {
    snake,
    pascal,
    keyword,
};

pub const Symbol = struct {
    text: []const u8,
    kind: SymbolKind,
    span: ast.Span,
};

pub const Literal = struct {
    text: []const u8,
    span: ast.Span,
};

pub const SpecialKind = enum {
    pass_ref,
    passed_ref,
    link_ref,
    skip_ref,
    drain_reserved,
};

pub const Special = struct {
    kind: SpecialKind,
    span: ast.Span,
};

pub const Item = union(enum) {
    binding: *Binding,
    expr: Expr,
};

pub const Binding = struct {
    name: Symbol,
    value: Expr,
    span: ast.Span,
};

pub const Expr = union(enum) {
    symbol: Symbol,
    special: Special,
    number: Literal,
    wildcard: Literal,
    atom: Literal,
    path: *Path,
    call: *Call,
    access: *Access,
    unary: *Unary,
    binary: *Binary,
    sequence: *Sequence,
    record: *Record,
    form: *Form,
};

pub const Path = struct {
    segments: []Symbol,
    span: ast.Span,
};

pub const Argument = union(enum) {
    positional: Expr,
    named: *Binding,
    spread: Expr,
};

pub const CallKind = enum {
    call,
    tagged_value,
};

pub const Call = struct {
    kind: CallKind,
    callee: Expr,
    arguments: []Argument,
    span: ast.Span,
};

pub const Access = struct {
    kind: ast.AccessKind,
    target: Expr,
    field: Symbol,
    span: ast.Span,
};

pub const Unary = struct {
    operator: ast.UnaryOp,
    operand: Expr,
    span: ast.Span,
};

pub const Binary = struct {
    operator: ast.BinaryOp,
    lhs: Expr,
    rhs: Expr,
    span: ast.Span,
};

pub const Sequence = struct {
    delimiter: ast.Delimiter,
    items: []Item,
    span: ast.Span,
};

pub const Record = struct {
    fields: []*Binding,
    span: ast.Span,
};

pub const FormKind = enum {
    function_decl,
    hold,
    latest,
    then,
    when,
    while_,
    block,
    text,
    link,
    list_dynamic,
    list_static,
    bits_dynamic,
    bits_static,
    bytes_dynamic,
    bytes_static,
    memory_dynamic,
    memory_static,
    drain_reserved,
    generic_keyword,
};

pub const Form = struct {
    kind: FormKind,
    keyword: Symbol,
    bare_args: []Symbol,
    arguments: []Expr,
    span: ast.Span,
};

pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    items: []Item,
    source_len: usize,
    definition_count: usize,
    expr_count: usize,
    call_count: usize,
    form_count: usize,

    pub fn deinit(self: *Document) void {
        self.arena.deinit();
    }
};

pub fn renderAlloc(allocator: std.mem.Allocator, document: *const Document) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    const writer = output.writer(allocator);
    try writer.print(
        "stats definitions={d} exprs={d} calls={d} forms={d}\n",
        .{ document.definition_count, document.expr_count, document.call_count, document.form_count },
    );
    var renderer = Renderer{ .writer = &writer };
    for (document.items) |item| {
        try renderer.renderItem(item, 0, 3);
        try writer.writeByte('\n');
    }

    return try output.toOwnedSlice(allocator);
}

pub const Options = struct {};

pub fn lowerAlloc(allocator: std.mem.Allocator, source: []const u8) !Outcome {
    return lowerAllocWithOptions(allocator, source, .{});
}

pub fn lowerAllocWithOptions(allocator: std.mem.Allocator, source: []const u8, options: Options) !Outcome {
    _ = options;
    const parsed = try parser.parseAlloc(allocator, source);
    const parsed_document = switch (parsed) {
        .ok => |document| document,
        .err => |failure| return .{ .err = failure },
    };
    var ast_document = parsed_document;
    defer ast_document.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var lowerer = Lowerer{
        .source = source,
        .arena = arena.allocator(),
    };

    const items = lowerer.lowerItems(ast_document.root.items) catch |err| switch (err) {
        error.LoweringFailed => return .{ .err = lowerer.failure_diag.? },
        else => return err,
    };
    const document: Document = .{
        .arena = arena,
        .items = items,
        .source_len = source.len,
        .definition_count = lowerer.definition_count,
        .expr_count = lowerer.expr_count,
        .call_count = lowerer.call_count,
        .form_count = lowerer.form_count,
    };
    return .{ .ok = document };
}

const Lowerer = struct {
    source: []const u8,
    arena: std.mem.Allocator,
    definition_count: usize = 0,
    expr_count: usize = 0,
    call_count: usize = 0,
    form_count: usize = 0,
    failure_diag: ?diag.Diagnostic = null,

    fn lowerItems(self: *Lowerer, exprs: []ast.Expr) LowerError![]Item {
        var items: std.ArrayList(Item) = .empty;
        defer items.deinit(self.arena);

        for (exprs) |expr| {
            try items.append(self.arena, try self.lowerItem(expr));
        }

        return try items.toOwnedSlice(self.arena);
    }

    fn lowerItem(self: *Lowerer, expr: ast.Expr) LowerError!Item {
        if (expr == .binary and expr.binary.operator == .bind) {
            const binding = try self.lowerBinding(expr.binary);
            return .{ .binding = binding };
        }
        return .{ .expr = try self.lowerExpr(expr) };
    }

    fn lowerBinding(self: *Lowerer, binding: *ast.Binary) LowerError!*Binding {
        const name = try self.bindingName(binding.lhs);
        const lowered = try self.arena.create(Binding);
        lowered.* = .{
            .name = name,
            .value = try self.lowerExpr(binding.rhs),
            .span = binding.span,
        };
        self.definition_count += 1;
        return lowered;
    }

    fn bindingName(self: *Lowerer, expr: ast.Expr) LowerError!Symbol {
        return switch (expr) {
            .token => |token| switch (token.kind) {
                .snake_identifier => try self.symbolFromToken(token, .snake),
                .pascal_identifier => try self.symbolFromToken(token, .pascal),
                .keyword => try self.symbolFromToken(token, .keyword),
                else => return self.fail(token.span, "expected binding name"),
            },
            else => self.fail(ast.exprSpan(expr), "expected binding name"),
        };
    }

    fn lowerExpr(self: *Lowerer, expr: ast.Expr) LowerError!Expr {
        self.expr_count += 1;
        return switch (expr) {
            .token => |token| try self.lowerTokenExpr(token),
            .group => |group| try self.lowerGroupExpr(group),
            .path => |path| try self.lowerPathExpr(path),
            .apply => try self.lowerApplyExpr(expr),
            .access => |access| try self.lowerAccessExpr(access),
            .unary => |unary| try self.lowerUnaryExpr(unary),
            .binary => |binary| try self.lowerBinaryExpr(binary),
        };
    }

    fn lowerTokenExpr(self: *Lowerer, token: ast.Token) LowerError!Expr {
        return switch (token.kind) {
            .snake_identifier => .{ .symbol = try self.symbolFromToken(token, .snake) },
            .pascal_identifier => .{ .symbol = try self.symbolFromToken(token, .pascal) },
            .keyword => {
                const text = self.source[token.span.start..token.span.end];
                if (std.mem.eql(u8, text, "PASS")) return .{ .special = .{ .kind = .pass_ref, .span = token.span } };
                if (std.mem.eql(u8, text, "PASSED")) return .{ .special = .{ .kind = .passed_ref, .span = token.span } };
                if (std.mem.eql(u8, text, "SOURCE") or std.mem.eql(u8, text, "LINK")) return .{ .special = .{ .kind = .link_ref, .span = token.span } };
                if (std.mem.eql(u8, text, "SKIP")) return .{ .special = .{ .kind = .skip_ref, .span = token.span } };
                if (std.mem.eql(u8, text, "DRAIN")) return .{ .special = .{ .kind = .drain_reserved, .span = token.span } };
                return .{ .symbol = try self.symbolFromToken(token, .keyword) };
            },
            .numeric_literal => .{ .number = try self.literalFromToken(token) },
            .wildcard => .{ .wildcard = try self.literalFromToken(token) },
            else => .{ .atom = try self.literalFromToken(token) },
        };
    }

    fn lowerGroupExpr(self: *Lowerer, group: *ast.Group) LowerError!Expr {
        if (group.delimiter == .brackets and self.isRecordLike(group.items)) {
            const record = try self.arena.create(Record);
            record.* = .{
                .fields = try self.lowerRecordFields(group.items),
                .span = group.span,
            };
            return .{ .record = record };
        }

        const sequence = try self.arena.create(Sequence);
        sequence.* = .{
            .delimiter = group.delimiter,
            .items = try self.lowerItems(group.items),
            .span = group.span,
        };
        return .{ .sequence = sequence };
    }

    fn lowerPathExpr(self: *Lowerer, path: *ast.Path) LowerError!Expr {
        const lowered = try self.arena.create(Path);
        const segments = try self.arena.alloc(Symbol, path.segments.len);
        for (path.segments, 0..) |segment, index| {
            segments[index] = switch (segment.kind) {
                .snake_identifier => try self.symbolFromToken(segment, .snake),
                .pascal_identifier => try self.symbolFromToken(segment, .pascal),
                .keyword => try self.symbolFromToken(segment, .keyword),
                else => return self.fail(segment.span, "invalid module path segment"),
            };
        }
        lowered.* = .{
            .segments = segments,
            .span = path.span,
        };
        return .{ .path = lowered };
    }

    fn lowerApplyExpr(self: *Lowerer, expr: ast.Expr) LowerError!Expr {
        var flattened: std.ArrayList(ast.Expr) = .empty;
        defer flattened.deinit(self.arena);

        const head = try self.flattenApply(expr, &flattened);
        if (head == .token and head.token.kind == .keyword) {
            return try self.lowerFormExpr(head.token, try flattened.toOwnedSlice(self.arena), null, ast.exprSpan(expr));
        }
        return try self.lowerCallExprWithPiped(head, try flattened.toOwnedSlice(self.arena), null, ast.exprSpan(expr));
    }

    fn flattenApply(self: *Lowerer, expr: ast.Expr, args: *std.ArrayList(ast.Expr)) LowerError!ast.Expr {
        return switch (expr) {
            .apply => |apply| blk: {
                const head = try self.flattenApply(apply.head, args);
                for (apply.arguments) |argument| try args.append(self.arena, argument);
                break :blk head;
            },
            else => expr,
        };
    }

    fn lowerCallExpr(self: *Lowerer, head: ast.Expr, arguments: []ast.Expr, span: ast.Span) LowerError!Expr {
        return self.lowerCallExprWithPiped(head, arguments, null, span);
    }

    fn lowerCallExprWithPiped(self: *Lowerer, head: ast.Expr, arguments: []ast.Expr, piped: ?Expr, span: ast.Span) LowerError!Expr {
        var lowered_arguments: std.ArrayList(Argument) = .empty;
        defer lowered_arguments.deinit(self.arena);

        if (piped) |input| {
            try lowered_arguments.append(self.arena, .{ .positional = input });
        }

        for (arguments) |argument| {
            if (argument == .group and (argument.group.delimiter == .parentheses or argument.group.delimiter == .brackets)) {
                try self.lowerCallGroupArguments(argument.group.items, &lowered_arguments);
            } else {
                try lowered_arguments.append(self.arena, .{ .positional = try self.lowerExpr(argument) });
            }
        }

        const call = try self.arena.create(Call);
        call.* = .{
            .kind = self.callKind(head),
            .callee = try self.lowerExpr(head),
            .arguments = try lowered_arguments.toOwnedSlice(self.arena),
            .span = span,
        };
        self.call_count += 1;
        return .{ .call = call };
    }

    fn lowerCallGroupArguments(self: *Lowerer, exprs: []ast.Expr, arguments: *std.ArrayList(Argument)) LowerError!void {
        for (exprs) |expr| {
            if (isCommaTokenExpr(expr)) continue;
            const item = try self.lowerItem(expr);
            switch (item) {
                .binding => |binding| try arguments.append(self.arena, .{ .named = binding }),
                .expr => |lowered| switch (lowered) {
                    .unary => |unary| {
                        if (unary.operator == .spread) {
                            try arguments.append(self.arena, .{ .spread = unary.operand });
                        } else {
                            try arguments.append(self.arena, .{ .positional = lowered });
                        }
                    },
                    else => try arguments.append(self.arena, .{ .positional = lowered }),
                },
            }
        }
    }

    fn callKind(self: *Lowerer, head: ast.Expr) CallKind {
        _ = self;
        return switch (head) {
            .token => |token| switch (token.kind) {
                .pascal_identifier => .tagged_value,
                else => .call,
            },
            .path => |path| switch (path.segments[path.segments.len - 1].kind) {
                .pascal_identifier => .tagged_value,
                else => .call,
            },
            else => .call,
        };
    }

    fn lowerAccessExpr(self: *Lowerer, access: *ast.Access) LowerError!Expr {
        const lowered = try self.arena.create(Access);
        lowered.* = .{
            .kind = access.kind,
            .target = try self.lowerExpr(access.target),
            .field = switch (access.field.kind) {
                .snake_identifier => try self.symbolFromToken(access.field, .snake),
                .pascal_identifier => try self.symbolFromToken(access.field, .pascal),
                .keyword => try self.symbolFromToken(access.field, .keyword),
                else => return self.fail(access.field.span, "invalid field access"),
            },
            .span = access.span,
        };
        return .{ .access = lowered };
    }

    fn lowerUnaryExpr(self: *Lowerer, unary: *ast.Unary) LowerError!Expr {
        const lowered = try self.arena.create(Unary);
        lowered.* = .{
            .operator = unary.operator,
            .operand = try self.lowerExpr(unary.operand),
            .span = unary.span,
        };
        return .{ .unary = lowered };
    }

    fn lowerBinaryExpr(self: *Lowerer, binary: *ast.Binary) LowerError!Expr {
        if (binary.operator == .pipe_forward) {
            return try self.lowerPipeExpr(binary);
        }

        const lowered = try self.arena.create(Binary);
        lowered.* = .{
            .operator = binary.operator,
            .lhs = try self.lowerExpr(binary.lhs),
            .rhs = try self.lowerExpr(binary.rhs),
            .span = binary.span,
        };
        return .{ .binary = lowered };
    }

    fn lowerPipeExpr(self: *Lowerer, binary: *ast.Binary) LowerError!Expr {
        const piped = try self.lowerExpr(binary.lhs);
        return try self.lowerPipeTarget(binary.rhs, piped, binary.span);
    }

    fn lowerPipeTarget(self: *Lowerer, target: ast.Expr, piped: Expr, span: ast.Span) LowerError!Expr {
        return switch (target) {
            .apply => {
                var flattened: std.ArrayList(ast.Expr) = .empty;
                defer flattened.deinit(self.arena);

                const head = try self.flattenApply(target, &flattened);
                if (head == .token and head.token.kind == .keyword) {
                    return try self.lowerFormExpr(head.token, try flattened.toOwnedSlice(self.arena), piped, span);
                }
                return try self.lowerCallExprWithPiped(head, try flattened.toOwnedSlice(self.arena), piped, span);
            },
            .path => try self.lowerCallExprWithPiped(target, &.{}, piped, span),
            .access => |access| {
                if (access.target == .token and access.target.token.kind == .dot) {
                    const lowered = try self.arena.create(Access);
                    lowered.* = .{
                        .kind = access.kind,
                        .target = piped,
                        .field = switch (access.field.kind) {
                            .snake_identifier => try self.symbolFromToken(access.field, .snake),
                            .pascal_identifier => try self.symbolFromToken(access.field, .pascal),
                            .keyword => try self.symbolFromToken(access.field, .keyword),
                            else => return self.fail(access.field.span, "invalid field access"),
                        },
                        .span = span,
                    };
                    return .{ .access = lowered };
                }
                return try self.lowerCallExprWithPiped(target, &.{}, piped, span);
            },
            .token => |token| switch (token.kind) {
                .snake_identifier, .pascal_identifier => try self.lowerCallExprWithPiped(target, &.{}, piped, span),
                .keyword => try self.lowerFormExpr(token, &.{}, piped, span),
                else => self.fail(ast.exprSpan(target), "unsupported pipe target"),
            },
            else => self.fail(ast.exprSpan(target), "unsupported pipe target"),
        };
    }

    fn lowerFormExpr(self: *Lowerer, keyword_token: ast.Token, arguments: []ast.Expr, piped: ?Expr, span: ast.Span) LowerError!Expr {
        var bare_args: std.ArrayList(Symbol) = .empty;
        defer bare_args.deinit(self.arena);

        var lowered_args: std.ArrayList(Expr) = .empty;
        defer lowered_args.deinit(self.arena);

        if (piped) |input| {
            try lowered_args.append(self.arena, input);
        }

        const keyword_text = self.source[keyword_token.span.start..keyword_token.span.end];

        for (arguments) |argument| {
            if (argument == .token and isBareFormArgToken(argument.token.kind)) {
                try bare_args.append(self.arena, try self.formBareArg(argument.token));
            } else if (std.mem.eql(u8, keyword_text, "TEXT") and argument == .group and argument.group.delimiter == .braces) {
                try lowered_args.append(self.arena, try self.lowerRawTextBody(argument.group, textHashCount(self.source, keyword_token.span.end, argument.group.span.start)));
            } else {
                try lowered_args.append(self.arena, try self.lowerExpr(argument));
            }
        }

        const lowered = try self.arena.create(Form);
        lowered.* = .{
            .kind = formKindFor(keyword_text, lowered_args.items),
            .keyword = try self.symbolFromToken(keyword_token, .keyword),
            .bare_args = try bare_args.toOwnedSlice(self.arena),
            .arguments = try lowered_args.toOwnedSlice(self.arena),
            .span = span,
        };
        self.form_count += 1;
        return .{ .form = lowered };
    }

    fn lowerRawTextBody(self: *Lowerer, group: *ast.Group, hash_count: usize) LowerError!Expr {
        var items: std.ArrayList(Item) = .empty;
        defer items.deinit(self.arena);

        const body_start = group.span.start + 1;
        const body_end = group.span.end - 1;
        var cursor = body_start;
        const marker = if (hash_count == 0)
            "{"
        else if (hash_count == 1)
            "#{"
        else
            "__multi_hash_marker__";

        if (hash_count <= 1) {
            var search_start = body_start;
            while (search_start < body_end) {
                const relative = std.mem.indexOfPos(u8, self.source[body_start..body_end], search_start - body_start, marker) orelse break;
                const absolute_start = body_start + relative;

                try self.appendRawTextLiteral(&items, cursor, absolute_start);

                const value_start = absolute_start + marker.len;
                const close_relative = std.mem.indexOfScalarPos(u8, self.source[value_start..body_end], 0, '}') orelse {
                    return self.fail(group.span, "unterminated TEXT interpolation");
                };
                const close_index = value_start + close_relative;

                try items.append(self.arena, .{ .expr = try self.lowerInlineTextExpr(ast.Span.init(value_start, close_index)) });
                cursor = close_index + 1;
                search_start = close_index + 1;
            }
        } else {
            var search_start = body_start;
            while (search_start + hash_count + 1 <= body_end) {
                const maybe_start = findHashedInterpolation(self.source[body_start..body_end], search_start - body_start, hash_count) orelse break;
                const absolute_start = body_start + maybe_start;

                try self.appendRawTextLiteral(&items, cursor, absolute_start);

                const value_start = absolute_start + hash_count + 1;
                const close_relative = std.mem.indexOfScalarPos(u8, self.source[value_start..body_end], 0, '}') orelse {
                    return self.fail(group.span, "unterminated TEXT interpolation");
                };
                const close_index = value_start + close_relative;

                try items.append(self.arena, .{ .expr = try self.lowerInlineTextExpr(ast.Span.init(value_start, close_index)) });
                cursor = close_index + 1;
                search_start = close_index + 1;
            }
        }

        try self.appendRawTextLiteral(&items, cursor, body_end);

        const sequence = try self.arena.create(Sequence);
        sequence.* = .{
            .delimiter = .braces,
            .items = try items.toOwnedSlice(self.arena),
            .span = group.span,
        };
        return .{ .sequence = sequence };
    }

    fn appendRawTextLiteral(self: *Lowerer, items: *std.ArrayList(Item), start: usize, end: usize) LowerError!void {
        const raw_chunk = self.source[start..end];
        const fully_trimmed = std.mem.trim(u8, raw_chunk, " \n\r\t");
        if (fully_trimmed.len == 0) {
            const only_spaces = std.mem.indexOfNone(u8, raw_chunk, " ") == null;
            if (!only_spaces) return;
            try items.append(self.arena, .{ .expr = .{ .atom = .{
                .text = try self.arena.dupe(u8, raw_chunk),
                .span = ast.Span.init(start, end),
            } } });
            return;
        }

        const chunk = fully_trimmed;
        try items.append(self.arena, .{ .expr = .{ .atom = .{
            .text = try self.arena.dupe(u8, chunk),
            .span = ast.Span.init(start, end),
        } } });
    }

    fn lowerInlineTextExpr(self: *Lowerer, original_span: ast.Span) LowerError!Expr {
        const source = self.source[original_span.start..original_span.end];
        const inner = std.mem.trim(u8, source, " \n\r\t");
        if (inner.len == 0) return self.fail(original_span, "TEXT interpolation requires an expression");

        var offset = original_span.start;
        while (offset < original_span.end) : (offset += 1) {
            switch (self.source[offset]) {
                ' ', '\n', '\r', '\t' => continue,
                else => break,
            }
        }

        const parsed = parser.parseAlloc(self.arena, inner) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                const failure = parser.diagnosticForParseFailure(inner, err);
                self.failure_diag = .{
                    .message = failure.message,
                    .span = shiftSpan(failure.span, offset),
                };
                return error.LoweringFailed;
            },
        };
        const parsed_document = switch (parsed) {
            .ok => |document| document,
            .err => |failure| {
                self.failure_diag = .{
                    .message = failure.message,
                    .span = shiftSpan(failure.span, offset),
                };
                return error.LoweringFailed;
            },
        };
        var ast_document = parsed_document;
        defer ast_document.deinit();

        if (ast_document.root.items.len != 1) return self.fail(original_span, "TEXT interpolation requires a single expression");

        var nested = Lowerer{
            .source = inner,
            .arena = self.arena,
        };
        const lowered = nested.lowerItem(ast_document.root.items[0]) catch |err| switch (err) {
            error.LoweringFailed => {
                const failure = nested.failure_diag orelse diag.Diagnostic{
                    .message = "failed to lower TEXT interpolation",
                    .span = ast.Span.init(0, inner.len),
                };
                self.failure_diag = .{
                    .message = failure.message,
                    .span = shiftSpan(failure.span, offset),
                };
                return error.LoweringFailed;
            },
            else => return err,
        };
        const expr = switch (lowered) {
            .expr => |expr| expr,
            .binding => return self.fail(original_span, "TEXT interpolation requires an expression"),
        };
        if (!isAllowedTextInterpolationExpr(expr)) {
            return self.fail(original_span, "TEXT interpolation only allows names and field access; use BLOCK for expressions");
        }
        return rebaseExpr(expr, offset);
    }

    fn isAllowedTextInterpolationExpr(expr: Expr) bool {
        return switch (expr) {
            .symbol => true,
            .access => |access| isAllowedTextInterpolationExpr(access.target),
            else => false,
        };
    }

    fn formBareArg(self: *Lowerer, token: ast.Token) LowerError!Symbol {
        return switch (token.kind) {
            .snake_identifier => try self.symbolFromToken(token, .snake),
            .pascal_identifier => try self.symbolFromToken(token, .pascal),
            .keyword => try self.symbolFromToken(token, .keyword),
            else => self.fail(token.span, "invalid bare form argument"),
        };
    }

    fn isRecordLike(self: *Lowerer, exprs: []ast.Expr) bool {
        _ = self;
        for (exprs) |expr| {
            if (isCommaTokenExpr(expr)) continue;
            if (!(expr == .binary and expr.binary.operator == .bind)) return false;
        }
        return true;
    }

    fn lowerRecordFields(self: *Lowerer, exprs: []ast.Expr) LowerError![]*Binding {
        var fields: std.ArrayList(*Binding) = .empty;
        defer fields.deinit(self.arena);

        for (exprs) |expr| {
            if (isCommaTokenExpr(expr)) continue;
            if (!(expr == .binary and expr.binary.operator == .bind)) {
                return self.fail(ast.exprSpan(expr), "expected record field binding");
            }
            try fields.append(self.arena, try self.lowerBinding(expr.binary));
        }

        return try fields.toOwnedSlice(self.arena);
    }

    fn symbolFromToken(self: *Lowerer, token: ast.Token, kind: SymbolKind) LowerError!Symbol {
        return .{
            .text = try self.arena.dupe(u8, self.source[token.span.start..token.span.end]),
            .kind = kind,
            .span = token.span,
        };
    }

    fn literalFromToken(self: *Lowerer, token: ast.Token) LowerError!Literal {
        return .{
            .text = try self.arena.dupe(u8, self.source[token.span.start..token.span.end]),
            .span = token.span,
        };
    }

    fn fail(self: *Lowerer, span: ast.Span, message: []const u8) error{LoweringFailed} {
        self.failure_diag = .{ .message = message, .span = span };
        return error.LoweringFailed;
    }
};

fn isCommaTokenExpr(expr: ast.Expr) bool {
    return expr == .token and expr.token.kind == .comma;
}

fn textHashCount(source: []const u8, keyword_end: usize, brace_start: usize) usize {
    var index = keyword_end;
    while (index < brace_start and (source[index] == ' ' or source[index] == '\t')) : (index += 1) {}
    var count: usize = 0;
    while (index < brace_start and source[index] == '#') : (index += 1) {
        count += 1;
    }
    return count;
}

fn findHashedInterpolation(source: []const u8, start: usize, hash_count: usize) ?usize {
    var index = start;
    while (index + hash_count + 1 <= source.len) : (index += 1) {
        var matched: usize = 0;
        while (matched < hash_count and index + matched < source.len and source[index + matched] == '#') : (matched += 1) {}
        if (matched == hash_count and index + matched < source.len and source[index + matched] == '{') return index;
    }
    return null;
}

fn isBareFormArgToken(kind: ast.TokenKind) bool {
    return switch (kind) {
        .snake_identifier, .pascal_identifier, .keyword => true,
        else => false,
    };
}

fn shiftSpan(span: ast.Span, offset: usize) ast.Span {
    return ast.Span.init(span.start + offset, span.end + offset);
}

fn rebaseExpr(expr: Expr, offset: usize) Expr {
    return switch (expr) {
        .symbol => |symbol| .{ .symbol = .{
            .text = symbol.text,
            .kind = symbol.kind,
            .span = shiftSpan(symbol.span, offset),
        } },
        .special => |special| .{ .special = .{
            .kind = special.kind,
            .span = shiftSpan(special.span, offset),
        } },
        .number => |literal| .{ .number = .{
            .text = literal.text,
            .span = shiftSpan(literal.span, offset),
        } },
        .wildcard => |literal| .{ .wildcard = .{
            .text = literal.text,
            .span = shiftSpan(literal.span, offset),
        } },
        .atom => |literal| .{ .atom = .{
            .text = literal.text,
            .span = shiftSpan(literal.span, offset),
        } },
        .path => |path| blk: {
            path.span = shiftSpan(path.span, offset);
            for (path.segments) |*segment| segment.span = shiftSpan(segment.span, offset);
            break :blk .{ .path = path };
        },
        .call => |call| blk: {
            call.span = shiftSpan(call.span, offset);
            call.callee = rebaseExpr(call.callee, offset);
            for (call.arguments) |*argument| {
                switch (argument.*) {
                    .positional => |value| argument.* = .{ .positional = rebaseExpr(value, offset) },
                    .spread => |value| argument.* = .{ .spread = rebaseExpr(value, offset) },
                    .named => |binding| {
                        binding.span = shiftSpan(binding.span, offset);
                        binding.name.span = shiftSpan(binding.name.span, offset);
                        binding.value = rebaseExpr(binding.value, offset);
                    },
                }
            }
            break :blk .{ .call = call };
        },
        .access => |access| blk: {
            access.span = shiftSpan(access.span, offset);
            access.target = rebaseExpr(access.target, offset);
            access.field.span = shiftSpan(access.field.span, offset);
            break :blk .{ .access = access };
        },
        .unary => |unary| blk: {
            unary.span = shiftSpan(unary.span, offset);
            unary.operand = rebaseExpr(unary.operand, offset);
            break :blk .{ .unary = unary };
        },
        .binary => |binary| blk: {
            binary.span = shiftSpan(binary.span, offset);
            binary.lhs = rebaseExpr(binary.lhs, offset);
            binary.rhs = rebaseExpr(binary.rhs, offset);
            break :blk .{ .binary = binary };
        },
        .sequence => |sequence| blk: {
            sequence.span = shiftSpan(sequence.span, offset);
            for (sequence.items) |*item| {
                switch (item.*) {
                    .expr => |value| item.* = .{ .expr = rebaseExpr(value, offset) },
                    .binding => |binding| {
                        binding.span = shiftSpan(binding.span, offset);
                        binding.name.span = shiftSpan(binding.name.span, offset);
                        binding.value = rebaseExpr(binding.value, offset);
                    },
                }
            }
            break :blk .{ .sequence = sequence };
        },
        .record => |record| blk: {
            record.span = shiftSpan(record.span, offset);
            for (record.fields) |binding| {
                binding.span = shiftSpan(binding.span, offset);
                binding.name.span = shiftSpan(binding.name.span, offset);
                binding.value = rebaseExpr(binding.value, offset);
            }
            break :blk .{ .record = record };
        },
        .form => |form| blk: {
            form.span = shiftSpan(form.span, offset);
            form.keyword.span = shiftSpan(form.keyword.span, offset);
            for (form.bare_args) |*arg| arg.span = shiftSpan(arg.span, offset);
            for (form.arguments) |*argument| argument.* = rebaseExpr(argument.*, offset);
            break :blk .{ .form = form };
        },
    };
}

fn formKindFor(text: []const u8, arguments: []Expr) FormKind {
    if (std.mem.eql(u8, text, "FUNCTION")) return .function_decl;
    if (std.mem.eql(u8, text, "HOLD")) return .hold;
    if (std.mem.eql(u8, text, "LATEST")) return .latest;
    if (std.mem.eql(u8, text, "THEN")) return .then;
    if (std.mem.eql(u8, text, "WHEN")) return .when;
    if (std.mem.eql(u8, text, "WHILE")) return .while_;
    if (std.mem.eql(u8, text, "BLOCK")) return .block;
    if (std.mem.eql(u8, text, "TEXT")) return .text;
    if (std.mem.eql(u8, text, "SOURCE") or std.mem.eql(u8, text, "LINK")) return .link;
    if (std.mem.eql(u8, text, "DRAIN")) return .drain_reserved;
    if (std.mem.eql(u8, text, "LIST")) {
        return if (firstArgumentIsBracket(arguments)) .list_static else .list_dynamic;
    }
    if (std.mem.eql(u8, text, "BITS")) {
        return if (firstArgumentIsBracket(arguments)) .bits_static else .bits_dynamic;
    }
    if (std.mem.eql(u8, text, "BYTES")) {
        return if (firstArgumentIsBracket(arguments)) .bytes_static else .bytes_dynamic;
    }
    if (std.mem.eql(u8, text, "MEMORY")) {
        return if (firstArgumentIsBracket(arguments)) .memory_static else .memory_dynamic;
    }
    return .generic_keyword;
}

fn firstArgumentIsBracket(arguments: []Expr) bool {
    if (arguments.len == 0) return false;
    return switch (arguments[0]) {
        .sequence => |sequence| sequence.delimiter == .brackets,
        .record => true,
        else => false,
    };
}

const Renderer = struct {
    writer: *const std.Io.Writer,

    fn renderItem(self: *Renderer, item: Item, indent: usize, depth: usize) !void {
        try self.writeIndent(indent);
        switch (item) {
            .binding => |binding| {
                try self.writer.print("binding {s} = ", .{binding.name.text});
                try self.renderExpr(binding.value, depth);
            },
            .expr => |expr| {
                try self.writer.writeAll("expr ");
                try self.renderExpr(expr, depth);
            },
        }
    }

    fn renderExpr(self: *Renderer, expr: Expr, depth: usize) !void {
        switch (expr) {
            .symbol => |symbol| try self.writer.print("symbol({s})", .{symbol.text}),
            .special => |special| try self.writer.print("special({s})", .{@tagName(special.kind)}),
            .number => |literal| try self.writer.print("number({s})", .{literal.text}),
            .wildcard => |literal| try self.writer.print("wildcard({s})", .{literal.text}),
            .atom => |literal| try self.writer.print("atom({s})", .{literal.text}),
            .path => |path| try self.renderPath(path),
            .call => |call| try self.renderCall(call, depth),
            .access => |access| try self.renderAccess(access, depth),
            .unary => |unary| try self.renderUnary(unary, depth),
            .binary => |binary| try self.renderBinary(binary, depth),
            .sequence => |sequence| try self.renderSequence(sequence, depth),
            .record => |record| try self.renderRecord(record, depth),
            .form => |form| try self.renderForm(form, depth),
        }
    }

    fn renderPath(self: *Renderer, path: *const Path) !void {
        try self.writer.writeAll("path(");
        for (path.segments, 0..) |segment, index| {
            if (index != 0) try self.writer.writeByte('/');
            try self.writer.writeAll(segment.text);
        }
        try self.writer.writeByte(')');
    }

    fn renderCall(self: *Renderer, call: *const Call, depth: usize) !void {
        try self.writer.print("call<{s}>(", .{@tagName(call.kind)});
        if (depth == 0) {
            try self.writer.print("args={d})", .{call.arguments.len});
            return;
        }

        try self.renderExpr(call.callee, depth - 1);
        for (call.arguments) |argument| {
            try self.writer.writeAll(", ");
            try self.renderArgument(argument, depth - 1);
        }
        try self.writer.writeByte(')');
    }

    fn renderArgument(self: *Renderer, argument: Argument, depth: usize) !void {
        switch (argument) {
            .positional => |expr| try self.renderExpr(expr, depth),
            .spread => |expr| {
                try self.writer.writeAll("spread(");
                try self.renderExpr(expr, depth);
                try self.writer.writeByte(')');
            },
            .named => |binding| {
                try self.writer.print("named({s}=", .{binding.name.text});
                if (depth == 0) {
                    try self.writer.writeAll("...)");
                    return;
                }
                try self.renderExpr(binding.value, depth - 1);
                try self.writer.writeByte(')');
            },
        }
    }

    fn renderAccess(self: *Renderer, access: *const Access, depth: usize) !void {
        try self.writer.print("access<{s}>(", .{@tagName(access.kind)});
        if (depth == 0) {
            try self.writer.print("{s})", .{access.field.text});
            return;
        }
        try self.renderExpr(access.target, depth - 1);
        try self.writer.print(", {s})", .{access.field.text});
    }

    fn renderUnary(self: *Renderer, unary: *const Unary, depth: usize) !void {
        try self.writer.print("unary({s}", .{@tagName(unary.operator)});
        if (depth == 0) {
            try self.writer.writeByte(')');
            return;
        }
        try self.writer.writeAll(", ");
        try self.renderExpr(unary.operand, depth - 1);
        try self.writer.writeByte(')');
    }

    fn renderBinary(self: *Renderer, binary: *const Binary, depth: usize) !void {
        try self.writer.print("binary({s}", .{@tagName(binary.operator)});
        if (depth == 0) {
            try self.writer.writeByte(')');
            return;
        }
        try self.writer.writeAll(", ");
        try self.renderExpr(binary.lhs, depth - 1);
        try self.writer.writeAll(", ");
        try self.renderExpr(binary.rhs, depth - 1);
        try self.writer.writeByte(')');
    }

    fn renderSequence(self: *Renderer, sequence: *const Sequence, depth: usize) !void {
        try self.writer.print("seq<{s}>(", .{@tagName(sequence.delimiter)});
        if (depth == 0) {
            try self.writer.print("{d})", .{sequence.items.len});
            return;
        }
        for (sequence.items, 0..) |item, index| {
            if (index != 0) try self.writer.writeAll("; ");
            switch (item) {
                .binding => |binding| {
                    try self.writer.print("{s}=", .{binding.name.text});
                    try self.renderExpr(binding.value, depth - 1);
                },
                .expr => |expr| try self.renderExpr(expr, depth - 1),
            }
        }
        try self.writer.writeByte(')');
    }

    fn renderRecord(self: *Renderer, record: *const Record, depth: usize) !void {
        try self.writer.writeAll("record(");
        if (depth == 0) {
            try self.writer.print("{d})", .{record.fields.len});
            return;
        }
        for (record.fields, 0..) |field, index| {
            if (index != 0) try self.writer.writeAll(", ");
            try self.writer.print("{s}=", .{field.name.text});
            try self.renderExpr(field.value, depth - 1);
        }
        try self.writer.writeByte(')');
    }

    fn renderForm(self: *Renderer, form: *const Form, depth: usize) !void {
        try self.writer.print("form({s}", .{@tagName(form.kind)});
        if (form.bare_args.len != 0) {
            try self.writer.writeAll(", bare=[");
            for (form.bare_args, 0..) |arg, index| {
                if (index != 0) try self.writer.writeAll(", ");
                try self.writer.writeAll(arg.text);
            }
            try self.writer.writeByte(']');
        }
        if (depth == 0) {
            try self.writer.print(", args={d})", .{form.arguments.len});
            return;
        }
        try self.writer.writeAll(", args=[");
        for (form.arguments, 0..) |argument, index| {
            if (index != 0) try self.writer.writeAll(", ");
            try self.renderExpr(argument, depth - 1);
        }
        try self.writer.writeAll("])");
    }

    fn writeIndent(self: *Renderer, indent: usize) !void {
        for (0..indent) |_| try self.writer.writeAll("  ");
    }
};

fn expectLowers(comptime path: []const u8) !void {
    const source = @embedFile(path);
    const outcome = try lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |document| {
            var lowered = document;
            lowered.deinit();
        },
        .err => |failure| {
            std.debug.print("hir failure for {s}: {s}\n", .{ path, failure.message });
            return error.UnexpectedHirFailure;
        },
    }
}

fn expectGolden(comptime path: []const u8, expected: []const u8) !void {
    const source = @embedFile(path);
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected hir failure for {s}: {s}\n", .{ path, failure.message });
            return error.UnexpectedHirFailure;
        },
    };
    var lowered = document;
    defer lowered.deinit();

    const actual = try renderAlloc(std.testing.allocator, &lowered);
    defer std.testing.allocator.free(actual);

    try std.testing.expectEqualStrings(expected, actual);
}

test "lowers counter definitions and forms" {
    const source = @embedFile("../examples/upstream/counter/counter.bn");
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected hir failure: {s}\n", .{failure.message});
            return error.UnexpectedHirFailure;
        },
    };
    var lowered = document;
    defer lowered.deinit();

    try std.testing.expect(lowered.items.len >= 3);
    try std.testing.expect(lowered.definition_count >= 3);

    const first_binding = switch (lowered.items[0]) {
        .binding => |binding| binding,
        else => return error.ExpectedBinding,
    };
    try std.testing.expectEqualStrings("document", first_binding.name.text);
}

test "reports lowering diagnostics with spans" {
    const source = "value: 1 |> 2\n";
    const outcome = try lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => return error.ExpectedLoweringFailure,
        .err => |failure| {
            try std.testing.expectEqualStrings("unsupported pipe target", failure.message);
            try std.testing.expectEqual(@as(usize, 12), failure.span.start);
            try std.testing.expectEqual(@as(usize, 13), failure.span.end);
        },
    }
}

test "lowers pipe-to-field shorthand access" {
    const source =
        \\value: [current: 5]
        \\result: value |> .current
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected pipe access lowering failure: {s}\n", .{failure.message});
            return error.UnexpectedHirFailure;
        },
    };
    var lowered = document;
    defer lowered.deinit();

    const actual = try renderAlloc(std.testing.allocator, &lowered);
    defer std.testing.allocator.free(actual);
    try std.testing.expect(std.mem.indexOf(u8, actual, "binding result = access<direct>(symbol(value), current)") != null);
}

test "lowers text interpolation with literal separators" {
    const source =
        \\document: TEXT { {name}: {input} }
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected text interpolation failure: {s}\n", .{failure.message});
            return error.UnexpectedHirFailure;
        },
    };
    var lowered = document;
    defer lowered.deinit();

    const rendered = try renderAlloc(std.testing.allocator, &lowered);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "atom(:)") != null);
}

test "lowers text bodies with literal parentheses and brackets" {
    const source =
        \\document: TEXT { Toggle filter (show_even: {store.show_even}) [X] }
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected text punctuation failure: {s}\n", .{failure.message});
            return error.UnexpectedHirFailure;
        },
    };
    var lowered = document;
    defer lowered.deinit();

    const rendered = try renderAlloc(std.testing.allocator, &lowered);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Toggle filter (show_even:") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "[X]") != null);
}

test "lowers hash-delimited text interpolation" {
    const source =
        \\document: TEXT ##{ a[href^="#{url}"] { color: ##{theme.color}; } }
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected hash text interpolation failure: {s}\n", .{failure.message});
            return error.UnexpectedHirFailure;
        },
    };
    var lowered = document;
    defer lowered.deinit();

    const rendered = try renderAlloc(std.testing.allocator, &lowered);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "a[href^=\"#{url}\"] { color:") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "access<direct>(symbol(theme), color)") != null);
}

test "rejects call expressions in TEXT interpolation" {
    const source =
        \\document: TEXT { Count: {store.items |> List/count()} }
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => return error.ExpectedHirFailure,
        .err => |failure| {
            try std.testing.expect(std.mem.indexOf(u8, failure.message, "TEXT interpolation only allows names and field access") != null);
        },
    }
}

test "lowers call-like text bodies as raw text" {
    const source =
        \\document: TEXT { add(A1, A2) }
        \\
    ;
    const outcome = try lowerAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected call-like text failure: {s}\n", .{failure.message});
            return error.UnexpectedHirFailure;
        },
    };
    var lowered = document;
    defer lowered.deinit();

    const rendered = try renderAlloc(std.testing.allocator, &lowered);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "add(A1, A2)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "call<call>(symbol(add)") == null);
}

test "golden HIR for counter" {
    try expectGolden("../examples/upstream/counter/counter.bn",
        \\stats definitions=14 exprs=34 calls=4 forms=4
        \\binding document = call<tagged_value>(path(Document/new), named(root=call<tagged_value>(path(Element/stripe), named(element=record()), named(direction=symbol(Column)), named(gap=number(0)), named(style=record()), named(items=form(list_dynamic, args=[seq<braces>(symbol(counter); symbol(increment_button))])))))
        \\binding counter = call<call>(path(Math/sum), form(latest, args=[seq<braces>(number(0); form(then, args=[access<direct>(access<direct>(access<direct>(symbol(increment_button), event), press), ...), seq<braces>(number(1))]))]))
        \\binding increment_button = call<tagged_value>(path(Element/button), named(element=record(event=record(press=special(link_ref)))), named(style=record()), named(label=form(text, args=[seq<braces>(atom(+))])))
        \\
    );
}

test "golden HIR for interval" {
    try expectGolden("../examples/upstream/interval/interval.bn",
        \\stats definitions=2 exprs=13 calls=4 forms=1
        \\binding document = call<tagged_value>(path(Document/new), call<call>(path(Math/sum), form(then, args=[call<call>(path(Timer/interval), call<tagged_value>(path(Duration), named(seconds=number(1)))), seq<braces>(number(1))])))
        \\
    );
}

test "golden HIR summary for cells" {
    try expectGolden("../examples/upstream/cells/cells.bn",
        \\stats definitions=320 exprs=1449 calls=132 forms=146
        \\expr form(function_decl, bare=[matching_overrides], args=[seq<parentheses>(symbol(column); symbol(row)), seq<braces>(call<call>(path(List/retain), symbol(overrides), symbol(item), named(if=form(when, args=[binary(equal, access<direct>(..., row), symbol(row)), seq<braces>(number(0)); wildcard(__)=number(0)]))))])
        \\expr form(function_decl, bare=[cell_formula], args=[seq<parentheses>(symbol(column); symbol(row)), seq<braces>(form(block, args=[match_count=call<call>(path(List/count), call<call>(path(matching_overrides), named(column=symbol(column)), named(row=symbol(row)))); match_count=access<direct>(..., text)]))])
        \\expr form(function_decl, bare=[parse_column_letter], args=[seq<parentheses>(symbol(text)), seq<braces>(form(when, args=[symbol(text), seq<braces>(form(text, args=1); number(1); form(text, args=1); number(2); form(text, args=1); number(3); form(text, args=1); number(4); form(text, args=1); number(5); form(text, args=1); number(6); form(text, args=1); number(7); form(text, args=1); number(8); form(text, args=1); number(9); form(text, args=1); number(10); form(text, args=1); number(11); form(text, args=1); number(12); form(text, args=1); number(13); form(text, args=1); number(14); form(text, args=1); number(15); form(text, args=1); number(16); form(text, args=1); number(17); form(text, args=1); number(18); form(text, args=1); number(19); form(text, args=1); number(20); form(text, args=1); number(21); form(text, args=1); number(22); form(text, args=1); number(23); form(text, args=1); number(24); form(text, args=1); number(25); form(text, args=1); number(26); wildcard(__)=number(0)]))])
        \\expr form(function_decl, bare=[extract_reference_column], args=[seq<parentheses>(symbol(ref_text)), seq<braces>(call<call>(symbol(parse_column_letter), call<call>(path(Text/substring), symbol(ref_text), named(start=number(0)), named(length=number(1)))))])
        \\expr form(function_decl, bare=[extract_reference_row], args=[seq<parentheses>(symbol(ref_text)), seq<braces>(call<call>(path(Text/to_number), call<call>(path(Text/substring), symbol(ref_text), named(start=number(1)), named(length=number(8)))))])
        \\expr form(function_decl, bare=[expression_value], args=[seq<parentheses>(symbol(text)), seq<braces>(form(block, args=7))])
        \\expr form(function_decl, bare=[compute_value], args=[seq<parentheses>(symbol(formula_text)), seq<braces>(form(while_, args=[call<call>(path(Text/starts_with), symbol(formula_text), named(prefix=form(text, args=1))), seq<braces>(symbol(False)=form(while_, args=3); wildcard(__)=form(block, args=2))]))])
        \\expr form(function_decl, bare=[make_cell], args=[seq<parentheses>(symbol(column); symbol(row)), seq<braces>(record(column=symbol(column), row=symbol(row)))])
        \\expr form(function_decl, bare=[make_row_cells], args=[seq<parentheses>(symbol(row)), seq<braces>(form(list_dynamic, args=[seq<braces>(call<call>(symbol(make_cell), named(column=number(1)), named(row=symbol(row))); call<call>(symbol(make_cell), named(column=number(2)), named(row=symbol(row))); call<call>(symbol(make_cell), named(column=number(3)), named(row=symbol(row))); ...)]))])
        \\expr form(function_decl, bare=[default_formula], args=[seq<parentheses>(symbol(column); symbol(row)), seq<braces>(form(when, args=3))])
        \\expr form(function_decl, bare=[is_editing_cell], args=[seq<parentheses>(symbol(cell)), seq<braces>(form(when, args=3))])
        \\expr form(function_decl, bare=[column_header], args=[seq<parentheses>(symbol(column_index)), seq<braces>(form(when, args=27))])
        \\expr form(function_decl, bare=[make_cell_element], args=[seq<parentheses>(symbol(cell)), seq<braces>(form(block, args=16))])
        \\expr form(function_decl, bare=[render_row_cells], args=[seq<parentheses>(symbol(row)), seq<braces>(call<call>(path(List/map), call<call>(symbol(make_row_cells), symbol(row)), symbol(cell), named(new=call<call>(symbol(make_cell_element), named(cell=symbol(cell))))))])
        \\expr form(function_decl, bare=[row_label], args=[seq<parentheses>(symbol(row_index)), seq<braces>(call<call>(path(Text/from), symbol(row_index)))])
        \\expr form(function_decl, bare=[column_headers], args=[seq<parentheses>(), seq<braces>(form(list_dynamic, args=1))])
        \\expr form(function_decl, bare=[row_element], args=[seq<parentheses>(symbol(row_index)), seq<braces>(call<tagged_value>(path(Element/stripe), named(direction=symbol(Row)), named(gap=number(0)), named(style=record()), named(items=form(list_dynamic, args=1))))])
        \\expr form(function_decl, bare=[all_rows], args=[seq<parentheses>(), seq<braces>(form(list_dynamic, args=1))])
        \\binding overrides = form(hold, bare=[state], args=[seq<braces>(form(list_dynamic, args=1); special(pass_ref); special(passed_ref))])
        \\binding editing_row = form(hold, bare=[state], args=[seq<braces>(number(0); access<direct>(..., edit_started_row); access<direct>(..., edit_committed_row))])
        \\binding editing_column = form(hold, bare=[state], args=[seq<braces>(number(0); access<direct>(..., edit_started_column); access<direct>(..., edit_committed_column))])
        \\binding editing_text = form(hold, bare=[state], args=[seq<braces>(form(text, args=1); access<direct>(..., edit_text_event))])
        \\binding editing_active = form(hold, bare=[state], args=[seq<braces>(symbol(False); access<direct>(..., edit_active_event); symbol(False))])
        \\binding event_ports = record(edit_started_row=special(link_ref), edit_started_column=special(link_ref), edit_text_event=special(link_ref), edit_active_event=special(link_ref), edit_committed_row=special(link_ref), edit_committed_column=special(link_ref), edit_committed_text=special(link_ref))
        \\binding document = call<tagged_value>(path(Document/new), named(root=call<tagged_value>(path(Element/stripe), named(direction=symbol(Column)), named(gap=number(0)), named(style=record()), named(items=form(list_dynamic, args=1)))))
        \\
    );
}

test "golden HIR for pong stub" {
    try expectGolden("../examples/terminal/pong/pong.bn",
        \\stats definitions=2 exprs=7 calls=1 forms=1
        \\binding document = call<tagged_value>(path(Document/new), named(root=form(text, args=[seq<braces>(atom(Pong); symbol(phase); number(2); symbol(parser); symbol(stub))])))
        \\
    );
}

test "golden HIR for arkanoid stub" {
    try expectGolden("../examples/terminal/arkanoid/arkanoid.bn",
        \\stats definitions=2 exprs=7 calls=1 forms=1
        \\binding document = call<tagged_value>(path(Document/new), named(root=form(text, args=[seq<braces>(symbol(Arkanoid); symbol(phase); number(2); symbol(parser); symbol(stub))])))
        \\
    );
}

test "lowers phase 3 verification examples" {
    try expectLowers("../examples/upstream/counter/counter.bn");
    try expectLowers("../examples/upstream/interval/interval.bn");
    try expectLowers("../examples/upstream/cells/cells.bn");
    try expectLowers("../examples/upstream/while/while.bn");
    try expectLowers("../examples/terminal/counter/counter.bn");
    try expectLowers("../examples/terminal/interval/interval.bn");
    try expectLowers("../examples/terminal/todo_mvc/todo_mvc.bn");
    try expectLowers("../examples/terminal/cells/cells.bn");
    try expectLowers("../examples/terminal/cells_dynamic/cells_dynamic.bn");
    try expectLowers("../examples/terminal/pong/pong.bn");
    try expectLowers("../examples/terminal/arkanoid/arkanoid.bn");
}
