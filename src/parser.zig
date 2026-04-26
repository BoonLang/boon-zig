const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const lexer = @import("lexer.zig");

const ParseInternalError = std.mem.Allocator.Error || error{
    UnexpectedClosingDelimiter,
    UnterminatedDelimiter,
    ExpectedExpression,
    ExpectedPathSegment,
    ExpectedFieldName,
};

const BinaryInfo = struct {
    operator: ast.BinaryOp,
    precedence: u8,
    right_associative: bool = false,
};

pub const Outcome = union(enum) {
    ok: ast.Document,
    err: diag.Diagnostic,
};

pub const Options = struct {};

pub fn parseAlloc(allocator: std.mem.Allocator, source: []const u8) !Outcome {
    return parseAllocWithOptions(allocator, source, .{});
}

pub fn parseAllocWithOptions(allocator: std.mem.Allocator, source: []const u8, options: Options) !Outcome {
    const lexed = try lexer.lexAlloc(allocator, source);
    const tokens = switch (lexed) {
        .ok => |tokens| tokens,
        .err => |failure| return .{ .err = failure },
    };
    defer allocator.free(tokens);

    _ = options;

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var state = Parser{
        .source = source,
        .tokens = tokens,
        .arena = arena.allocator(),
    };

    const items = try state.parseItems(null);
    const document: ast.Document = .{
        .arena = arena,
        .root = .{
            .delimiter = .root,
            .span = ast.Span.init(0, source.len),
            .items = items,
        },
        .token_count = tokens.len,
        .group_count = state.group_count,
        .form_count = state.form_count,
        .source_len = source.len,
    };
    return .{ .ok = document };
}

const Parser = struct {
    source: []const u8,
    tokens: []const ast.Token,
    index: usize = 0,
    arena: std.mem.Allocator,
    group_count: usize = 0,
    form_count: usize = 0,

    fn parseItems(self: *Parser, closing_kind: ?ast.TokenKind) ParseInternalError![]ast.Expr {
        var items: std.ArrayList(ast.Expr) = .empty;
        defer items.deinit(self.arena);

        while (self.index < self.tokens.len) {
            const token = self.tokens[self.index];
            if (closing_kind) |expected| {
                if (token.kind == expected) {
                    self.index += 1;
                    return try items.toOwnedSlice(self.arena);
                }
            }

            if (isClosingDelimiter(token.kind)) return error.UnexpectedClosingDelimiter;

            const expr = try self.parseExpression(0, closing_kind);
            try items.append(self.arena, expr);
        }

        if (closing_kind != null) return error.UnterminatedDelimiter;
        return try items.toOwnedSlice(self.arena);
    }

    fn parseExpression(self: *Parser, min_precedence: u8, closing_kind: ?ast.TokenKind) ParseInternalError!ast.Expr {
        var lhs = try self.parsePrefix(closing_kind);
        lhs = try self.parsePostfix(lhs);

        while (self.index < self.tokens.len) {
            const token = self.tokens[self.index];
            if (closing_kind) |expected| {
                if (token.kind == expected) break;
            }
            if (isClosingDelimiter(token.kind)) break;

            const info = self.binaryInfo(lhs, token) orelse break;
            if (info.precedence < min_precedence) break;
            if (!self.hasBinaryRhs()) break;

            self.index += 1;
            const next_min = if (info.right_associative) info.precedence else info.precedence + 1;
            const rhs = try self.parseExpression(next_min, closing_kind);
            lhs = try self.makeBinary(info.operator, lhs, token.span, rhs);
        }

        return lhs;
    }

    fn parsePrefix(self: *Parser, closing_kind: ?ast.TokenKind) ParseInternalError!ast.Expr {
        _ = closing_kind;
        if (self.index >= self.tokens.len) return error.ExpectedExpression;

        const token = self.tokens[self.index];
        switch (token.kind) {
            .minus => {
                if (!self.hasPrefixOperand()) {
                    self.index += 1;
                    return .{ .token = token };
                }
                self.index += 1;
                const operand = try self.parseExpression(70, null);
                return try self.makeUnary(.negate, token.span, operand);
            },
            .spread => {
                if (!self.hasPrefixOperand()) {
                    self.index += 1;
                    return .{ .token = token };
                }
                self.index += 1;
                const operand = try self.parseExpression(70, null);
                return try self.makeUnary(.spread, token.span, operand);
            },
            .l_paren, .l_bracket, .l_brace => {
                self.index += 1;
                const group = try self.parseGroup(token);
                return .{ .group = group };
            },
            .r_paren, .r_bracket, .r_brace => return error.UnexpectedClosingDelimiter,
            .keyword => {
                self.index += 1;
                var expr: ast.Expr = .{ .token = token };
                expr = try self.parseKeywordBareArgs(expr);
                return expr;
            },
            .dot => {
                if (self.index + 1 < self.tokens.len) {
                    const field = self.tokens[self.index + 1];
                    if (isNameToken(field.kind) and self.isTight(token.span.start, token.span.end, field.span.start, field.span.end)) {
                        const access = try self.arena.create(ast.Access);
                        access.* = .{
                            .kind = .direct,
                            .target = .{ .token = token },
                            .field = field,
                            .span = ast.Span.init(token.span.start, field.span.end),
                        };
                        self.index += 2;
                        self.form_count += 1;
                        return .{ .access = access };
                    }
                }
                self.index += 1;
                return .{ .token = token };
            },
            else => {
                self.index += 1;
                return .{ .token = token };
            },
        }
    }

    fn parsePostfix(self: *Parser, initial: ast.Expr) ParseInternalError!ast.Expr {
        var expr = initial;
        while (self.index < self.tokens.len) {
            const token = self.tokens[self.index];
            switch (token.kind) {
                .l_paren, .l_bracket, .l_brace => {
                    if (!self.canApplyGroup(expr, token)) break;
                    self.index += 1;
                    const group = try self.parseGroup(token);
                    expr = try self.appendApply(expr, .{ .group = group }, null);
                },
                .slash => {
                    if (!self.isPathJoin(expr)) break;
                    expr = try self.extendPath(expr);
                },
                .dot => {
                    if (!self.isTightAccess(expr, token)) break;
                    expr = try self.parseAccess(expr, .direct);
                },
                .question => {
                    if (!self.isOptionalAccessStart(expr, token)) break;
                    expr = try self.parseAccess(expr, .optional);
                },
                else => break,
            }
        }
        return expr;
    }

    fn parseKeywordBareArgs(self: *Parser, head: ast.Expr) ParseInternalError!ast.Expr {
        const token = switch (head) {
            .token => |value| value,
            else => return head,
        };

        if (!self.keywordAcceptsBareArgs(token)) return head;

        var expr = head;
        while (self.index < self.tokens.len) {
            const next = self.tokens[self.index];
            if (!isNameToken(next.kind)) break;

            self.index += 1;
            expr = try self.appendApply(expr, .{ .token = next }, .keyword_form);
        }
        return expr;
    }

    fn parseGroup(self: *Parser, opening: ast.Token) ParseInternalError!*ast.Group {
        const expected_close = matchingClose(opening.kind);
        const delimiter = delimiterFor(opening.kind);
        const items = self.parseItems(expected_close) catch |err| {
            return switch (err) {
                error.UnexpectedClosingDelimiter => error.UnexpectedClosingDelimiter,
                error.UnterminatedDelimiter => error.UnterminatedDelimiter,
                error.ExpectedExpression => error.ExpectedExpression,
                error.ExpectedPathSegment => error.ExpectedPathSegment,
                error.ExpectedFieldName => error.ExpectedFieldName,
                else => err,
            };
        };

        const close_token = self.tokens[self.index - 1];
        const group = try self.arena.create(ast.Group);
        group.* = .{
            .delimiter = delimiter,
            .span = ast.Span.init(opening.span.start, close_token.span.end),
            .items = items,
        };
        self.group_count += 1;
        self.form_count += items.len;
        return group;
    }

    fn appendApply(
        self: *Parser,
        expr: ast.Expr,
        argument: ast.Expr,
        forced_kind: ?ast.ApplyKind,
    ) ParseInternalError!ast.Expr {
        if (expr == .apply and forced_kind == null) {
            const existing = expr.apply;
            const args = try self.arena.alloc(ast.Expr, existing.arguments.len + 1);
            @memcpy(args[0..existing.arguments.len], existing.arguments);
            args[existing.arguments.len] = argument;

            const apply = try self.arena.create(ast.Apply);
            apply.* = .{
                .kind = existing.kind,
                .head = existing.head,
                .arguments = args,
                .span = ast.Span.init(ast.exprSpan(existing.head).start, ast.exprSpan(argument).end),
            };
            self.form_count += 1;
            return .{ .apply = apply };
        }

        const args = try self.arena.alloc(ast.Expr, 1);
        args[0] = argument;

        const apply = try self.arena.create(ast.Apply);
        apply.* = .{
            .kind = forced_kind orelse classifyApplyKind(expr, argument),
            .head = expr,
            .arguments = args,
            .span = ast.Span.init(ast.exprSpan(expr).start, ast.exprSpan(argument).end),
        };
        self.form_count += 1;
        return .{ .apply = apply };
    }

    fn extendPath(self: *Parser, expr: ast.Expr) ParseInternalError!ast.Expr {
        const slash = self.tokens[self.index];
        const rhs_index = self.index + 1;
        if (rhs_index >= self.tokens.len) return error.ExpectedPathSegment;

        const rhs = self.tokens[rhs_index];
        if (!isNameToken(rhs.kind)) return error.ExpectedPathSegment;
        if (!self.isTight(slash.span.start, slash.span.end, rhs.span.start, rhs.span.end)) {
            return error.ExpectedPathSegment;
        }

        const segments = switch (expr) {
            .path => |path| blk: {
                const owned = try self.arena.alloc(ast.Token, path.segments.len + 1);
                @memcpy(owned[0..path.segments.len], path.segments);
                owned[path.segments.len] = rhs;
                break :blk owned;
            },
            .token => |token| blk: {
                const owned = try self.arena.alloc(ast.Token, 2);
                owned[0] = token;
                owned[1] = rhs;
                break :blk owned;
            },
            else => return error.ExpectedPathSegment,
        };

        const path = try self.arena.create(ast.Path);
        path.* = .{
            .segments = segments,
            .span = ast.Span.init(ast.exprSpan(expr).start, rhs.span.end),
        };
        self.index += 2;
        self.form_count += 1;
        return .{ .path = path };
    }

    fn parseAccess(self: *Parser, expr: ast.Expr, kind: ast.AccessKind) ParseInternalError!ast.Expr {
        const operator_index = self.index;
        var field_index = operator_index + 1;

        if (kind == .optional and field_index < self.tokens.len and self.tokens[field_index].kind == .dot) {
            field_index += 1;
        }
        if (field_index >= self.tokens.len) return error.ExpectedFieldName;

        const field = self.tokens[field_index];
        if (!isNameToken(field.kind)) return error.ExpectedFieldName;

        const operator_token = self.tokens[operator_index];
        if (kind == .direct) {
            if (!self.isTight(ast.exprSpan(expr).start, ast.exprSpan(expr).end, operator_token.span.start, operator_token.span.end)) {
                return error.ExpectedFieldName;
            }
        } else if (field_index == operator_index + 2) {
            const dot = self.tokens[operator_index + 1];
            if (!self.isTight(ast.exprSpan(expr).start, ast.exprSpan(expr).end, operator_token.span.start, operator_token.span.end) or
                !self.isTight(operator_token.span.start, operator_token.span.end, dot.span.start, dot.span.end) or
                !self.isTight(dot.span.start, dot.span.end, field.span.start, field.span.end))
            {
                return error.ExpectedFieldName;
            }
        }

        const access = try self.arena.create(ast.Access);
        access.* = .{
            .kind = kind,
            .target = expr,
            .field = field,
            .span = ast.Span.init(ast.exprSpan(expr).start, field.span.end),
        };
        self.index = field_index + 1;
        self.form_count += 1;
        return .{ .access = access };
    }

    fn makeUnary(self: *Parser, operator: ast.UnaryOp, operator_span: ast.Span, operand: ast.Expr) ParseInternalError!ast.Expr {
        const unary = try self.arena.create(ast.Unary);
        unary.* = .{
            .operator = operator,
            .operator_span = operator_span,
            .operand = operand,
            .span = ast.Span.init(operator_span.start, ast.exprSpan(operand).end),
        };
        self.form_count += 1;
        return .{ .unary = unary };
    }

    fn makeBinary(self: *Parser, operator: ast.BinaryOp, lhs: ast.Expr, operator_span: ast.Span, rhs: ast.Expr) ParseInternalError!ast.Expr {
        const binary = try self.arena.create(ast.Binary);
        binary.* = .{
            .operator = operator,
            .lhs = lhs,
            .rhs = rhs,
            .operator_span = operator_span,
            .span = ast.Span.init(ast.exprSpan(lhs).start, ast.exprSpan(rhs).end),
        };
        self.form_count += 1;
        return .{ .binary = binary };
    }

    fn binaryInfo(self: *Parser, lhs: ast.Expr, token: ast.Token) ?BinaryInfo {
        return switch (token.kind) {
            .colon => .{ .operator = .bind, .precedence = 10, .right_associative = true },
            .fat_arrow => .{ .operator = .arm_arrow, .precedence = 20, .right_associative = true },
            .pipe_forward => .{ .operator = .pipe_forward, .precedence = 30 },
            .eq, .single_equals => .{ .operator = .equal, .precedence = 40 },
            .neq => .{ .operator = .not_equal, .precedence = 40 },
            .gt => .{ .operator = .greater, .precedence = 40 },
            .gte => .{ .operator = .greater_equal, .precedence = 40 },
            .lt => .{ .operator = .less, .precedence = 40 },
            .lte => .{ .operator = .less_equal, .precedence = 40 },
            .plus => .{ .operator = .add, .precedence = 50 },
            .minus => .{ .operator = .subtract, .precedence = 50 },
            .star => .{ .operator = .multiply, .precedence = 60 },
            .slash => if (self.isPathJoin(lhs)) null else .{ .operator = .divide, .precedence = 60 },
            .percent => .{ .operator = .modulo, .precedence = 60 },
            .caret => .{ .operator = .power, .precedence = 70, .right_associative = true },
            else => null,
        };
    }

    fn hasBinaryRhs(self: *Parser) bool {
        const rhs_index = self.index + 1;
        if (rhs_index >= self.tokens.len) return false;
        return canStartExpression(self.tokens[rhs_index].kind);
    }

    fn hasPrefixOperand(self: *Parser) bool {
        const operand_index = self.index + 1;
        if (operand_index >= self.tokens.len) return false;
        return canStartExpression(self.tokens[operand_index].kind);
    }

    fn isPathJoin(self: *Parser, expr: ast.Expr) bool {
        if (self.index + 1 >= self.tokens.len) return false;
        if (self.tokens[self.index].kind != .slash) return false;
        if (!isNameToken(self.tokens[self.index + 1].kind)) return false;
        if (!isPathHeadExpr(expr)) return false;

        const slash = self.tokens[self.index];
        return self.isTight(ast.exprSpan(expr).start, ast.exprSpan(expr).end, slash.span.start, slash.span.end) and
            self.isTight(slash.span.start, slash.span.end, self.tokens[self.index + 1].span.start, self.tokens[self.index + 1].span.end);
    }

    fn isTightAccess(self: *Parser, expr: ast.Expr, dot: ast.Token) bool {
        if (self.index + 1 >= self.tokens.len) return false;
        if (!isNameToken(self.tokens[self.index + 1].kind)) return false;
        return self.isTight(ast.exprSpan(expr).start, ast.exprSpan(expr).end, dot.span.start, dot.span.end) and
            self.isTight(dot.span.start, dot.span.end, self.tokens[self.index + 1].span.start, self.tokens[self.index + 1].span.end);
    }

    fn isOptionalAccessStart(self: *Parser, expr: ast.Expr, question: ast.Token) bool {
        if (!self.isTight(ast.exprSpan(expr).start, ast.exprSpan(expr).end, question.span.start, question.span.end)) return false;
        if (self.index + 2 < self.tokens.len and self.tokens[self.index + 1].kind == .dot and isNameToken(self.tokens[self.index + 2].kind)) {
            return self.isTight(question.span.start, question.span.end, self.tokens[self.index + 1].span.start, self.tokens[self.index + 1].span.end) and
                self.isTight(self.tokens[self.index + 1].span.start, self.tokens[self.index + 1].span.end, self.tokens[self.index + 2].span.start, self.tokens[self.index + 2].span.end);
        }
        return false;
    }

    fn canApplyGroup(self: *Parser, expr: ast.Expr, opening: ast.Token) bool {
        if (self.isTight(ast.exprSpan(expr).start, ast.exprSpan(expr).end, opening.span.start, opening.span.end)) return true;
        const tail = ast.exprTailToken(expr) orelse return false;
        return tail.kind == .keyword or
            (tail.kind == .pascal_identifier and opening.kind == .l_bracket);
    }

    fn keywordAcceptsBareArgs(self: *Parser, token: ast.Token) bool {
        const text = self.source[token.span.start..token.span.end];
        return std.mem.eql(u8, text, "FUNCTION") or std.mem.eql(u8, text, "HOLD");
    }

    fn hasWhitespace(self: *Parser, start: usize, end: usize) bool {
        if (end <= start) return false;
        for (self.source[start..end]) |byte| {
            switch (byte) {
                ' ', '\n', '\r', '\t' => return true,
                else => {},
            }
        }
        return false;
    }

    fn isTight(self: *Parser, left_start: usize, left_end: usize, right_start: usize, right_end: usize) bool {
        _ = left_start;
        _ = right_end;
        return !self.hasWhitespace(left_end, right_start) and left_end == right_start;
    }
};

fn classifyApplyKind(head: ast.Expr, argument: ast.Expr) ast.ApplyKind {
    _ = argument;
    const tail = ast.exprTailToken(head) orelse return .call;
    return switch (tail.kind) {
        .keyword => .keyword_form,
        .pascal_identifier => .tagged_value,
        else => .call,
    };
}

fn isPathHeadExpr(expr: ast.Expr) bool {
    return switch (expr) {
        .token => |token| isNameToken(token.kind),
        .path => true,
        else => false,
    };
}

fn isNameToken(kind: ast.TokenKind) bool {
    return switch (kind) {
        .snake_identifier, .pascal_identifier, .wildcard, .keyword => true,
        else => false,
    };
}

fn isClosingDelimiter(kind: ast.TokenKind) bool {
    return switch (kind) {
        .r_paren, .r_bracket, .r_brace => true,
        else => false,
    };
}

fn canStartExpression(kind: ast.TokenKind) bool {
    return switch (kind) {
        .r_paren, .r_bracket, .r_brace, .comma => false,
        else => true,
    };
}

fn matchingClose(kind: ast.TokenKind) ast.TokenKind {
    return switch (kind) {
        .l_paren => .r_paren,
        .l_bracket => .r_bracket,
        .l_brace => .r_brace,
        else => unreachable,
    };
}

fn delimiterFor(kind: ast.TokenKind) ast.Delimiter {
    return switch (kind) {
        .l_paren => .parentheses,
        .l_bracket => .brackets,
        .l_brace => .braces,
        else => unreachable,
    };
}

pub fn diagnosticForParseFailure(source: []const u8, outcome_err: anytype) diag.Diagnostic {
    return switch (outcome_err) {
        error.UnexpectedClosingDelimiter => .{
            .message = "unexpected closing delimiter",
            .span = closingFailureSpan(source),
        },
        error.UnterminatedDelimiter => .{
            .message = "unterminated delimiter group",
            .span = ast.Span.init(@max(source.len, 1) - 1, source.len),
        },
        error.ExpectedExpression => .{
            .message = "expected expression",
            .span = ast.Span.init(@max(source.len, 1) - 1, source.len),
        },
        error.ExpectedPathSegment => .{
            .message = "expected module path segment",
            .span = ast.Span.init(@max(source.len, 1) - 1, source.len),
        },
        error.ExpectedFieldName => .{
            .message = "expected field name after access operator",
            .span = ast.Span.init(@max(source.len, 1) - 1, source.len),
        },
        else => .{
            .message = "unhandled parser failure",
            .span = ast.Span.init(0, @min(source.len, 1)),
        },
    };
}

fn closingFailureSpan(source: []const u8) ast.Span {
    var index = source.len;
    while (index > 0) {
        index -= 1;
        switch (source[index]) {
            ')', ']', '}' => return ast.Span.init(index, index + 1),
            else => {},
        }
    }
    return ast.Span.init(0, @min(source.len, 1));
}

fn expectParses(comptime path: []const u8) !void {
    const source = @embedFile(path);
    const outcome = try parseAlloc(std.testing.allocator, source);
    switch (outcome) {
        .ok => |document| {
            var parsed = document;
            parsed.deinit();
        },
        .err => |failure| {
            std.debug.print("parse failure for {s}: {s}\n", .{ path, failure.message });
            return error.UnexpectedParseFailure;
        },
    }
}

const corpus_roots = [_][]const u8{
    "examples/upstream",
    "examples/terminal",
};

const known_parser_blockers = [_][]const u8{
    "examples/upstream/hw_examples/serialadder.bn",
};

fn isKnownParserBlocker(path: []const u8) bool {
    inline for (known_parser_blockers) |blocked| {
        if (std.mem.eql(u8, blocked, path)) return true;
    }
    return false;
}

fn expectCorpusParses() !void {
    const allocator = std.testing.allocator;
    var parsed_count: usize = 0;
    var blocked_count: usize = 0;

    inline for (corpus_roots) |root_path| {
        var dir = try std.Io.Dir.cwd().openDir(std.testing.io, root_path, .{ .iterate = true });
        defer dir.close(std.testing.io);

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.path, ".bn")) continue;

            const relative_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root_path, entry.path });
            defer allocator.free(relative_path);

            const source = try std.Io.Dir.cwd().readFileAlloc(
                std.testing.io,
                relative_path,
                allocator,
                .limited(std.math.maxInt(usize)),
            );
            defer allocator.free(source);

            const outcome = try parseAlloc(allocator, source);
            switch (outcome) {
                .ok => |document| {
                    var parsed = document;
                    parsed.deinit();
                    parsed_count += 1;
                },
                .err => |failure| {
                    if (isKnownParserBlocker(relative_path)) {
                        blocked_count += 1;
                        continue;
                    }
                    std.debug.print("unexpected corpus parse failure for {s}: {s}\n", .{ relative_path, failure.message });
                    return error.UnexpectedParseFailure;
                },
            }
        }
    }

    try std.testing.expect(parsed_count > 0);
    try std.testing.expectEqual(@as(usize, known_parser_blockers.len), blocked_count);
}

test "detects mismatched delimiters" {
    const outcome = try parseAlloc(std.testing.allocator, "{ ]");
    switch (outcome) {
        .ok => |document| {
            var parsed = document;
            parsed.deinit();
            return error.ExpectedFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("unexpected closing delimiter", failure.message),
    }
}

test "parses bindings pipes and keyword forms" {
    const outcome = try parseAlloc(
        std.testing.allocator,
        "document: Document/new(root: TEXT { Hi })\ncount: tick |> THEN { state + 0.1 }\n",
    );
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected parse failure: {s}\n", .{failure.message});
            return error.UnexpectedParseFailure;
        },
    };
    var parsed = document;
    defer parsed.deinit();

    try std.testing.expect(parsed.root.items.len >= 2);
    try std.testing.expect(parsed.form_count >= parsed.group_count);
    switch (parsed.root.items[0]) {
        .binary => |binding| try std.testing.expectEqual(ast.BinaryOp.bind, binding.operator),
        else => return error.ExpectedBinding,
    }
}

test "canonical source mode rejects legacy LINK leaf" {
    const outcome = try parseAllocWithOptions(
        std.testing.allocator,
        "button: [event: [press: LINK]]\n",
        .{},
    );
    switch (outcome) {
        .ok => |document| {
            var parsed = document;
            parsed.deinit();
            return error.ExpectedCanonicalLinkFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("`LINK` was renamed to `SOURCE`; use `SOURCE` in canonical source mode", failure.message),
    }
}

test "canonical source mode rejects pipe LINK assignment" {
    const outcome = try parseAllocWithOptions(
        std.testing.allocator,
        "button |> LINK { store.sources.button.event.press }\n",
        .{},
    );
    switch (outcome) {
        .ok => |document| {
            var parsed = document;
            parsed.deinit();
            return error.ExpectedCanonicalPipeLinkFailure;
        },
        .err => |failure| try std.testing.expectEqualStrings("`|> LINK { ... }` was removed; declare a source interface and pass or spread it into the element bag instead", failure.message),
    }
}

test "distinguishes module paths from arithmetic division" {
    const outcome = try parseAlloc(std.testing.allocator, "path: Document/new(root: 1)\nratio: total / count\n");
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected parse failure: {s}\n", .{failure.message});
            return error.UnexpectedParseFailure;
        },
    };
    var parsed = document;
    defer parsed.deinit();

    const path_binding = switch (parsed.root.items[0]) {
        .binary => |binding| binding,
        else => return error.ExpectedBinding,
    };
    switch (path_binding.rhs) {
        .apply => |apply| switch (apply.head) {
            .path => |path| try std.testing.expectEqual(@as(usize, 2), path.segments.len),
            else => return error.ExpectedModulePath,
        },
        else => return error.ExpectedApply,
    }

    const ratio_binding = switch (parsed.root.items[1]) {
        .binary => |binding| binding,
        else => return error.ExpectedBinding,
    };
    switch (ratio_binding.rhs) {
        .binary => |binary| try std.testing.expectEqual(ast.BinaryOp.divide, binary.operator),
        else => return error.ExpectedDivision,
    }
}

test "parses phase 2 priority examples" {
    try expectParses("../examples/upstream/counter/counter.bn");
    try expectParses("../examples/upstream/interval/interval.bn");
    try expectParses("../examples/upstream/cells/cells.bn");
    try expectParses("../examples/upstream/timer/timer.bn");
    try expectParses("../examples/upstream/temperature_converter/temperature_converter.bn");
    try expectParses("../examples/terminal/pong/pong.bn");
    try expectParses("../examples/terminal/arkanoid/arkanoid.bn");
    try expectParses("../examples/upstream/todo_mvc/todo_mvc.bn");
    try expectParses("../examples/upstream/todo_mvc_physical/BUILD.bn");
    try expectParses("../examples/upstream/hw_examples/alu.bn");
}

test "parses imported corpus except explicit blockers" {
    try expectCorpusParses();
}

test "parses spaced tagged value object" {
    const source = "x: Oklch [lightness: 0.35]";
    const outcome = try parseAlloc(std.testing.allocator, source);
    const document = switch (outcome) {
        .ok => |document| document,
        .err => |failure| {
            std.debug.print("unexpected parse failure: {s}\n", .{failure.message});
            return error.UnexpectedParseFailure;
        },
    };
    var parsed = document;
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.root.items.len);
    const binding = switch (parsed.root.items[0]) {
        .binary => |binding| binding,
        else => return error.ExpectedBinding,
    };
    try std.testing.expectEqual(ast.BinaryOp.bind, binding.operator);
    switch (binding.rhs) {
        .apply => |apply| try std.testing.expectEqual(ast.ApplyKind.tagged_value, apply.kind),
        else => return error.ExpectedTaggedValue,
    }
}
