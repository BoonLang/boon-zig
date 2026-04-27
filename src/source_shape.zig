const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");

pub const SourceField = struct {
    path: []const u8,
    span: ast.Span,
};

pub const SourceShape = struct {
    arena: std.heap.ArenaAllocator,
    fields: []SourceField,

    pub fn deinit(self: *SourceShape) void {
        self.arena.deinit();
    }
};

pub const Outcome = union(enum) {
    ok: SourceShape,
    err: diag.Diagnostic,
};

const FreezeError = std.mem.Allocator.Error || error{FreezeFailed};
const invalid_source_expression_message = "SOURCE marks a runtime source field and cannot be used as a normal value";

const Freezer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    fields: std.ArrayList(SourceField) = .empty,
    root_bindings: std.StringHashMap(ast.Expr),
    failure_diag: ?diag.Diagnostic = null,

    fn init(allocator: std.mem.Allocator, source: []const u8) Freezer {
        return .{
            .allocator = allocator,
            .source = source,
            .root_bindings = .init(allocator),
        };
    }

    fn deinit(self: *Freezer) void {
        self.fields.deinit(self.allocator);
        self.root_bindings.deinit();
    }

    fn fail(self: *Freezer, span: ast.Span, message: []const u8) FreezeError {
        self.failure_diag = .{ .message = message, .span = span };
        return error.FreezeFailed;
    }

    fn collectRootBindings(self: *Freezer, document: *const ast.Document) FreezeError!void {
        for (document.root.items) |item| {
            if (item != .binary or item.binary.operator != .bind) continue;
            const name = tokenText(self.source, item.binary.lhs) orelse continue;
            try self.root_bindings.put(name, item.binary.rhs);
        }
    }

    fn collectRootItem(self: *Freezer, expr: ast.Expr) FreezeError!void {
        if (expr != .binary or expr.binary.operator != .bind) return;
        const name = tokenText(self.source, expr.binary.lhs) orelse return;
        var path: std.ArrayList([]const u8) = .empty;
        defer path.deinit(self.allocator);
        try path.append(self.allocator, name);
        try self.collectExpr(&path, expr.binary.rhs, 0);
    }

    fn collectExpr(self: *Freezer, path: *std.ArrayList([]const u8), expr: ast.Expr, depth: usize) FreezeError!void {
        if (depth > 32) return self.fail(ast.exprSpan(expr), "dynamic source shape");
        if (isSourceToken(self.source, expr)) {
            try self.fields.append(self.allocator, .{
                .path = try joinPath(self.allocator, path.items),
                .span = ast.exprSpan(expr),
            });
            return;
        }

        switch (expr) {
            .group => |group| if (group.delimiter == .brackets) {
                for (group.items) |item| {
                    if (item == .unary and item.unary.operator == .spread) {
                        const spread_expr = try self.resolveSpread(item.unary.operand);
                        try self.collectExpr(path, spread_expr, depth + 1);
                        continue;
                    }
                    if (item != .binary or item.binary.operator != .bind) continue;
                    const field_name = tokenText(self.source, item.binary.lhs) orelse continue;
                    try path.append(self.allocator, field_name);
                    defer _ = path.pop();
                    try self.collectExpr(path, item.binary.rhs, depth + 1);
                }
            },
            .apply => |apply| {
                try self.collectExpr(path, apply.head, depth + 1);
                for (apply.arguments) |arg| try self.collectExpr(path, arg, depth + 1);
            },
            .access => |access| try self.collectExpr(path, access.target, depth + 1),
            .unary => |unary| switch (unary.operator) {
                .spread => {
                    const spread_expr = try self.resolveSpread(unary.operand);
                    try self.collectExpr(path, spread_expr, depth + 1);
                },
                else => try self.collectExpr(path, unary.operand, depth + 1),
            },
            .binary => |binary| {
                if (binary.operator != .bind and containsSourceToken(self.source, expr)) {
                    return self.fail(ast.exprSpan(expr), invalid_source_expression_message);
                }
                try self.collectExpr(path, binary.lhs, depth + 1);
                try self.collectExpr(path, binary.rhs, depth + 1);
            },
            .token, .path => {},
        }
    }

    fn resolveSpread(self: *Freezer, expr: ast.Expr) FreezeError!ast.Expr {
        if (expr == .token) {
            const name = self.source[expr.token.span.start..expr.token.span.end];
            if (self.root_bindings.get(name)) |resolved| return resolved;
        }
        return self.fail(ast.exprSpan(expr), "dynamic source shape");
    }
};

pub fn freezeAlloc(allocator: std.mem.Allocator, source: []const u8, document: *const ast.Document) !Outcome {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var owns_result = false;
    defer if (!owns_result) arena.deinit();

    var freezer = Freezer.init(arena.allocator(), source);
    defer freezer.deinit();

    freezer.collectRootBindings(document) catch |err| switch (err) {
        error.FreezeFailed => return .{ .err = freezer.failure_diag.? },
        else => return err,
    };
    for (document.root.items) |item| {
        freezer.collectRootItem(item) catch |err| switch (err) {
            error.FreezeFailed => return .{ .err = freezer.failure_diag.? },
            else => return err,
        };
    }

    const fields = try freezer.fields.toOwnedSlice(arena.allocator());
    owns_result = true;
    return .{ .ok = .{
        .arena = arena,
        .fields = fields,
    } };
}

fn tokenText(source: []const u8, expr: ast.Expr) ?[]const u8 {
    return switch (expr) {
        .token => |token| source[token.span.start..token.span.end],
        else => null,
    };
}

fn isSourceToken(source: []const u8, expr: ast.Expr) bool {
    const text = tokenText(source, expr) orelse return false;
    return std.mem.eql(u8, text, "SOURCE");
}

fn containsSourceToken(source: []const u8, expr: ast.Expr) bool {
    if (isSourceToken(source, expr)) return true;
    return switch (expr) {
        .token, .path => false,
        .group => |group| for (group.items) |item| {
            if (containsSourceToken(source, item)) break true;
        } else false,
        .apply => |apply| blk: {
            if (containsSourceToken(source, apply.head)) break :blk true;
            for (apply.arguments) |arg| {
                if (containsSourceToken(source, arg)) break :blk true;
            }
            break :blk false;
        },
        .access => |access| containsSourceToken(source, access.target),
        .unary => |unary| containsSourceToken(source, unary.operand),
        .binary => |binary| containsSourceToken(source, binary.lhs) or containsSourceToken(source, binary.rhs),
    };
}

fn joinPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    if (parts.len == 0) return try allocator.dupe(u8, "");
    var len: usize = 0;
    for (parts) |part| len += part.len;
    len += parts.len - 1;

    const output = try allocator.alloc(u8, len);
    var cursor: usize = 0;
    for (parts, 0..) |part, index| {
        if (index != 0) {
            output[cursor] = '.';
            cursor += 1;
        }
        @memcpy(output[cursor .. cursor + part.len], part);
        cursor += part.len;
    }
    return output;
}
