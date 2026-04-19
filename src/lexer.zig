const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");

pub const Outcome = union(enum) {
    ok: []ast.Token,
    err: diag.Diagnostic,
};

pub fn lexAlloc(allocator: std.mem.Allocator, source: []const u8) !Outcome {
    var tokens: std.ArrayList(ast.Token) = .empty;
    defer tokens.deinit(allocator);

    var index: usize = 0;
    while (index < source.len) {
        const byte = source[index];
        if (isWhitespace(byte)) {
            index += 1;
            continue;
        }
        if (byte == '-' and peek(source, index + 1) == '-') {
            index = skipComment(source, index + 2);
            continue;
        }
        if (byte < 0x20) {
            return .{ .err = .{
                .message = "unsupported control character",
                .span = ast.Span.init(index, index + 1),
            } };
        }

        if (std.ascii.isDigit(byte)) {
            const end = scanNumericLiteral(source, index);
            try tokens.append(allocator, .{
                .kind = .numeric_literal,
                .span = ast.Span.init(index, end),
            });
            index = end;
            continue;
        }

        if (matchPunctuator(&tokens, allocator, source, &index)) continue;

        const start = index;
        while (index < source.len and !isTokenBoundary(source, index)) : (index += 1) {}

        if (start == index) {
            return .{ .err = .{
                .message = "unsupported character in source",
                .span = ast.Span.init(index, index + 1),
            } };
        }

        const lexeme = source[start..index];
        try tokens.append(allocator, .{
            .kind = classifyBareToken(lexeme),
            .span = ast.Span.init(start, index),
        });
    }

    return .{ .ok = try tokens.toOwnedSlice(allocator) };
}

fn matchPunctuator(
    tokens: *std.ArrayList(ast.Token),
    allocator: std.mem.Allocator,
    source: []const u8,
    index: *usize,
) bool {
    const start = index.*;
    const remaining = source[start..];

    const punctuators = [_]struct { text: []const u8, kind: ast.TokenKind }{
        .{ .text = "...", .kind = .spread },
        .{ .text = "=/=", .kind = .neq },
        .{ .text = "|>", .kind = .pipe_forward },
        .{ .text = "=>", .kind = .fat_arrow },
        .{ .text = "==", .kind = .eq },
        .{ .text = ">=", .kind = .gte },
        .{ .text = "<=", .kind = .lte },
        .{ .text = "=", .kind = .single_equals },
        .{ .text = "(", .kind = .l_paren },
        .{ .text = ")", .kind = .r_paren },
        .{ .text = "[", .kind = .l_bracket },
        .{ .text = "]", .kind = .r_bracket },
        .{ .text = "{", .kind = .l_brace },
        .{ .text = "}", .kind = .r_brace },
        .{ .text = ",", .kind = .comma },
        .{ .text = ":", .kind = .colon },
        .{ .text = ".", .kind = .dot },
        .{ .text = "?", .kind = .question },
        .{ .text = ">", .kind = .gt },
        .{ .text = "<", .kind = .lt },
        .{ .text = "+", .kind = .plus },
        .{ .text = "-", .kind = .minus },
        .{ .text = "*", .kind = .star },
        .{ .text = "/", .kind = .slash },
        .{ .text = "%", .kind = .percent },
        .{ .text = "^", .kind = .caret },
    };

    inline for (punctuators) |punctuator| {
        if (std.mem.startsWith(u8, remaining, punctuator.text)) {
            tokens.append(allocator, .{
                .kind = punctuator.kind,
                .span = ast.Span.init(start, start + punctuator.text.len),
            }) catch unreachable;
            index.* += punctuator.text.len;
            return true;
        }
    }
    return false;
}

fn classifyBareToken(lexeme: []const u8) ast.TokenKind {
    if (std.mem.eql(u8, lexeme, "__")) return .wildcard;
    if (isKeyword(lexeme)) return .keyword;
    if (isPascalIdentifier(lexeme)) return .pascal_identifier;
    if (isSnakeIdentifier(lexeme)) return .snake_identifier;
    return .atom;
}

fn isKeyword(lexeme: []const u8) bool {
    const keywords = [_][]const u8{
        "FUNCTION",
        "BLOCK",
        "LIST",
        "MAP",
        "LINK",
        "LATEST",
        "HOLD",
        "THEN",
        "WHEN",
        "WHILE",
        "SKIP",
        "PASS",
        "PASSED",
        "FLUSH",
        "PULSES",
        "UNPLUGGED",
        "TEXT",
        "BITS",
        "BYTES",
        "MEMORY",
        "DRAIN",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, keyword, lexeme)) return true;
    }
    return false;
}

fn isTokenBoundary(source: []const u8, index: usize) bool {
    const byte = source[index];
    if (isWhitespace(byte)) return true;
    if (byte == '-' and peek(source, index + 1) == '-') return true;

    return switch (byte) {
        '(', ')', '[', ']', '{', '}', ',', ':', '.', '?', '>', '<', '+', '-', '*', '/', '%', '^' => true,
        '|', '=' => true,
        else => false,
    };
}

fn scanNumericLiteral(source: []const u8, start: usize) usize {
    var index = start;
    while (index < source.len and std.ascii.isDigit(source[index])) : (index += 1) {}

    if (index + 1 < source.len and source[index] == '.' and std.ascii.isDigit(source[index + 1])) {
        index += 1;
        while (index < source.len and std.ascii.isDigit(source[index])) : (index += 1) {}
    }

    while (index < source.len and isNumericSuffixByte(source[index])) : (index += 1) {}
    return index;
}

fn isNumericSuffixByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn isPascalIdentifier(lexeme: []const u8) bool {
    if (lexeme.len == 0 or !std.ascii.isUpper(lexeme[0])) return false;
    for (lexeme[1..]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn isSnakeIdentifier(lexeme: []const u8) bool {
    if (lexeme.len == 0) return false;
    if (!std.ascii.isLower(lexeme[0]) and lexeme[0] != '_') return false;
    for (lexeme[1..]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn skipComment(source: []const u8, start: usize) usize {
    var index = start;
    while (index < source.len and source[index] != '\n') : (index += 1) {}
    return index;
}

fn peek(source: []const u8, index: usize) u8 {
    return if (index < source.len) source[index] else 0;
}

fn isWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\n', '\r', '\t' => true,
        else => false,
    };
}

test "lexes reserved DRAIN keyword" {
    const outcome = try lexAlloc(std.testing.allocator, "DRAIN { x }");
    const tokens = switch (outcome) {
        .ok => |tokens| tokens,
        .err => |failure| {
            std.debug.print("unexpected lex failure: {s}\n", .{failure.message});
            return error.UnexpectedLexFailure;
        },
    };
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(ast.TokenKind.keyword, tokens[0].kind);
    try std.testing.expectEqual(ast.TokenKind.l_brace, tokens[1].kind);
    try std.testing.expectEqual(ast.TokenKind.snake_identifier, tokens[2].kind);
    try std.testing.expectEqual(ast.TokenKind.r_brace, tokens[3].kind);
}

test "lexes fixed and dynamic list forms" {
    const outcome = try lexAlloc(std.testing.allocator, "LIST { item }\nBITS[8] { 16uFF }");
    const tokens = switch (outcome) {
        .ok => |tokens| tokens,
        .err => |failure| {
            std.debug.print("unexpected lex failure: {s}\n", .{failure.message});
            return error.UnexpectedLexFailure;
        },
    };
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(tokens.len >= 9);
    try std.testing.expectEqual(ast.TokenKind.keyword, tokens[0].kind);
    try std.testing.expectEqual(ast.TokenKind.keyword, tokens[4].kind);
}

test "keeps colon distinct from single equals" {
    const outcome = try lexAlloc(std.testing.allocator, "value : next = prev");
    const tokens = switch (outcome) {
        .ok => |tokens| tokens,
        .err => |failure| {
            std.debug.print("unexpected lex failure: {s}\n", .{failure.message});
            return error.UnexpectedLexFailure;
        },
    };
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(ast.TokenKind.snake_identifier, tokens[0].kind);
    try std.testing.expectEqual(ast.TokenKind.colon, tokens[1].kind);
    try std.testing.expectEqual(ast.TokenKind.snake_identifier, tokens[2].kind);
    try std.testing.expectEqual(ast.TokenKind.single_equals, tokens[3].kind);
    try std.testing.expectEqual(ast.TokenKind.snake_identifier, tokens[4].kind);
}

test "classifies decimals paths and pascal tags" {
    const outcome = try lexAlloc(std.testing.allocator, "value: 0.5\ncolor: Oklch[lightness: 0.3]\n");
    const tokens = switch (outcome) {
        .ok => |tokens| tokens,
        .err => |failure| {
            std.debug.print("unexpected lex failure: {s}\n", .{failure.message});
            return error.UnexpectedLexFailure;
        },
    };
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(ast.TokenKind.snake_identifier, tokens[0].kind);
    try std.testing.expectEqual(ast.TokenKind.numeric_literal, tokens[2].kind);
    try std.testing.expectEqual(ast.TokenKind.snake_identifier, tokens[3].kind);
    try std.testing.expectEqual(ast.TokenKind.pascal_identifier, tokens[5].kind);
}
